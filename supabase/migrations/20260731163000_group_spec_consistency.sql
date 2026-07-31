-- Align the group RPC contract with the chat/calls/notifications specification:
-- 256 active rows maximum, identity limits enforced on trimmed values, and one
-- system message for each visible identity change.

begin;

create or replace function public.create_group(
  p_title text,
  p_members uuid[],
  p_description text default null,
  p_avatar_path text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me           uuid := public.require_auth();
  v_title        text := trim(coalesce(p_title, ''));
  v_description  text := nullif(trim(p_description), '');
  v_members      uuid[];
  v_conversation uuid;
  v_my_name      text;
begin
  if v_title = '' then raise exception 'title_required'; end if;
  if char_length(v_title) > 60 then raise exception 'title_too_long'; end if;
  if char_length(coalesce(v_description, '')) > 500 then
    raise exception 'description_too_long';
  end if;

  -- The owner consumes one of the 256 active-member slots.
  select coalesce(array_agg(m), '{}') into v_members
  from (
    select distinct pr.id as m
      from unnest(coalesce(p_members, '{}'::uuid[])) as u(id)
      join public.profiles pr on pr.id = u.id
     where pr.id <> v_me
       and not public.blocked_with(pr.id)
     limit 255
  ) s;

  if coalesce(array_length(v_members, 1), 0) = 0 then
    raise exception 'group_needs_members';
  end if;

  insert into public.conversations (
    kind, title, description, avatar_path, created_by
  ) values (
    'group'::public.conversation_kind,
    v_title,
    v_description,
    p_avatar_path,
    v_me
  ) returning id into v_conversation;

  insert into public.conversation_members (
    conversation_id, user_id, role, request_state
  ) values (
    v_conversation, v_me, 'owner'::public.member_role, 'accepted'
  );

  insert into public.conversation_members (
    conversation_id, user_id, role, request_state
  )
  select v_conversation, t.m, 'member'::public.member_role, 'accepted'
    from unnest(v_members) as t(m);

  select display_name into v_my_name
    from public.profiles where id = v_me;

  insert into public.messages (conversation_id, author_id, kind, body)
  values (
    v_conversation,
    v_me,
    'system'::public.message_kind,
    v_my_name || ' created the group'
  );

  return v_conversation;
end;
$$;


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
  -- Serialize every capacity-changing path on the conversation row.
  perform 1
    from public.conversations c
   where c.id = p_conversation
     and c.kind = 'group'::public.conversation_kind
   for update;
  if not found then raise exception 'not_group'; end if;

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
         select 1
           from public.conversation_members cm
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
  if v_active + array_length(v_candidates, 1) > 256 then
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
       select 1
         from public.conversation_members cm
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
  select p_conversation,
         v_me,
         'system'::public.message_kind,
         v_my_name || ' added ' || pr.display_name
    from public.profiles pr
   where pr.id = any (v_joined);

  return coalesce(array_length(v_joined, 1), 0);
end;
$$;


create or replace function public.join_group_invite(
  p_token text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_group public.conversations%rowtype;
  v_state text;
  v_active integer;
begin
  if me is null then raise exception 'auth_required'; end if;
  if nullif(trim(p_token), '') is null then raise exception 'bad_invite'; end if;

  -- Uses the same row lock as add_group_members, preventing concurrent joins
  -- from taking the group past its hard capacity.
  select * into v_group
    from public.conversations c
   where c.kind = 'group'::public.conversation_kind
     and c.invite_token_hash = encode(
       extensions.digest(trim(p_token), 'sha256'),
       'hex'
     )
   for update;
  if not found then raise exception 'invite_invalid'; end if;

  if exists (
    select 1
      from public.blocks b
      join public.conversation_members cm
        on cm.conversation_id = v_group.id
       and cm.left_at is null
     where (b.blocker_id = me and b.blocked_id = cm.user_id)
        or (b.blocker_id = cm.user_id and b.blocked_id = me)
  ) then
    raise exception 'blocked_member';
  end if;

  if not exists (
    select 1
      from public.conversation_members cm
     where cm.conversation_id = v_group.id
       and cm.user_id = me
       and cm.left_at is null
  ) then
    select count(*) into v_active
      from public.conversation_members cm
     where cm.conversation_id = v_group.id
       and cm.left_at is null;
    if v_active >= 256 then raise exception 'group_full'; end if;
  end if;

  v_state := case
    when v_group.join_approval_required then 'pending'
    else 'accepted'
  end;

  insert into public.conversation_members (
    conversation_id, user_id, role, request_state, joined_at, left_at
  ) values (
    v_group.id, me, 'member'::public.member_role, v_state, now(), null
  )
  on conflict (conversation_id, user_id) do update
    set request_state = case
          when public.conversation_members.left_at is null
            then public.conversation_members.request_state
          else excluded.request_state
        end,
        left_at = null,
        joined_at = case
          when public.conversation_members.left_at is not null then now()
          else public.conversation_members.joined_at
        end;

  select cm.request_state into v_state
    from public.conversation_members cm
   where cm.conversation_id = v_group.id
     and cm.user_id = me;

  return jsonb_build_object(
    'conversation_id', v_group.id,
    'state', v_state
  );
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
  v_description text;
  v_name text;
  v_title_changed boolean;
  v_description_changed boolean;
  v_avatar_changed boolean;
begin
  select * into v_conv
    from public.conversations c
   where c.id = p_conversation
     and c.kind = 'group'::public.conversation_kind
   for update;
  if not found then raise exception 'not_group'; end if;

  if not public.group_policy_allows(p_conversation, 'edit_info', v_me) then
    raise exception 'group_policy_denied';
  end if;

  if p_title is not null then
    v_title := trim(p_title);
    if v_title = '' then raise exception 'title_required'; end if;
    if char_length(v_title) > 60 then raise exception 'title_too_long'; end if;
  end if;

  if p_description is not null then
    v_description := nullif(trim(p_description), '');
    if char_length(coalesce(v_description, '')) > 500 then
      raise exception 'description_too_long';
    end if;
  end if;

  v_title_changed := p_title is not null
    and v_title is distinct from v_conv.title;
  v_description_changed := p_description is not null
    and v_description is distinct from v_conv.description;
  v_avatar_changed := p_avatar_path is not null
    and p_avatar_path is distinct from v_conv.avatar_path;

  update public.conversations
     set title = case when p_title is null then title else v_title end,
         description = case
           when p_description is null then description else v_description
         end,
         avatar_path = case
           when p_avatar_path is null then avatar_path else p_avatar_path
         end,
         updated_at = now()
   where id = p_conversation;

  if v_title_changed or v_description_changed or v_avatar_changed then
    select display_name into v_name
      from public.profiles where id = v_me;
  end if;

  if v_title_changed then
    insert into public.messages (conversation_id, author_id, kind, body)
    values (
      p_conversation,
      v_me,
      'system'::public.message_kind,
      v_name || ' renamed the group to "' || v_title || '"'
    );
  end if;

  if v_description_changed then
    insert into public.messages (conversation_id, author_id, kind, body)
    values (
      p_conversation,
      v_me,
      'system'::public.message_kind,
      v_name || case
        when v_description is null then ' cleared the group description'
        else ' changed the group description'
      end
    );
  end if;

  if v_avatar_changed then
    insert into public.messages (conversation_id, author_id, kind, body)
    values (
      p_conversation,
      v_me,
      'system'::public.message_kind,
      v_name || ' changed the group photo'
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
declare
  v_me uuid := public.require_auth();
  v_conv public.conversations%rowtype;
  v_name text;
begin
  select * into v_conv
    from public.conversations c
   where c.id = p_conversation
     and c.kind = 'group'::public.conversation_kind
   for update;
  if not found then raise exception 'not_group'; end if;

  if not public.group_policy_allows(p_conversation, 'edit_info', v_me) then
    raise exception 'group_policy_denied';
  end if;

  if v_conv.avatar_path is null then return; end if;

  update public.conversations
     set avatar_path = null,
         updated_at = now()
   where id = p_conversation;

  select display_name into v_name
    from public.profiles where id = v_me;
  insert into public.messages (conversation_id, author_id, kind, body)
  values (
    p_conversation,
    v_me,
    'system'::public.message_kind,
    v_name || ' removed the group photo'
  );
end;
$$;


comment on function public.create_group(text, uuid[], text, text) is
  'Create a 2..256 member group. Title and description are validated after trimming.';
comment on function public.add_group_members(uuid, uuid[]) is
  'Add or rejoin members without exceeding 256 active rows.';
comment on function public.join_group_invite(text) is
  'Join a group invite without exceeding 256 active rows.';
comment on function public.update_group_info(uuid, text, text, text) is
  'Update group identity and emit one system message for each actual change.';
comment on function public.clear_group_avatar(uuid) is
  'Clear a group avatar and emit one system message when it actually changes.';

revoke all on function public.create_group(text, uuid[], text, text)
  from public, anon, authenticated;
grant execute on function public.create_group(text, uuid[], text, text)
  to authenticated, service_role;

revoke all on function public.add_group_members(uuid, uuid[])
  from public, anon, authenticated;
grant execute on function public.add_group_members(uuid, uuid[])
  to authenticated, service_role;

revoke all on function public.join_group_invite(text)
  from public, anon, authenticated;
grant execute on function public.join_group_invite(text)
  to authenticated, service_role;

revoke all on function public.update_group_info(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.update_group_info(uuid, text, text, text)
  to authenticated, service_role;

revoke all on function public.clear_group_avatar(uuid)
  from public, anon, authenticated;
grant execute on function public.clear_group_avatar(uuid)
  to authenticated, service_role;

commit;
