-- ============================================================================
-- 0017_group_chats.sql — group-chat management RPC surface
--
-- Implements docs/CHAT_PLAN.md §5. The schema is already group-ready
-- (conversations.kind='group' + title/description/avatar_path,
-- conversation_members.role owner|admin|member + left_at,
-- message_kind='system'); this migration adds ONLY the five RPCs:
--
--   create_group(p_title, p_members, p_description, p_avatar_path)      -> uuid
--   add_group_members(p_conversation, p_members)                        -> integer
--   remove_group_member(p_conversation, p_member)                       -> void
--   update_group_info(p_conversation, p_title, p_description, p_avatar_path) -> void
--   set_group_member_role(p_conversation, p_member, p_role)             -> void
--
-- Hardening matches 0012: every function is SECURITY DEFINER with
-- search_path pinned to '', EXECUTE revoked from public/anon and granted to
-- `authenticated` only. System messages are plain inserts into public.messages
-- (kind='system'), so the existing message-insert triggers do the conversation
-- preview, unread fan-out and notifications — nothing here duplicates them.
--
-- Stable snake_case error texts (mapped to human copy by the clients):
--   title_required, title_too_long, group_needs_members, group_full,
--   not_group, not_admin, not_member, not_owner,
--   cannot_remove_owner, cannot_demote_owner
--
-- STATUS: ✅ APPLIED to `new_klect` (dikhuygcwxnrsckqglzg) on 2026-07-26 via
-- Supabase MCP `apply_migration` (version 0017_group_chats in the migrations
-- table). Smoke-tested under JWT impersonation as demo user aria: create →
-- add → promote → remove → rename → owner-leave-with-transfer all passed;
-- test data rolled back.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- create_group — caller becomes owner, everyone else member.
-- Title trimmed 1..80 chars. Members deduped, self-excluded, capped at 64,
-- anyone in a blocks pair with the caller silently dropped, unknown ids
-- silently dropped. Errors if nobody remains. Emits one system message.
-- ----------------------------------------------------------------------------
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
  v_members      uuid[];
  v_conversation uuid;
  v_my_name      text;
begin
  if v_title = '' then
    raise exception 'title_required';
  end if;
  if char_length(v_title) > 80 then
    raise exception 'title_too_long';
  end if;

  -- dedupe · drop self · drop unknown ids · drop blocked pairs · cap at 64
  select coalesce(array_agg(m), '{}')
    into v_members
  from (
    select distinct pr.id as m
    from unnest(coalesce(p_members, '{}'::uuid[])) as u(id)
    join public.profiles pr on pr.id = u.id
    where pr.id <> v_me
      and not public.blocked_with(pr.id)
    limit 64
  ) s;

  if coalesce(array_length(v_members, 1), 0) = 0 then
    raise exception 'group_needs_members';
  end if;

  insert into public.conversations (kind, title, description, avatar_path, created_by)
  values ('group', v_title, nullif(trim(p_description), ''), p_avatar_path, v_me)
  returning id into v_conversation;

  insert into public.conversation_members (conversation_id, user_id, role)
  values (v_conversation, v_me, 'owner');

  insert into public.conversation_members (conversation_id, user_id, role)
  select v_conversation, t.m, 'member'
  from unnest(v_members) as t(m);

  select display_name into v_my_name from public.profiles where id = v_me;

  insert into public.messages (conversation_id, author_id, kind, body)
  values (v_conversation, v_me, 'system', v_my_name || ' created the group');

  return v_conversation;
end;
$$;

comment on function public.create_group(text, uuid[], text, text) is
  'Create a group conversation. Caller becomes owner, p_members become members. Returns the conversation id.';


-- ----------------------------------------------------------------------------
-- add_group_members — admin/owner only. Skips blocked pairs, unknown ids and
-- current members. Rows with left_at set are RE-JOINED (left_at cleared,
-- unread_count/last_read_at reset, role back to member). One system message
-- per join. Returns the number of members actually added/re-joined.
-- ----------------------------------------------------------------------------
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
    where c.id = p_conversation and c.kind = 'group'
  ) then
    raise exception 'not_group';
  end if;

  if not public.is_conversation_admin(p_conversation) then
    raise exception 'not_admin';
  end if;

  -- dedupe · drop self · drop unknown ids · drop blocked pairs · drop actives
  select coalesce(array_agg(m), '{}')
    into v_candidates
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

  if coalesce(array_length(v_candidates, 1), 0) = 0 then
    return 0;  -- nothing to do; treat as success (idempotent-friendly)
  end if;

  -- keep the creation-time ceiling: owner + 64 members = 65 active rows
  select count(*) into v_active
  from public.conversation_members cm
  where cm.conversation_id = p_conversation and cm.left_at is null;

  if v_active + array_length(v_candidates, 1) > 65 then
    raise exception 'group_full';
  end if;

  -- re-join previously-left rows
  with rejoin as (
    update public.conversation_members cm
       set left_at      = null,
           role         = 'member',
           unread_count = 0,
           last_read_at = now(),
           joined_at    = now()
     where cm.conversation_id = p_conversation
       and cm.user_id = any (v_candidates)
       and cm.left_at is not null
    returning cm.user_id
  )
  select coalesce(array_agg(user_id), '{}') into v_rejoined from rejoin;

  -- brand-new rows
  with ins as (
    insert into public.conversation_members (conversation_id, user_id, role)
    select p_conversation, t.m, 'member'
    from unnest(v_candidates) as t(m)
    where not exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = p_conversation and cm.user_id = t.m
    )
    returning user_id
  )
  select coalesce(array_agg(user_id), '{}') into v_inserted from ins;

  v_joined := v_rejoined || v_inserted;

  select display_name into v_my_name from public.profiles where id = v_me;

  -- one system message per join ("Kenji added Noor")
  insert into public.messages (conversation_id, author_id, kind, body)
  select p_conversation, v_me, 'system', v_my_name || ' added ' || pr.display_name
  from public.profiles pr
  where pr.id = any (v_joined);

  return coalesce(array_length(v_joined, 1), 0);
end;
$$;

comment on function public.add_group_members(uuid, uuid[]) is
  'Add (or re-join) members to a group. Admin/owner only. Returns how many actually joined.';


-- ----------------------------------------------------------------------------
-- remove_group_member — self-removal (leave) always allowed; otherwise the
-- caller must be admin/owner, and admins cannot remove the owner. Sets
-- left_at. If the owner leaves, ownership auto-transfers to the
-- earliest-joined admin, else the earliest-joined member; if the group
-- empties it is simply left dormant. Emits "X left" / "X was removed".
-- ----------------------------------------------------------------------------
create or replace function public.remove_group_member(
  p_conversation uuid,
  p_member uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me     uuid := public.require_auth();
  v_target public.conversation_members%rowtype;
  v_heir   uuid;
  v_name   text;
begin
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation and c.kind = 'group'
  ) then
    raise exception 'not_group';
  end if;

  if not public.is_conversation_member(p_conversation) then
    raise exception 'not_member';
  end if;

  select * into v_target
  from public.conversation_members cm
  where cm.conversation_id = p_conversation
    and cm.user_id = p_member
    and cm.left_at is null;
  if not found then
    raise exception 'not_member';
  end if;

  if p_member <> v_me then
    if not public.is_conversation_admin(p_conversation) then
      raise exception 'not_admin';
    end if;
    if v_target.role = 'owner' then
      raise exception 'cannot_remove_owner';
    end if;
  end if;

  update public.conversation_members
     set left_at = now()
   where conversation_id = p_conversation
     and user_id = p_member;

  -- owner left: transfer to earliest-joined admin, else earliest member
  if v_target.role = 'owner' then
    select cm.user_id into v_heir
    from public.conversation_members cm
    where cm.conversation_id = p_conversation
      and cm.left_at is null
    order by (cm.role = 'admin') desc, cm.joined_at asc, cm.user_id asc
    limit 1;

    if v_heir is not null then
      update public.conversation_members
         set role = 'owner'
       where conversation_id = p_conversation
         and user_id = v_heir;
    end if;
    -- v_heir null → nobody remains; the group is left dormant on purpose
  end if;

  select display_name into v_name from public.profiles where id = p_member;

  insert into public.messages (conversation_id, author_id, kind, body)
  values (
    p_conversation,
    v_me,
    'system',
    case when p_member = v_me
         then v_name || ' left'
         else v_name || ' was removed'
    end
  );
end;
$$;

comment on function public.remove_group_member(uuid, uuid) is
  'Leave a group (p_member = self) or remove a member (admin/owner only; owner cannot be removed).';


-- ----------------------------------------------------------------------------
-- update_group_info — admin/owner only. Null args mean "keep". A provided
-- title is trimmed and must be 1..80 chars; a provided description of ''
-- clears it. A rename emits a system message.
-- ----------------------------------------------------------------------------
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
  v_me    uuid := public.require_auth();
  v_conv  public.conversations%rowtype;
  v_title text;
  v_name  text;
begin
  select * into v_conv from public.conversations c where c.id = p_conversation;
  if not found or v_conv.kind <> 'group' then
    raise exception 'not_group';
  end if;

  if not public.is_conversation_admin(p_conversation) then
    raise exception 'not_admin';
  end if;

  if p_title is not null then
    v_title := trim(p_title);
    if v_title = '' then
      raise exception 'title_required';
    end if;
    if char_length(v_title) > 80 then
      raise exception 'title_too_long';
    end if;
  end if;

  update public.conversations
     set title       = coalesce(v_title, title),
         description = case when p_description is null then description
                            else nullif(trim(p_description), '') end,
         avatar_path = coalesce(p_avatar_path, avatar_path),
         updated_at  = now()
   where id = p_conversation;

  if v_title is not null and v_title is distinct from v_conv.title then
    select display_name into v_name from public.profiles where id = v_me;
    insert into public.messages (conversation_id, author_id, kind, body)
    values (p_conversation, v_me, 'system',
            v_name || ' renamed the group to "' || v_title || '"');
  end if;
end;
$$;

comment on function public.update_group_info(uuid, text, text, text) is
  'Update a group''s title/description/avatar. Admin/owner only. Null args keep current values.';


-- ----------------------------------------------------------------------------
-- set_group_member_role — owner only. Granting 'owner' transfers ownership
-- (the previous owner becomes admin). The owner cannot demote themselves —
-- transfer ownership or leave instead.
-- ----------------------------------------------------------------------------
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
  if v_my_role is null or v_my_role <> 'owner' then
    raise exception 'not_owner';
  end if;

  select cm.role into v_target_role
  from public.conversation_members cm
  where cm.conversation_id = p_conversation
    and cm.user_id = p_member
    and cm.left_at is null;
  if v_target_role is null then
    raise exception 'not_member';
  end if;

  if p_member = v_me then
    if p_role <> 'owner' then
      raise exception 'cannot_demote_owner';
    end if;
    return;  -- already owner; nothing to do
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
  'Owner only: promote/demote a member. Granting owner transfers ownership; previous owner becomes admin.';


-- ----------------------------------------------------------------------------
-- Grants — same posture as 0012: nothing for public/anon, RPC surface for
-- `authenticated` only.
-- ----------------------------------------------------------------------------
revoke execute on function public.create_group(text, uuid[], text, text)                from public, anon;
revoke execute on function public.add_group_members(uuid, uuid[])                       from public, anon;
revoke execute on function public.remove_group_member(uuid, uuid)                       from public, anon;
revoke execute on function public.update_group_info(uuid, text, text, text)             from public, anon;
revoke execute on function public.set_group_member_role(uuid, uuid, public.member_role) from public, anon;

grant execute on function public.create_group(text, uuid[], text, text)                to authenticated;
grant execute on function public.add_group_members(uuid, uuid[])                       to authenticated;
grant execute on function public.remove_group_member(uuid, uuid)                       to authenticated;
grant execute on function public.update_group_info(uuid, text, text, text)             to authenticated;
grant execute on function public.set_group_member_role(uuid, uuid, public.member_role) to authenticated;
