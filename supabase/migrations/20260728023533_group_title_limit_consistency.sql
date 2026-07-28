-- Keep group creation and editing on the same 80-character title limit.

begin;

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
    if char_length(v_title) > 80 then raise exception 'title_too_long'; end if;
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

revoke all on function public.update_group_info(uuid, text, text, text) from public;
revoke all on function public.update_group_info(uuid, text, text, text) from anon;
grant execute on function public.update_group_info(uuid, text, text, text) to authenticated;
grant execute on function public.update_group_info(uuid, text, text, text) to service_role;

commit;
