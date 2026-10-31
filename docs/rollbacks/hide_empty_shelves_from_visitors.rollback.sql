-- Rollback for migration `hide_empty_shelves_from_visitors` (2026-10-31).
--
-- NOT a migration: run by hand (Supabase SQL editor or MCP apply_migration)
-- only if empty shelves must become visible to visitors again. It restores
-- the exact live definitions captured before the change.

alter policy collections_read on public.collections
  using (
    visible_to_me(user_id, visibility)
    and (((deleted_at is null) and (hidden_at is null))
         or (user_id = (select auth.uid()))
         or is_staff())
  );

create or replace function public.can_view_entity(p_type entity_type, p_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare o uuid; v visibility; hid timestamptz; del timestamptz;
begin
  if p_id is null then return false; end if;
  case p_type
    when 'collection' then
      select user_id, visibility, hidden_at, deleted_at into o, v, hid, del
        from collections where id = p_id;
    when 'subcollection' then
      select s.user_id, coalesce(s.visibility, c.visibility), s.hidden_at, s.deleted_at into o, v, hid, del
        from subcollections s join collections c on c.id = s.collection_id where s.id = p_id;
    when 'item' then
      select i.user_id, coalesce(i.visibility, s.visibility, c.visibility), i.hidden_at, i.deleted_at into o, v, hid, del
        from items i
        join collections c on c.id = i.collection_id
        left join subcollections s on s.id = i.subcollection_id
       where i.id = p_id;
    when 'post' then
      select author_id, visibility, hidden_at, deleted_at into o, v, hid, del
        from posts where id = p_id;
    when 'comment' then
      select author_id, 'public'::visibility, hidden_at, deleted_at into o, v, hid, del
        from comments where id = p_id;
  end case;

  if o is null then return false; end if;
  if (hid is not null or del is not null) and o is distinct from auth.uid() then
    return public.is_staff();
  end if;
  return public.visible_to_me(o, v);
end $function$;

-- get_closeup: restore the group list without the content filter. Re-run the
-- migration's get_closeup body with this line removed from the
-- 'subcollections' subquery:
--   and (owner = me or public.is_staff() or public.subcollection_has_content(id))
--
-- get_matches: likewise remove
--   and public.collection_has_content(id)
-- from the top_collections subquery.
--
-- Then, once nothing references them:
--   drop function public.collection_has_content(uuid);
--   drop function public.subcollection_has_content(uuid);
