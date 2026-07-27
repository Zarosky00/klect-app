begin;

-- Reliable calling stays disabled until Firebase delivery and Cloudflare TURN
-- health are configured. The RPC is the only client-visible flag surface.
create table if not exists public.feature_flags (
  key text primary key,
  enabled boolean not null default false,
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.feature_flags enable row level security;
revoke all on table public.feature_flags from public, anon, authenticated;
grant all on table public.feature_flags to service_role;

insert into public.feature_flags (key, enabled, config)
values (
  'reliable_calls',
  false,
  '{"requires":["firebase","cloudflare_turn"]}'::jsonb
)
on conflict (key) do nothing;

create or replace function public.call_feature_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select f.enabled from public.feature_flags f
      where f.key = 'reliable_calls'),
    false
  )
$$;


-- FCM device-token lifecycle extends the existing push fanout contract.
alter table public.push_tokens
  add column if not exists device_id text,
  add column if not exists app_version text,
  add column if not exists enabled boolean not null default true,
  add column if not exists last_seen_at timestamptz not null default now();

create index if not exists push_tokens_enabled_user_idx
  on public.push_tokens (user_id, last_seen_at desc)
  where enabled;

create or replace function public.register_push_token(
  p_token text,
  p_platform text,
  p_device_id text default null,
  p_app_version text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
begin
  if nullif(trim(p_token), '') is null then raise exception 'bad_token'; end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'bad_platform';
  end if;

  insert into public.push_tokens (
    user_id, token, platform, device_id, app_version, enabled, last_seen_at
  ) values (
    me, trim(p_token), p_platform, nullif(trim(p_device_id), ''),
    nullif(trim(p_app_version), ''), true, now()
  )
  on conflict (user_id, token) do update
    set platform = excluded.platform,
        device_id = excluded.device_id,
        app_version = excluded.app_version,
        enabled = true,
        last_seen_at = now();
end;
$$;

create or replace function public.unregister_push_token(
  p_token text
) returns void
language sql
security definer
set search_path = ''
as $$
  update public.push_tokens
  set enabled = false,
      last_seen_at = now()
  where user_id = public.require_auth()
    and token = p_token
$$;


-- Per-user call privacy.
alter table public.profiles
  add column if not exists allow_calls_from text not null default 'following';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_allow_calls_from_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_allow_calls_from_check
      check (allow_calls_from in ('everyone', 'following', 'matches', 'nobody'));
  end if;
end
$$;


-- Durable participant outcomes and expiry diagnostics.
alter table public.calls
  add column if not exists expires_at timestamptz,
  add column if not exists answered_by uuid references public.profiles(id),
  add column if not exists state_version integer not null default 1,
  add column if not exists diagnostics jsonb not null default '{}'::jsonb;

update public.calls
set expires_at = created_at + interval '45 seconds'
where expires_at is null;

alter table public.calls
  alter column expires_at set default (now() + interval '45 seconds'),
  alter column expires_at set not null;

alter table public.call_participants
  add column if not exists invite_state text not null default 'ringing',
  add column if not exists answered_at timestamptz,
  add column if not exists declined_at timestamptz,
  add column if not exists answered_device_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'call_participants_invite_state_check'
      and conrelid = 'public.call_participants'::regclass
  ) then
    alter table public.call_participants
      add constraint call_participants_invite_state_check
      check (
        invite_state in (
          'ringing', 'accepted', 'declined', 'missed',
          'busy', 'answered_elsewhere', 'ended'
        )
      );
  end if;
end
$$;

create unique index if not exists calls_one_live_per_conversation_idx
  on public.calls (conversation_id)
  where status in ('ringing', 'active');

create index if not exists calls_ringing_expiry_idx
  on public.calls (expires_at)
  where status = 'ringing';


create or replace function public.call_peer_allowed(
  p_caller uuid,
  p_callee uuid
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    p_caller is not null
    and p_callee is not null
    and p_caller <> p_callee
    and not exists (
      select 1 from public.blocks b
      where (b.blocker_id = p_caller and b.blocked_id = p_callee)
         or (b.blocker_id = p_callee and b.blocked_id = p_caller)
    )
    and coalesce((
      select case p.allow_calls_from
        when 'everyone' then true
        when 'following' then exists (
          select 1 from public.follows f
          where f.follower_id = p_callee
            and f.following_id = p_caller
        )
        when 'matches' then exists (
          select 1 from public.user_matches m
          where m.user_id = p_callee and m.other_id = p_caller
        )
        else false
      end
      from public.profiles p
      where p.id = p_callee
        and not p.is_suspended
    ), false)
$$;

create or replace function public.record_call_activity(
  p_call public.calls,
  p_label text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.messages
  set body = p_label,
      updated_at = now()
  where call_id = p_call.id
    and kind = 'call_event'
    and deleted_at is null;

  if not found then
    insert into public.messages (
      conversation_id, author_id, kind, body, call_id
    ) values (
      p_call.conversation_id, p_call.created_by, 'call_event', p_label, p_call.id
    );
  end if;
end;
$$;


create or replace function public.start_call(
  p_conversation uuid,
  p_kind public.call_kind
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_peer uuid;
  v_call public.calls%rowtype;
begin
  if not public.call_feature_enabled() then
    raise exception 'calls_unavailable';
  end if;

  select cm.user_id into v_peer
  from public.conversations c
  join public.conversation_members mine
    on mine.conversation_id = c.id
   and mine.user_id = me
   and mine.left_at is null
  join public.conversation_members cm
    on cm.conversation_id = c.id
   and cm.user_id <> me
   and cm.left_at is null
  where c.id = p_conversation
    and c.kind = 'dm'
  limit 1;

  if v_peer is null then raise exception 'not_dm_member'; end if;
  if not public.call_peer_allowed(me, v_peer) then
    raise exception 'calls_not_allowed';
  end if;
  if exists (
    select 1 from public.calls c
    join public.call_participants cp on cp.call_id = c.id
    where c.status in ('ringing', 'active')
      and cp.user_id in (me, v_peer)
  ) then
    raise exception 'participant_busy';
  end if;

  insert into public.calls (
    conversation_id, created_by, kind, status, expires_at
  ) values (
    p_conversation, me, p_kind, 'ringing', now() + interval '45 seconds'
  )
  returning * into v_call;

  insert into public.call_participants (
    call_id, user_id, invite_state, joined_at, answered_at
  ) values
    (v_call.id, me, 'accepted', now(), now()),
    (v_call.id, v_peer, 'ringing', null, null);

  return to_jsonb(v_call);
exception
  when unique_violation then
    raise exception 'conversation_busy';
end;
$$;

create or replace function public.answer_call(
  p_call uuid,
  p_device_id text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id = p_call for update;
  if not found then raise exception 'call_not_found'; end if;
  if not exists (
    select 1 from public.call_participants
    where call_id = p_call and user_id = me
  ) then raise exception 'not_call_participant'; end if;
  if v_call.created_by = me then raise exception 'caller_cannot_answer'; end if;
  if v_call.status <> 'ringing' then raise exception 'call_not_ringing'; end if;

  if v_call.expires_at <= now() then
    update public.calls
    set status = 'missed', ended_at = now(), end_reason = 'timeout',
        state_version = state_version + 1
    where id = p_call
    returning * into v_call;
    update public.call_participants
    set invite_state = 'missed'
    where call_id = p_call and user_id <> v_call.created_by;
    perform public.record_call_activity(v_call, 'Missed call');
    raise exception 'call_expired';
  end if;

  update public.calls
  set status = 'active',
      started_at = coalesce(started_at, now()),
      answered_by = me,
      state_version = state_version + 1
  where id = p_call
  returning * into v_call;

  update public.call_participants
  set invite_state = 'accepted',
      joined_at = coalesce(joined_at, now()),
      answered_at = coalesce(answered_at, now()),
      answered_device_id = nullif(trim(p_device_id), '')
  where call_id = p_call and user_id = me;

  return to_jsonb(v_call);
end;
$$;

create or replace function public.decline_call(
  p_call uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_call public.calls%rowtype;
begin
  select * into v_call from public.calls where id = p_call for update;
  if not found then raise exception 'call_not_found'; end if;
  if v_call.created_by = me then raise exception 'caller_cannot_decline'; end if;
  if not exists (
    select 1 from public.call_participants
    where call_id = p_call and user_id = me
  ) then raise exception 'not_call_participant'; end if;
  if v_call.status <> 'ringing' then raise exception 'call_not_ringing'; end if;

  update public.calls
  set status = 'declined',
      ended_at = now(),
      end_reason = 'declined',
      state_version = state_version + 1
  where id = p_call
  returning * into v_call;

  update public.call_participants
  set invite_state = case when user_id = me then 'declined' else 'ended' end,
      declined_at = case when user_id = me then now() else declined_at end,
      left_at = now()
  where call_id = p_call;

  perform public.record_call_activity(v_call, 'Call declined');
  return to_jsonb(v_call);
end;
$$;

create or replace function public.end_call(
  p_call uuid,
  p_reason text default 'ended',
  p_outcome public.call_status default 'ended'
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_call public.calls%rowtype;
  v_duration integer;
begin
  select * into v_call from public.calls where id = p_call for update;
  if not found then raise exception 'call_not_found'; end if;
  if not exists (
    select 1 from public.call_participants
    where call_id = p_call and user_id = me
  ) then raise exception 'not_call_participant'; end if;
  if v_call.status not in ('ringing', 'active') then
    return to_jsonb(v_call);
  end if;
  if p_outcome not in ('ended', 'missed', 'failed') then
    raise exception 'bad_call_outcome';
  end if;
  if p_outcome = 'missed' and (
    v_call.status <> 'ringing' or v_call.created_by <> me
  ) then
    raise exception 'bad_missed_transition';
  end if;

  v_duration := case
    when v_call.started_at is null then 0
    else greatest(0, floor(extract(epoch from (now() - v_call.started_at)))::int)
  end;

  update public.calls
  set status = p_outcome,
      ended_at = now(),
      duration_seconds = v_duration,
      end_reason = left(coalesce(nullif(trim(p_reason), ''), 'ended'), 120),
      state_version = state_version + 1
  where id = p_call
  returning * into v_call;

  update public.call_participants
  set invite_state = 'ended',
      left_at = now()
  where call_id = p_call;

  perform public.record_call_activity(
    v_call,
    case
      when p_outcome = 'missed' then 'Missed call'
      when p_outcome = 'failed' then 'Call failed'
      when v_duration > 0 then
        'Call · ' || lpad((v_duration / 60)::text, 2, '0') || ':' ||
        lpad((v_duration % 60)::text, 2, '0')
      else 'Call ended'
    end
  );
  return to_jsonb(v_call);
end;
$$;

create or replace function public.expire_ringing_calls()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_call public.calls%rowtype;
  v_count integer := 0;
begin
  for v_call in
    update public.calls
    set status = 'missed',
        ended_at = now(),
        end_reason = 'timeout',
        state_version = state_version + 1
    where status = 'ringing' and expires_at <= now()
    returning *
  loop
    update public.call_participants
    set invite_state = case
      when user_id = v_call.created_by then 'ended'
      else 'missed'
    end,
    left_at = now()
    where call_id = v_call.id;
    perform public.record_call_activity(v_call, 'Missed call');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.join_call(
  p_call uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
begin
  if not exists (
    select 1 from public.calls c
    join public.call_participants cp on cp.call_id = c.id
    where c.id = p_call and c.status = 'active' and cp.user_id = me
  ) then raise exception 'call_not_active'; end if;
  update public.call_participants
  set joined_at = coalesce(joined_at, now()),
      invite_state = 'accepted'
  where call_id = p_call and user_id = me;
end;
$$;

create or replace function public.leave_call(
  p_call uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
begin
  update public.call_participants
  set left_at = now()
  where call_id = p_call and user_id = me;
end;
$$;

create or replace function public.send_call_signal(
  p_call uuid,
  p_recipient uuid,
  p_type text,
  p_payload jsonb
) returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_id bigint;
begin
  if p_recipient is null or p_recipient = me then
    raise exception 'bad_signal_recipient';
  end if;
  if p_type not in ('offer', 'answer', 'ice', 'renegotiate', 'bye') then
    raise exception 'bad_signal_type';
  end if;
  if jsonb_typeof(p_payload) <> 'object' then
    raise exception 'bad_signal_payload';
  end if;
  if not exists (
    select 1
    from public.calls c
    join public.call_participants sender
      on sender.call_id = c.id and sender.user_id = me
    join public.call_participants recipient
      on recipient.call_id = c.id and recipient.user_id = p_recipient
    where c.id = p_call
      and c.status in ('ringing', 'active')
  ) then raise exception 'invalid_signal_recipient'; end if;

  insert into public.call_signals (
    call_id, sender_id, recipient_id, type, payload
  ) values (
    p_call, me, p_recipient, p_type, p_payload
  )
  returning id into v_id;
  return v_id;
end;
$$;


-- All call mutations now pass through legal-transition RPCs.
drop policy if exists calls_insert on public.calls;
drop policy if exists calls_update on public.calls;
drop policy if exists call_parts_insert on public.call_participants;
drop policy if exists call_parts_update on public.call_participants;
drop policy if exists call_parts_delete on public.call_participants;
drop policy if exists signals_insert on public.call_signals;

revoke insert, update, delete on table public.calls from authenticated;
revoke insert, update, delete on table public.call_participants
  from authenticated;
revoke insert, update, delete on table public.call_signals from authenticated;

revoke execute on function public.call_peer_allowed(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.record_call_activity(public.calls, text)
  from public, anon, authenticated;
revoke execute on function public.expire_ringing_calls()
  from public, anon, authenticated;
grant execute on function public.expire_ringing_calls() to service_role;

revoke execute on function public.call_feature_enabled()
  from public, anon;
revoke execute on function public.register_push_token(text, text, text, text)
  from public, anon;
revoke execute on function public.unregister_push_token(text)
  from public, anon;
revoke execute on function public.start_call(uuid, public.call_kind)
  from public, anon;
revoke execute on function public.answer_call(uuid, text)
  from public, anon;
revoke execute on function public.decline_call(uuid)
  from public, anon;
revoke execute on function public.end_call(uuid, text, public.call_status)
  from public, anon;
revoke execute on function public.join_call(uuid)
  from public, anon;
revoke execute on function public.leave_call(uuid)
  from public, anon;
revoke execute on function public.send_call_signal(uuid, uuid, text, jsonb)
  from public, anon;

grant execute on function public.call_feature_enabled()
  to authenticated, service_role;
grant execute on function public.register_push_token(text, text, text, text)
  to authenticated, service_role;
grant execute on function public.unregister_push_token(text)
  to authenticated, service_role;
grant execute on function public.start_call(uuid, public.call_kind)
  to authenticated, service_role;
grant execute on function public.answer_call(uuid, text)
  to authenticated, service_role;
grant execute on function public.decline_call(uuid)
  to authenticated, service_role;
grant execute on function public.end_call(uuid, text, public.call_status)
  to authenticated, service_role;
grant execute on function public.join_call(uuid)
  to authenticated, service_role;
grant execute on function public.leave_call(uuid)
  to authenticated, service_role;
grant execute on function public.send_call_signal(uuid, uuid, text, jsonb)
  to authenticated, service_role;

commit;
