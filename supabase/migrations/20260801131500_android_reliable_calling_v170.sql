begin;

-- Global calling stays off during physical QA. The two-account allowlist lives
-- in the existing private feature flag config and is evaluated server-side.
update public.feature_flags
set config = jsonb_set(
      config,
      '{qa_allowlist}',
      case
        when jsonb_typeof(config -> 'qa_allowlist') = 'array'
          then config -> 'qa_allowlist'
        else '[]'::jsonb
      end,
      true
    ),
    updated_at = now()
where key = 'reliable_calls';

create or replace function public.call_feature_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select f.enabled or (
      auth.uid() is not null
      and jsonb_typeof(f.config -> 'qa_allowlist') = 'array'
      and exists (
        select 1
        from jsonb_array_elements_text(f.config -> 'qa_allowlist') allowed(user_id)
        where allowed.user_id = auth.uid()::text
      )
    )
    from public.feature_flags f
    where f.key = 'reliable_calls'
  ), false)
$$;

-- A call owns exactly one recipient notification. This is the durable source
-- consumed by the database webhook and makes retries transactionally safe.
create unique index if not exists notifications_call_unique_idx
  on public.notifications (user_id, call_id)
  where call_id is not null and type = 'call';

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

  insert into public.notifications (
    user_id, actor_id, type, call_id, conversation_id, body
  ) values (
    v_peer,
    me,
    'call',
    v_call.id,
    p_conversation,
    case p_kind
      when 'video' then 'Incoming video call'
      else 'Incoming audio call'
    end
  )
  on conflict (user_id, call_id)
    where call_id is not null and type = 'call'
    do nothing;

  return to_jsonb(v_call);
exception
  when unique_violation then
    raise exception 'conversation_busy';
end;
$$;

-- WebRTC signals are replayable only while a call is live. Frequent cleanup
-- keeps terminated-call payloads short without racing reconnects.
create or replace function public.cleanup_call_signals()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  removed integer;
begin
  delete from public.call_signals signal
  using public.calls call
  where signal.call_id = call.id
    and (
      signal.created_at < now() - interval '2 hours'
      or (
        call.status in ('ended', 'missed', 'declined', 'failed')
        and signal.created_at < now() - interval '5 minutes'
      )
    );
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.cleanup_call_signals()
  from public, anon, authenticated;
grant execute on function public.cleanup_call_signals() to service_role;

do $$
declare
  job bigint;
begin
  for job in
    select jobid from cron.job
    where jobname in ('klect-call-expiry', 'klect-call-signal-cleanup')
  loop
    perform cron.unschedule(job);
  end loop;
end
$$;

select cron.schedule(
  'klect-call-expiry',
  '15 seconds',
  'select public.expire_ringing_calls()'
);

select cron.schedule(
  'klect-call-signal-cleanup',
  '*/15 * * * *',
  'select public.cleanup_call_signals()'
);

commit;
