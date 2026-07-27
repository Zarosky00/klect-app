-- Messaging integrity, group controls and synced appearance preferences.

begin;

-- ---------------------------------------------------------------------------
-- Conversation policy and request state
-- ---------------------------------------------------------------------------

alter table public.conversations
  add column if not exists group_policy jsonb not null default jsonb_build_object(
    'edit_info', 'admins',
    'add_members', 'admins',
    'send_messages', 'everyone'
  ),
  add column if not exists join_approval_required boolean not null default false,
  add column if not exists invite_token_hash text,
  add column if not exists invite_token_prefix text,
  add column if not exists invite_rotated_at timestamptz;

alter table public.conversations
  drop constraint if exists conversations_group_policy_shape;
alter table public.conversations
  add constraint conversations_group_policy_shape check (
    kind <> 'group'::public.conversation_kind
    or (
      group_policy ->> 'edit_info' in ('owner', 'admins', 'everyone')
      and group_policy ->> 'add_members' in ('owner', 'admins', 'everyone')
      and group_policy ->> 'send_messages' in ('owner', 'admins', 'everyone')
    )
  );

alter table public.conversation_members
  add column if not exists request_state text not null default 'accepted',
  add column if not exists notification_level text not null default 'all';

alter table public.conversation_members
  drop constraint if exists conversation_members_request_state_check;
alter table public.conversation_members
  add constraint conversation_members_request_state_check
  check (request_state in ('pending', 'accepted', 'declined'));

alter table public.conversation_members
  drop constraint if exists conversation_members_notification_level_check;
alter table public.conversation_members
  add constraint conversation_members_notification_level_check
  check (notification_level in ('all', 'mentions', 'none'));


create or replace function public.group_policy_allows(
  p_conversation uuid,
  p_action text,
  p_user uuid default auth.uid()
) returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select case coalesce(c.group_policy ->> p_action, 'admins')
      when 'everyone' then true
      when 'admins' then cm.role in (
        'admin'::public.member_role,
        'owner'::public.member_role
      )
      when 'owner' then cm.role = 'owner'::public.member_role
      else false
    end
      from public.conversations c
      join public.conversation_members cm
        on cm.conversation_id = c.id
       and cm.user_id = p_user
       and cm.left_at is null
       and cm.request_state = 'accepted'
     where c.id = p_conversation
       and c.kind = 'group'::public.conversation_kind
  ), false);
$$;


create or replace function public.set_group_policy(
  p_conversation uuid,
  p_policy jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_role public.member_role;
  v_policy jsonb;
begin
  if me is null then raise exception 'auth_required'; end if;

  select cm.role into v_role
    from public.conversation_members cm
    join public.conversations c on c.id = cm.conversation_id
   where cm.conversation_id = p_conversation
     and cm.user_id = me
     and cm.left_at is null
     and cm.request_state = 'accepted'
     and c.kind = 'group'::public.conversation_kind;

  if v_role <> 'owner'::public.member_role then
    raise exception 'owner_required';
  end if;

  v_policy := jsonb_build_object(
    'edit_info', coalesce(p_policy ->> 'edit_info', 'admins'),
    'add_members', coalesce(p_policy ->> 'add_members', 'admins'),
    'send_messages', coalesce(p_policy ->> 'send_messages', 'everyone')
  );

  if v_policy ->> 'edit_info' not in ('owner', 'admins', 'everyone')
     or v_policy ->> 'add_members' not in ('owner', 'admins', 'everyone')
     or v_policy ->> 'send_messages' not in ('owner', 'admins', 'everyone') then
    raise exception 'bad_group_policy';
  end if;

  update public.conversations
     set group_policy = v_policy,
         updated_at = now()
   where id = p_conversation;

  return v_policy;
end;
$$;


-- ---------------------------------------------------------------------------
-- Idempotent, reply-safe message sending
-- ---------------------------------------------------------------------------

create or replace function public.send_message(
  p_conversation uuid,
  p_id uuid,
  p_body text default null,
  p_kind public.message_kind default 'text',
  p_attachments jsonb default '[]'::jsonb,
  p_shared_entity_type public.entity_type default null,
  p_shared_entity_id uuid default null,
  p_reply_to uuid default null,
  p_call_id uuid default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_conversation_kind public.conversation_kind;
  v_role public.member_role;
  v_request_state text;
  v_existing public.messages%rowtype;
begin
  if me is null then raise exception 'auth_required'; end if;
  if p_conversation is null or p_id is null then raise exception 'bad_message'; end if;

  select c.kind, cm.role, cm.request_state
    into v_conversation_kind, v_role, v_request_state
    from public.conversations c
    join public.conversation_members cm
      on cm.conversation_id = c.id
     and cm.user_id = me
     and cm.left_at is null
   where c.id = p_conversation;

  if not found then raise exception 'not_a_member'; end if;
  if v_request_state <> 'accepted' then raise exception 'request_not_accepted'; end if;

  if v_conversation_kind = 'group'::public.conversation_kind
     and not public.group_policy_allows(
       p_conversation, 'send_messages', me
     ) then
    raise exception 'posting_restricted';
  end if;

  if p_reply_to is not null and not exists (
    select 1
      from public.messages parent
     where parent.id = p_reply_to
       and parent.conversation_id = p_conversation
  ) then
    raise exception 'reply_outside_conversation';
  end if;

  if jsonb_typeof(coalesce(p_attachments, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_attachments, '[]'::jsonb)) > 4 then
    raise exception 'bad_attachments';
  end if;

  select * into v_existing from public.messages where id = p_id;
  if found then
    if v_existing.conversation_id = p_conversation
       and v_existing.author_id = me then
      return v_existing.id;
    end if;
    raise exception 'message_id_conflict';
  end if;

  insert into public.messages (
    id,
    conversation_id,
    author_id,
    body,
    kind,
    attachments,
    shared_entity_type,
    shared_entity_id,
    reply_to_id,
    call_id
  ) values (
    p_id,
    p_conversation,
    me,
    nullif(trim(p_body), ''),
    p_kind,
    coalesce(p_attachments, '[]'::jsonb),
    p_shared_entity_type,
    p_shared_entity_id,
    p_reply_to,
    p_call_id
  );

  return p_id;
end;
$$;


-- ---------------------------------------------------------------------------
-- Group invitation lifecycle
-- ---------------------------------------------------------------------------

create or replace function public.rotate_group_invite(
  p_conversation uuid
) returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_token text;
begin
  if me is null then raise exception 'auth_required'; end if;
  if not public.group_policy_allows(p_conversation, 'add_members', me) then
    raise exception 'not_allowed';
  end if;

  v_token := encode(extensions.gen_random_bytes(24), 'hex');
  update public.conversations
     set invite_token_hash = encode(
           extensions.digest(v_token, 'sha256'),
           'hex'
         ),
         invite_token_prefix = left(v_token, 8),
         invite_rotated_at = now(),
         updated_at = now()
   where id = p_conversation
     and kind = 'group'::public.conversation_kind;

  if not found then raise exception 'group_not_found'; end if;
  return v_token;
end;
$$;


create or replace function public.revoke_group_invite(
  p_conversation uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if not public.group_policy_allows(
    p_conversation, 'add_members', auth.uid()
  ) then
    raise exception 'not_allowed';
  end if;

  update public.conversations
     set invite_token_hash = null,
         invite_token_prefix = null,
         invite_rotated_at = now(),
         updated_at = now()
   where id = p_conversation;
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
begin
  if me is null then raise exception 'auth_required'; end if;
  if nullif(trim(p_token), '') is null then raise exception 'bad_invite'; end if;

  select * into v_group
    from public.conversations c
   where c.kind = 'group'::public.conversation_kind
     and c.invite_token_hash = encode(
       extensions.digest(trim(p_token), 'sha256'),
       'hex'
     );

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
    set request_state = excluded.request_state,
        left_at = null,
        joined_at = case
          when public.conversation_members.left_at is not null then now()
          else public.conversation_members.joined_at
        end;

  return jsonb_build_object(
    'conversation_id', v_group.id,
    'state', v_state
  );
end;
$$;


create or replace function public.review_group_join_request(
  p_conversation uuid,
  p_member uuid,
  p_accept boolean
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  if not public.group_policy_allows(
    p_conversation, 'add_members', auth.uid()
  ) then
    raise exception 'not_allowed';
  end if;

  update public.conversation_members
     set request_state = case when p_accept then 'accepted' else 'declined' end,
         left_at = case when p_accept then null else now() end
   where conversation_id = p_conversation
     and user_id = p_member
     and request_state = 'pending';

  if not found then raise exception 'request_not_found'; end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- Versioned account-synced appearance preferences
-- ---------------------------------------------------------------------------

create table if not exists public.user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  version integer not null default 1 check (version > 0),
  appearance jsonb not null default jsonb_build_object(
    'theme', 'system',
    'accent', 'klect',
    'font_pack', 'editorial',
    'text_size', 'system',
    'density', 'comfortable',
    'motion', 'system',
    'contrast', 'standard',
    'pulse_layout', 'balanced',
    'data_saver', false,
    'media_autoplay', 'wifi',
    'chat_wallpaper', 'noir'
  ),
  updated_at timestamptz not null default now()
);

alter table public.user_preferences enable row level security;

drop policy if exists user_preferences_select_own
  on public.user_preferences;
create policy user_preferences_select_own
  on public.user_preferences
  for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_preferences_insert_own
  on public.user_preferences;
create policy user_preferences_insert_own
  on public.user_preferences
  for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists user_preferences_update_own
  on public.user_preferences;
create policy user_preferences_update_own
  on public.user_preferences
  for update
  to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

revoke all on table public.user_preferences from anon;
grant select, insert, update on table public.user_preferences to authenticated;
grant all on table public.user_preferences to service_role;


create or replace function public.save_appearance_preferences(
  p_version integer,
  p_appearance jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_allowed_themes text[] := array['system', 'light', 'dark', 'oled'];
  v_allowed_fonts text[] := array['editorial', 'modern', 'readable'];
begin
  if me is null then raise exception 'auth_required'; end if;
  if p_version is null or p_version < 1 then raise exception 'bad_version'; end if;
  if jsonb_typeof(p_appearance) <> 'object' then
    raise exception 'bad_preferences';
  end if;
  if coalesce(p_appearance ->> 'theme', 'system') <> all(v_allowed_themes)
     or coalesce(p_appearance ->> 'font_pack', 'editorial') <> all(v_allowed_fonts) then
    raise exception 'bad_preferences';
  end if;

  insert into public.user_preferences (user_id, version, appearance, updated_at)
  values (me, p_version, p_appearance, now())
  on conflict (user_id) do update
    set version = excluded.version,
        appearance = excluded.appearance,
        updated_at = now();

  return jsonb_build_object(
    'version', p_version,
    'appearance', p_appearance,
    'updated_at', now()
  );
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
  if not public.is_conversation_admin(p_conversation) then
    raise exception 'not_admin';
  end if;
  if not public.group_policy_allows(p_conversation, 'edit_info', auth.uid()) then
    raise exception 'group_policy_denied';
  end if;

  update public.conversations
  set avatar_path = null,
      updated_at = now()
  where id = p_conversation
    and kind = 'group';

  if not found then raise exception 'not_group'; end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- ACL
-- ---------------------------------------------------------------------------

revoke execute on function public.group_policy_allows(uuid, text, uuid)
  from public, anon, authenticated;

revoke execute on function public.set_group_policy(uuid, jsonb)
  from public, anon;
grant execute on function public.set_group_policy(uuid, jsonb)
  to authenticated, service_role;

revoke execute on function public.send_message(
  uuid, uuid, text, public.message_kind, jsonb,
  public.entity_type, uuid, uuid, uuid
) from public, anon;
grant execute on function public.send_message(
  uuid, uuid, text, public.message_kind, jsonb,
  public.entity_type, uuid, uuid, uuid
) to authenticated, service_role;

revoke execute on function public.rotate_group_invite(uuid)
  from public, anon;
grant execute on function public.rotate_group_invite(uuid)
  to authenticated, service_role;

revoke execute on function public.revoke_group_invite(uuid)
  from public, anon;
grant execute on function public.revoke_group_invite(uuid)
  to authenticated, service_role;

revoke execute on function public.join_group_invite(text)
  from public, anon;
grant execute on function public.join_group_invite(text)
  to authenticated, service_role;

revoke execute on function public.review_group_join_request(uuid, uuid, boolean)
  from public, anon;
grant execute on function public.review_group_join_request(uuid, uuid, boolean)
  to authenticated, service_role;

revoke execute on function public.save_appearance_preferences(integer, jsonb)
  from public, anon;
grant execute on function public.save_appearance_preferences(integer, jsonb)
  to authenticated, service_role;

revoke execute on function public.clear_group_avatar(uuid)
  from public, anon;
grant execute on function public.clear_group_avatar(uuid)
  to authenticated, service_role;

commit;
