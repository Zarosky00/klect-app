-- Chat, calls and notifications overhaul.
--
-- One migration, applied to `new_klect`. Everything here is additive; nothing is
-- dropped. Sections:
--   1. Notification category taxonomy (one source of truth, 11 categories)
--   2. Account-synced notification preference store
--   3. Delete-for-me store plus the author-only tombstone RPC
--
-- Note on the enum: `alter type ... add value` may run inside a transaction on
-- PG12+, but the new label may not be *used* in that same transaction. Every
-- comparison below therefore goes through `p_type::text` rather than an enum
-- literal, so this file stays a single atomic migration.

begin;

-- ---------------------------------------------------------------------------
-- 1. Category taxonomy
-- ---------------------------------------------------------------------------

-- Additive, idempotent: gives the `recommendations` category a real backing label.
alter type public.notification_type add value if not exists 'recommendation';

-- Total over the enum: every label lands in exactly one of the 11 categories and
-- anything unmapped (including labels added later) is absorbed by `system`.
-- Compares on `::text` so the freshly added `recommendation` label is safe to
-- reference in the same transaction.
create or replace function public.notification_category(
  p_type public.notification_type
) returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case p_type::text
    when 'like' then 'likes'
    when 'save' then 'saves'
    when 'repost' then 'reposts'
    when 'comment' then 'comments_and_replies'
    when 'reply' then 'comments_and_replies'
    when 'mention' then 'mentions'
    when 'follow' then 'follows'
    when 'message' then 'messages'
    when 'call' then 'calls'
    when 'recommendation' then 'recommendations'
    when 'match' then 'matches'
    else 'system'
  end
$$;

revoke all on function public.notification_category(public.notification_type)
  from public, anon;
grant execute on function public.notification_category(public.notification_type)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. Account-synced notification preferences
-- ---------------------------------------------------------------------------

alter table public.user_preferences
  add column if not exists notifications jsonb not null default '{}'::jsonb;

-- Whole-payload validation, own-row only, returns the authoritative set.
-- A single bad key or non-boolean value rejects the ENTIRE write (5.4).
create or replace function public.set_notification_preferences(
  p_notifications jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_allowed text[] := array[
    'likes', 'saves', 'reposts', 'comments_and_replies',
    'mentions', 'follows', 'messages', 'calls',
    'recommendations', 'matches', 'system'
  ];
  k text;
  v jsonb;
begin
  if p_notifications is null or jsonb_typeof(p_notifications) <> 'object' then
    raise exception 'bad_notification_preferences';
  end if;

  for k, v in select key, value from jsonb_each(p_notifications) loop
    if k <> all(v_allowed) or jsonb_typeof(v) <> 'boolean' then
      raise exception 'bad_notification_preferences';
    end if;
  end loop;

  insert into public.user_preferences (user_id, notifications, updated_at)
  values (me, p_notifications, now())
  on conflict (user_id) do update
    set notifications = excluded.notifications,
        updated_at = now();

  return (
    select p.notifications
    from public.user_preferences p
    where p.user_id = me
  );
end;
$$;

revoke all on function public.set_notification_preferences(jsonb)
  from public, anon;
grant execute on function public.set_notification_preferences(jsonb)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Delete-for-me and the author-only tombstone
-- ---------------------------------------------------------------------------

-- One row per (message, viewer). The composite primary key is what makes the
-- hide idempotent: a repeat conflicts and is dropped, so a viewer can never
-- accumulate duplicates (12.7). `conversation_id` is denormalised so a thread
-- can fetch its own hidden set with one indexed read.
create table if not exists public.message_hides (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index if not exists message_hides_viewer_conversation_idx
  on public.message_hides (user_id, conversation_id);

alter table public.message_hides enable row level security;

-- Own-row only, for both select and insert: hiding is private and nobody can
-- hide a message on somebody else's behalf (12.8).
drop policy if exists message_hides_select_own on public.message_hides;
create policy message_hides_select_own
  on public.message_hides
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists message_hides_insert_own on public.message_hides;
create policy message_hides_insert_own
  on public.message_hides
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

revoke all on table public.message_hides from anon;
grant select, insert on table public.message_hides to authenticated;
grant all on table public.message_hides to service_role;

-- Hide for the caller only. Membership is proved by the join, so a non-member
-- cannot learn whether the message exists; a repeat is a silent success (12.7).
create or replace function public.hide_message_for_me(
  p_message uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_conversation uuid;
begin
  select m.conversation_id into v_conversation
    from public.messages m
    join public.conversation_members cm
      on cm.conversation_id = m.conversation_id
     and cm.user_id = me
   where m.id = p_message;

  if v_conversation is null then
    raise exception 'not_member';
  end if;

  insert into public.message_hides (message_id, user_id, conversation_id)
  values (p_message, me, v_conversation)
  on conflict (message_id, user_id) do nothing;
end;
$$;

revoke all on function public.hide_message_for_me(uuid) from public, anon;
grant execute on function public.hide_message_for_me(uuid)
  to authenticated, service_role;

-- Author-only tombstone. The row survives: `id`, `author_id`, `reply_to_id` and
-- `created_at` are never written, so thread order and the reply graph hold
-- (11.1, 11.3). `for update` serialises concurrent callers and the `deleted_at`
-- guard makes a repeat return the identical row (11.9).
create or replace function public.delete_message_for_everyone(
  p_message uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_message public.messages%rowtype;
  v_is_newest boolean;
begin
  select * into v_message
    from public.messages
   where id = p_message
     for update;

  if not found then
    raise exception 'message_not_found';
  end if;

  if v_message.author_id <> me then
    raise exception 'not_message_author';
  end if;

  if v_message.deleted_at is null then
    -- `conversations` tracks the preview, not the message id, so "newest" is
    -- decided on (created_at, id) — the same order the thread reads in.
    select not exists (
      select 1
        from public.messages m2
       where m2.conversation_id = v_message.conversation_id
         and (m2.created_at, m2.id) > (v_message.created_at, v_message.id)
    ) into v_is_newest;

    update public.messages
       set deleted_at = now(),
           body = '',
           attachments = '[]'::jsonb,
           updated_at = now()
     where id = p_message
    returning * into v_message;

    -- Server-owned preview, refreshed only when this really was the newest
    -- message; an older deletion leaves the inbox line alone (11.8).
    if v_is_newest then
      update public.conversations c
         set last_message_preview = 'Message deleted',
             updated_at = now()
       where c.id = v_message.conversation_id;
    end if;
  end if;

  return to_jsonb(v_message);
end;
$$;

revoke all on function public.delete_message_for_everyone(uuid) from public, anon;
grant execute on function public.delete_message_for_everyone(uuid)
  to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. Call and group RPC deltas
-- ---------------------------------------------------------------------------

-- `calls.diagnostics` arrived with 20260727153442_reliable_call_state.sql; the
-- additive guard keeps this migration standalone-safe on any older branch.
alter table public.calls
  add column if not exists diagnostics jsonb not null default '{}'::jsonb;

-- decline_call gains a reason so a busy decline can say why (7.16). The arg
-- list changes, so the single-argument function is dropped first: leaving both
-- in place would make `decline_call(uuid)` ambiguous. Dropping a function
-- touches no rows.
drop function if exists public.decline_call(uuid);

create or replace function public.decline_call(
  p_call uuid,
  p_reason text default 'declined'
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
      -- Trimmed, non-empty, capped: the reason is caller-supplied text that
      -- ends up on a durable row, so it is bounded like every other end_reason.
      end_reason = left(coalesce(nullif(trim(p_reason), ''), 'declined'), 120),
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

comment on function public.decline_call(uuid, text) is
  'Recipient declines a ringing call; the optional reason is trimmed and capped at 120 characters.';

revoke all on function public.decline_call(uuid, text) from public, anon;
grant execute on function public.decline_call(uuid, text)
  to authenticated, service_role;

-- end_call gains the client elapsed value (7.8). Same reasoning as above: the
-- three-argument form is dropped so a three-argument call stays unambiguous.
drop function if exists public.end_call(uuid, text, public.call_status);

create or replace function public.end_call(
  p_call uuid,
  p_reason text default 'ended',
  p_outcome public.call_status default 'ended',
  p_client_elapsed_seconds integer default null
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
  -- Already terminal: return the first outcome unchanged so a repeat from a
  -- retrying client is a no-op (7.11).
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

  -- The stored duration stays server-computed from `started_at`. The client
  -- value is diagnostics only and never feeds `duration_seconds` (7.8).
  v_duration := case
    when v_call.started_at is null then 0
    else greatest(0, floor(extract(epoch from (now() - v_call.started_at)))::int)
  end;

  update public.calls
  set status = p_outcome,
      ended_at = now(),
      duration_seconds = v_duration,
      end_reason = left(coalesce(nullif(trim(p_reason), ''), 'ended'), 120),
      -- Merge, never replace, and clamp to a day so a bad clock cannot store
      -- an absurd elapsed value. A null argument leaves diagnostics alone.
      diagnostics = case
        when p_client_elapsed_seconds is null then diagnostics
        else coalesce(diagnostics, '{}'::jsonb) || jsonb_build_object(
          'client_elapsed_seconds',
          least(greatest(coalesce(p_client_elapsed_seconds, 0), 0), 86400)
        )
      end,
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

comment on function public.end_call(uuid, text, public.call_status, integer) is
  'Terminates a call. duration_seconds stays server-computed; the client elapsed value is merged into diagnostics clamped to [0, 86400].';

revoke all on function public.end_call(uuid, text, public.call_status, integer)
  from public, anon;
grant execute on function public.end_call(uuid, text, public.call_status, integer)
  to authenticated, service_role;

-- Relay verdicts and other per-call observations, recorded for operator review
-- (10.3, 10.4). Participant-only, and a merge so two keys written by the two
-- ends of the same call cannot clobber each other.
create or replace function public.record_call_diagnostic(
  p_call uuid,
  p_key text,
  p_value jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_key text := left(trim(coalesce(p_key, '')), 120);
begin
  if v_key = '' then
    raise exception 'bad_diagnostic_key';
  end if;

  if not exists (
    select 1 from public.call_participants
    where call_id = p_call and user_id = me
  ) then
    raise exception 'not_call_participant';
  end if;

  update public.calls
  set diagnostics = coalesce(diagnostics, '{}'::jsonb)
      || jsonb_build_object(v_key, coalesce(p_value, 'null'::jsonb))
  where id = p_call;

  if not found then
    raise exception 'call_not_found';
  end if;
end;
$$;

comment on function public.record_call_diagnostic(uuid, text, jsonb) is
  'Participant-only: merges one key into calls.diagnostics without replacing the existing object.';

revoke all on function public.record_call_diagnostic(uuid, text, jsonb)
  from public, anon;
grant execute on function public.record_call_diagnostic(uuid, text, jsonb)
  to authenticated, service_role;

-- set_group_member_role widened (13.5, 13.6, 13.7). Same signature, so a
-- replace is enough. Ownership itself stays owner-only; 'admin' and 'member'
-- become admin-manageable, and the owner can never be targeted.
create or replace function public.set_group_member_role(
  p_conversation uuid,
  p_member uuid,
  p_role public.member_role
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me          uuid := public.require_auth();
  v_my_role     public.member_role;
  v_target_role public.member_role;
begin
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation and c.kind = 'group'
  ) then
    raise exception 'not_group';
  end if;

  select cm.role into v_my_role
  from public.conversation_members cm
  where cm.conversation_id = p_conversation
    and cm.user_id = v_me
    and cm.left_at is null;
  if v_my_role is null then
    raise exception 'not_member';
  end if;

  -- Transferring ownership is still owner-only (13.6).
  if p_role = 'owner' then
    if v_my_role <> 'owner' then
      raise exception 'not_owner';
    end if;
  elsif not public.is_conversation_admin(p_conversation) then
    -- Managing 'admin' and 'member' is open to admins as well as the owner
    -- (13.5); a plain member is refused.
    raise exception 'not_admin';
  end if;

  select cm.role into v_target_role
  from public.conversation_members cm
  where cm.conversation_id = p_conversation
    and cm.user_id = p_member
    and cm.left_at is null;
  if v_target_role is null then
    raise exception 'not_member';
  end if;

  -- Unchanged owner self-target behaviour: setting your own role to 'owner' is
  -- an idempotent no-op, anything else is a refused self-demotion. An admin
  -- self-target falls through to the normal path below.
  if p_member = v_me and v_my_role = 'owner' then
    if p_role <> 'owner' then
      raise exception 'cannot_demote_owner';
    end if;
    return;
  end if;

  -- The owner is never a target: demoting the owner would leave the group
  -- ownerless, so a transfer is the only way ownership moves (13.7).
  if v_target_role = 'owner' then
    raise exception 'not_owner';
  end if;

  if p_role = 'owner' then
    -- ownership transfer: target -> owner, previous owner -> admin
    update public.conversation_members
       set role = 'owner'
     where conversation_id = p_conversation and user_id = p_member;

    update public.conversation_members
       set role = 'admin'
     where conversation_id = p_conversation and user_id = v_me;
  else
    update public.conversation_members
       set role = p_role
     where conversation_id = p_conversation and user_id = p_member;
  end if;
end;
$$;

comment on function public.set_group_member_role(uuid, uuid, public.member_role) is
  'Owner transfers ownership; owner or admin may set admin/member. The owner cannot be targeted.';

revoke all on function public.set_group_member_role(uuid, uuid, public.member_role)
  from public, anon;
grant execute on function public.set_group_member_role(uuid, uuid, public.member_role)
  to authenticated, service_role;

commit;
