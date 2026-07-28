-- v1.6.1: expose the group controls already represented in the schema as
-- narrow, owner-checked RPCs and provide an explicit owner-only delete path.

begin;

-- The v1.6 policy JSON allowed `everyone`, but the older RPCs still performed
-- a hard admin check. Replace them so the stored policy is genuinely enforced.
create or replace function public.add_group_members(
  p_conversation uuid,
  p_members uuid[]
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me         uuid := public.require_auth();
  v_my_name    text;
  v_candidates uuid[];
  v_rejoined   uuid[];
  v_inserted   uuid[];
  v_joined     uuid[];
  v_active     integer;
begin
  if not exists (
    select 1 from public.conversations c
     where c.id = p_conversation
       and c.kind = 'group'::public.conversation_kind
  ) then
    raise exception 'not_group';
  end if;

  if not public.group_policy_allows(p_conversation, 'add_members', v_me) then
    raise exception 'group_policy_denied';
  end if;

  select coalesce(array_agg(m), '{}') into v_candidates
  from (
    select distinct pr.id as m
      from unnest(coalesce(p_members, '{}'::uuid[])) as u(id)
      join public.profiles pr on pr.id = u.id
     where pr.id <> v_me
       and not public.blocked_with(pr.id)
       and not exists (
         select 1 from public.conversation_members cm
          where cm.conversation_id = p_conversation
            and cm.user_id = pr.id
            and cm.left_at is null
       )
  ) s;

  if coalesce(array_length(v_candidates, 1), 0) = 0 then return 0; end if;

  select count(*) into v_active
    from public.conversation_members cm
   where cm.conversation_id = p_conversation
     and cm.left_at is null;
  if v_active + array_length(v_candidates, 1) > 65 then
    raise exception 'group_full';
  end if;

  with rejoin as (
    update public.conversation_members cm
       set left_at = null,
           role = 'member'::public.member_role,
           request_state = 'accepted',
           unread_count = 0,
           last_read_at = now(),
           joined_at = now()
     where cm.conversation_id = p_conversation
       and cm.user_id = any (v_candidates)
       and cm.left_at is not null
    returning cm.user_id
  )
  select coalesce(array_agg(user_id), '{}') into v_rejoined from rejoin;

  with ins as (
    insert into public.conversation_members (
      conversation_id, user_id, role, request_state
    )
    select p_conversation, t.m, 'member'::public.member_role, 'accepted'
      from unnest(v_candidates) as t(m)
     where not exists (
       select 1 from public.conversation_members cm
        where cm.conversation_id = p_conversation
          and cm.user_id = t.m
     )
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}') into v_inserted from ins;

  v_joined := v_rejoined || v_inserted;
  select display_name into v_my_name
    from public.profiles where id = v_me;
  insert into public.messages (conversation_id, author_id, kind, body)
  select p_conversation, v_me, 'system'::public.message_kind,
         v_my_name || ' added ' || pr.display_name
    from public.profiles pr
   where pr.id = any (v_joined);

  return coalesce(array_length(v_joined, 1), 0);
end;
$$;

create or replace function public.update_group_info(
  p_conversation uuid,
  p_title text default null,
  p_description text default null,
  p_avatar_path text default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me uuid := public.require_auth();
  v_conv public.conversations%rowtype;
  v_title text;
  v_name text;
begin
  select * into v_conv
    from public.conversations c
   where c.id = p_conversation
     and c.kind = 'group'::public.conversation_kind;
  if not found then raise exception 'not_group'; end if;
  if not public.group_policy_allows(p_conversation, 'edit_info', v_me) then
    raise exception 'group_policy_denied';
  end if;

  if p_title is not null then
    v_title := trim(p_title);
    if v_title = '' then raise exception 'title_required'; end if;
    if char_length(v_title) > 60 then raise exception 'title_too_long'; end if;
  end if;

  update public.conversations
     set title = coalesce(v_title, title),
         description = case when p_description is null then description
                            else nullif(trim(p_description), '') end,
         avatar_path = coalesce(p_avatar_path, avatar_path),
         updated_at = now()
   where id = p_conversation;

  if v_title is not null and v_title is distinct from v_conv.title then
    select display_name into v_name from public.profiles where id = v_me;
    insert into public.messages (conversation_id, author_id, kind, body)
    values (
      p_conversation,
      v_me,
      'system'::public.message_kind,
      v_name || ' renamed the group to "' || v_title || '"'
    );
  end if;
end;
$$;

create or replace function public.clear_group_avatar(
  p_conversation uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if not public.group_policy_allows(
    p_conversation, 'edit_info', auth.uid()
  ) then
    raise exception 'group_policy_denied';
  end if;

  update public.conversations
     set avatar_path = null,
         updated_at = now()
   where id = p_conversation
     and kind = 'group'::public.conversation_kind;
  if not found then raise exception 'not_group'; end if;
end;
$$;

create or replace function public.set_group_join_approval(
  p_conversation uuid,
  p_required boolean
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if not exists (
    select 1
      from public.conversation_members cm
      join public.conversations c on c.id = cm.conversation_id
     where cm.conversation_id = p_conversation
       and cm.user_id = auth.uid()
       and cm.role = 'owner'::public.member_role
       and cm.left_at is null
       and cm.request_state = 'accepted'
       and c.kind = 'group'::public.conversation_kind
  ) then
    raise exception 'owner_required';
  end if;

  update public.conversations
     set join_approval_required = coalesce(p_required, false),
         updated_at = now()
   where id = p_conversation
     and kind = 'group'::public.conversation_kind;

  if not found then raise exception 'group_not_found'; end if;
  return coalesce(p_required, false);
end;
$$;

create or replace function public.delete_group(
  p_conversation uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if not exists (
    select 1
      from public.conversation_members cm
      join public.conversations c on c.id = cm.conversation_id
     where cm.conversation_id = p_conversation
       and cm.user_id = auth.uid()
       and cm.role = 'owner'::public.member_role
       and cm.left_at is null
       and cm.request_state = 'accepted'
       and c.kind = 'group'::public.conversation_kind
  ) then
    raise exception 'owner_required';
  end if;

  delete from public.conversations
   where id = p_conversation
     and kind = 'group'::public.conversation_kind;

  if not found then raise exception 'group_not_found'; end if;
end;
$$;

revoke execute on function public.set_group_join_approval(uuid, boolean)
  from public, anon;
grant execute on function public.set_group_join_approval(uuid, boolean)
  to authenticated, service_role;

revoke execute on function public.delete_group(uuid)
  from public, anon;
grant execute on function public.delete_group(uuid)
  to authenticated, service_role;

commit;
