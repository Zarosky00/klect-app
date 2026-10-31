-- Empty shelves and groups stay private to their owner until something is on
-- them.
--
-- Onboarding turns every picked interest ("Games", "Coffee", ...) into a
-- public, coverless collection with nothing on it. Visitors could open those
-- shells from a profile, from search and through closeups, and like, save or
-- comment on a shelf that held nothing. Surf already skipped them
-- (`surf_feed` requires `item_count > 0`); every other read path did not.
--
-- The rule, enforced once in the read layer so the mobile app, the web app
-- and every RPC agree:
--
--   A collection or subcollection is visible to anybody other than its owner
--   (and staff) only while it holds at least one live item that viewer may
--   see.
--
-- "Live" and "may see" mirror `can_view_entity('item', ...)`: the item is not
-- hidden or deleted, and `visible_to_me(owner, coalesce(item, group, shelf
-- visibility))` holds. So a shelf is never visible while every item on it is
-- invisible to you, and you can never see an item whose shelf is hidden.
--
-- Owners keep seeing their own empty shelves (the `user_id = auth.uid()` fast
-- path), so onboarding's INSERT ... RETURNING and the owner's library are
-- unaffected. Staff keep seeing everything, for moderation.
--
-- Paths covered:
--   * `collections_read` RLS (profile grids, direct reads, web pages, sitemap)
--   * `can_view_entity` collection/subcollection branches, which gate
--     `subcollections_read`, `get_closeup`, `search_all`, Pulse attachments
--     (`pulse_target_payload_depth`), `social_target_active` and the
--     engagement/activity RPCs, plus like/save/comment writes on the target
--   * `get_closeup`'s group list for a shelf (it is SECURITY DEFINER and
--     listed every non-deleted group)
--   * `get_matches` shelf previews
--
-- Reversible: docs/rollbacks/hide_empty_shelves_from_visitors.rollback.sql
-- restores the previous `collections_read` and `can_view_entity` bodies and
-- lists the one-line removals for `get_closeup` and `get_matches`.

-- ---------------------------------------------------------------- helpers --

create or replace function public.collection_has_content(p_collection uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.collections c
      join public.items i on i.collection_id = c.id
      left join public.subcollections s on s.id = i.subcollection_id
     where c.id = p_collection
       and c.item_count > 0
       and i.deleted_at is null
       and i.hidden_at is null
       and public.visible_to_me(
             i.user_id,
             coalesce(i.visibility, s.visibility, c.visibility)
           )
  );
$$;

comment on function public.collection_has_content(uuid) is
  'True when the shelf holds at least one live item the caller may see. '
  'Non-owners only see shelves for which this holds.';

create or replace function public.subcollection_has_content(p_subcollection uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.subcollections s
      join public.collections c on c.id = s.collection_id
      join public.items i on i.subcollection_id = s.id
     where s.id = p_subcollection
       and s.item_count > 0
       and i.deleted_at is null
       and i.hidden_at is null
       and public.visible_to_me(
             i.user_id,
             coalesce(i.visibility, s.visibility, c.visibility)
           )
  );
$$;

comment on function public.subcollection_has_content(uuid) is
  'True when the group holds at least one live item the caller may see. '
  'Non-owners only see groups for which this holds.';

-- `collections_read` calls `collection_has_content` as the querying role, so
-- both API roles must keep EXECUTE. The helpers only answer true/false for
-- the caller's own view, and false for unknown ids.
revoke execute on function public.collection_has_content(uuid) from public;
revoke execute on function public.subcollection_has_content(uuid) from public;
grant execute on function public.collection_has_content(uuid)
  to anon, authenticated, service_role;
grant execute on function public.subcollection_has_content(uuid)
  to anon, authenticated, service_role;

-- ------------------------------------------------------------ shelf reads --

alter policy collections_read on public.collections
  using (
    public.visible_to_me(user_id, visibility)
    and (
      (deleted_at is null and hidden_at is null)
      or user_id = (select auth.uid())
      or public.is_staff()
    )
    and (
      user_id = (select auth.uid())
      or public.is_staff()
      or public.collection_has_content(id)
    )
  );

-- --------------------------------------------------------- can_view_entity --

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
  if not public.visible_to_me(o, v) then return false; end if;

  -- An empty shelf or group belongs to its owner until something is on it.
  if p_type in ('collection', 'subcollection')
     and o is distinct from auth.uid()
     and not public.is_staff() then
    if p_type = 'collection' then
      return public.collection_has_content(p_id);
    end if;
    return public.subcollection_has_content(p_id);
  end if;

  return true;
end $function$;

-- ------------------------------------------------------------- get_closeup --
-- Unchanged except the shelf's group list, which now hides empty groups from
-- everybody but the owner and staff, matching `subcollections_read`.

create or replace function public.get_closeup(p_type entity_type, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare me uuid := auth.uid(); result jsonb; owner uuid;
begin
  if not public.can_view_entity(p_type, p_id) then
    raise exception 'Not found' using errcode = '42501';
  end if;
  owner := public.entity_owner(p_type, p_id);

  result := jsonb_build_object(
    'entity_type', p_type,
    'entity_id',   p_id,
    'owner', (select row_to_json(o) from (
                select id, username::text, display_name, avatar_path, banner_path, bio,
                       is_verified, follower_count, collection_count, item_count
                  from profiles where id = owner) o),
    'viewer', jsonb_build_object(
       'liked',    exists (select 1 from likes   where entity_type=p_type and entity_id=p_id and user_id=me),
       'saved',    exists (select 1 from saves   where entity_type=p_type and entity_id=p_id and user_id=me),
       'reposted', exists (select 1 from reposts where entity_type=p_type and entity_id=p_id and user_id=me),
       'follows',  exists (select 1 from follows where follower_id=me and following_id=owner),
       'is_owner', owner = me),
    'counts', jsonb_build_object(
       'like',    public.entity_counter(p_type, p_id, 'like_count'),
       'save',    public.entity_counter(p_type, p_id, 'save_count'),
       'repost',  public.entity_counter(p_type, p_id, 'repost_count'),
       'comment', public.entity_counter(p_type, p_id, 'comment_count'),
       'view',    public.entity_counter(p_type, p_id, 'view_count')),
    'tags', coalesce((select jsonb_agg(t.slug::text) from entity_tags et
                        join tags t on t.id = et.tag_id
                       where et.entity_type = p_type and et.entity_id = p_id), '[]'::jsonb)
  );

  if p_type = 'item' then
    result := result || jsonb_build_object(
      'item', (select row_to_json(i) from (
                 select id, title, description, brand, model, year, condition, rarity,
                        acquisition_date, acquisition_place, purchase_price, currency,
                        is_favorite, attributes, created_at, collection_id, subcollection_id
                   from items where id = p_id) i),
      'media', coalesce((select jsonb_agg(row_to_json(m) order by m.position)
                           from (select id, storage_path, alt_text, width, height, blurhash,
                                        dominant_color, position
                                   from item_media where item_id = p_id) m), '[]'::jsonb),
      'breadcrumb', (select jsonb_build_object(
                       'collection', jsonb_build_object('id', c.id, 'name', c.name, 'slug', c.slug),
                       'subcollection', case when s.id is null then null
                                        else jsonb_build_object('id', s.id, 'name', s.name, 'slug', s.slug) end)
                       from items i join collections c on c.id = i.collection_id
                       left join subcollections s on s.id = i.subcollection_id
                      where i.id = p_id),
      'siblings', coalesce((select jsonb_agg(row_to_json(sib))
                    from (select i2.id, i2.title, i2.cover_path, i2.cover_blurhash,
                                 i2.cover_width, i2.cover_height, i2.like_count
                            from items i2, items self
                           where self.id = p_id and i2.id <> p_id
                             and i2.deleted_at is null and i2.hidden_at is null
                             and i2.cover_path is not null
                             and (case when self.subcollection_id is not null
                                       then i2.subcollection_id = self.subcollection_id
                                       else i2.collection_id = self.collection_id end)
                           order by i2.position, i2.created_at desc limit 24) sib), '[]'::jsonb));

  elsif p_type = 'subcollection' then
    result := result || jsonb_build_object(
      'subcollection', (select row_to_json(s) from (
                          select id, name, slug, description, cover_path, cover_blurhash,
                                 item_count, created_at, collection_id
                            from subcollections where id = p_id) s),
      'breadcrumb', (select jsonb_build_object('collection',
                       jsonb_build_object('id', c.id, 'name', c.name, 'slug', c.slug))
                       from subcollections s join collections c on c.id = s.collection_id where s.id = p_id),
      'items', coalesce((select jsonb_agg(row_to_json(it))
                  from (select id, title, cover_path, cover_blurhash, cover_width, cover_height,
                               like_count, save_count, comment_count, media_count, position
                          from items where subcollection_id = p_id
                           and deleted_at is null and hidden_at is null
                         order by position, created_at desc limit 60) it), '[]'::jsonb));

  elsif p_type = 'collection' then
    result := result || jsonb_build_object(
      'collection', (select row_to_json(c) from (
                       select id, name, slug, description, cover_path, cover_blurhash, accent_color,
                              item_count, subcollection_count, created_at, template_id
                         from collections where id = p_id) c),
      'subcollections', coalesce((select jsonb_agg(row_to_json(s))
                  from (select id, name, slug, cover_path, cover_blurhash, item_count, position
                          from subcollections where collection_id = p_id
                           and deleted_at is null and hidden_at is null
                           and (owner = me
                                or public.is_staff()
                                or public.subcollection_has_content(id))
                         order by position, created_at) s), '[]'::jsonb),
      'items', coalesce((select jsonb_agg(row_to_json(it))
                  from (select id, title, cover_path, cover_blurhash, cover_width, cover_height,
                               like_count, media_count, position, subcollection_id
                          from items where collection_id = p_id
                           and deleted_at is null and hidden_at is null
                         order by position, created_at desc limit 60) it), '[]'::jsonb));

  elsif p_type = 'post' then
    result := result || jsonb_build_object(
      'post', (select row_to_json(p) from (
                 select id, body, kind, entity_type, entity_id, created_at, edited_at
                   from posts where id = p_id) p));
  end if;

  return result;
end $function$;

-- ------------------------------------------------------------- get_matches --
-- Unchanged except that a match's shelf previews skip empty shelves.

create or replace function public.get_matches(p_limit integer default 20, p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare me uuid := public.require_auth(); last_run timestamptz;
begin
  select max(computed_at) into last_run from user_matches where user_id = me;

  if p_force or last_run is null or last_run < now() - interval '6 hours' then
    perform public.refresh_user_taste(me);
    perform public.refresh_matches(me, 60);
  end if;

  return coalesce((select jsonb_agg(row_to_json(x)) from (
    select p.id, p.username::text, p.display_name, p.avatar_path, p.bio, p.is_verified,
           p.follower_count, p.collection_count, p.item_count,
           m.score, m.shared_tags,
           exists (select 1 from follows f where f.follower_id = me and f.following_id = p.id) as viewer_follows,
           coalesce((select jsonb_agg(row_to_json(c)) from (
              select id, name, cover_path, cover_blurhash, item_count
                from collections
               where user_id = p.id and visibility='public' and deleted_at is null and cover_path is not null
                 and public.collection_has_content(id)
               order by item_count desc limit 3) c), '[]'::jsonb) as top_collections
      from user_matches m
      join profiles p on p.id = m.other_id
     where m.user_id = me and p.is_suspended = false
     order by m.score desc limit p_limit) x), '[]'::jsonb);
end $function$;
