-- Klect social integrity foundation (v1.5.0).
--
-- This migration is additive at the public RPC boundary. Existing clients keep
-- using pulse_feed/user_posts/get_post_thread while upgraded clients can adopt
-- the richer envelopes and get_comment_thread without a flag day.

begin;

-- ---------------------------------------------------------------------------
-- Complete media and cover resolution
-- ---------------------------------------------------------------------------

create or replace function public.pulse_entity_media(
  p_type public.entity_type,
  p_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_media jsonb := '[]'::jsonb;
begin
  if p_type is null or p_id is null
     or not public.can_view_entity(p_type, p_id) then
    return v_media;
  end if;

  case p_type
    when 'post' then
      return public.pulse_post_media(p_id);

    when 'item' then
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'id',             m.id,
                 'storage_path',   m.storage_path,
                 'width',          m.width,
                 'height',         m.height,
                 'blurhash',       m.blurhash,
                 'dominant_color', m.dominant_color,
                 'alt_text',       m.alt_text,
                 'position',       m.position
               ) order by m.position, m.created_at
             ), '[]'::jsonb)
        into v_media
        from (
          select im.*
            from public.item_media im
           where im.item_id = p_id
           order by im.position, im.created_at
           limit 4
        ) m;

    when 'collection' then
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'id',             m.id,
                 'storage_path',   m.storage_path,
                 'width',          m.width,
                 'height',         m.height,
                 'blurhash',       m.blurhash,
                 'dominant_color', m.dominant_color,
                 'alt_text',       m.alt_text,
                 'position',       m.out_position
               ) order by m.out_position
             ), '[]'::jsonb)
        into v_media
        from (
          select im.*, row_number() over (
                   order by i.position, i.created_at, im.position, im.created_at
                 )::integer - 1 as out_position
            from public.items i
            join public.item_media im on im.item_id = i.id
           where i.collection_id = p_id
             and i.deleted_at is null
             and i.hidden_at is null
             and public.can_view_entity('item'::public.entity_type, i.id)
           order by i.position, i.created_at, im.position, im.created_at
           limit 4
        ) m;

    when 'subcollection' then
      select coalesce(jsonb_agg(
               jsonb_build_object(
                 'id',             m.id,
                 'storage_path',   m.storage_path,
                 'width',          m.width,
                 'height',         m.height,
                 'blurhash',       m.blurhash,
                 'dominant_color', m.dominant_color,
                 'alt_text',       m.alt_text,
                 'position',       m.out_position
               ) order by m.out_position
             ), '[]'::jsonb)
        into v_media
        from (
          select im.*, row_number() over (
                   order by i.position, i.created_at, im.position, im.created_at
                 )::integer - 1 as out_position
            from public.items i
            join public.item_media im on im.item_id = i.id
           where i.subcollection_id = p_id
             and i.deleted_at is null
             and i.hidden_at is null
             and public.can_view_entity('item'::public.entity_type, i.id)
           order by i.position, i.created_at, im.position, im.created_at
           limit 4
        ) m;

    else
      v_media := '[]'::jsonb;
  end case;

  return coalesce(v_media, '[]'::jsonb);
end;
$$;

comment on function public.pulse_entity_media(public.entity_type, uuid) is
  'Internal: ordered 1-4 media descriptors for a visible Pulse target, including descendant fallback media.';


create or replace function public.pulse_entity_fallback_cover(
  p_type public.entity_type,
  p_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_type is null or p_id is null
      or not public.can_view_entity(p_type, p_id)
      then null
    else (
      with explicit_cover as (
        select c.cover_path as storage_path, c.cover_blurhash as blurhash,
               null::integer as width, null::integer as height
          from public.collections c
         where p_type = 'collection'::public.entity_type and c.id = p_id
        union all
        select s.cover_path, s.cover_blurhash, null::integer, null::integer
          from public.subcollections s
         where p_type = 'subcollection'::public.entity_type and s.id = p_id
        union all
        select i.cover_path, i.cover_blurhash, i.cover_width, i.cover_height
          from public.items i
         where p_type = 'item'::public.entity_type and i.id = p_id
      ),
      chosen as (
        select storage_path, blurhash, width, height
          from explicit_cover
         where storage_path is not null
        union all
        select m ->> 'storage_path',
               m ->> 'blurhash',
               nullif(m ->> 'width', '')::integer,
               nullif(m ->> 'height', '')::integer
          from jsonb_array_elements(public.pulse_entity_media(p_type, p_id)) m
         limit 1
      )
      select jsonb_build_object(
               'path', storage_path,
               'blurhash', blurhash,
               'width', width,
               'height', height
             )
        from chosen
       where storage_path is not null
       limit 1
    )
  end;
$$;

comment on function public.pulse_entity_fallback_cover(public.entity_type, uuid) is
  'Internal: explicit entity cover or first visible descendant/media cover.';


-- ---------------------------------------------------------------------------
-- Canonical PulseTargetEnvelope
-- ---------------------------------------------------------------------------

create or replace function public.pulse_target_payload_depth(
  p_type public.entity_type,
  p_id uuid,
  p_depth integer
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
  v_media jsonb;
  v_cover jsonb;
begin
  if p_type is null or p_id is null then
    return null;
  end if;

  if not public.can_view_entity(p_type, p_id) then
    return jsonb_build_object(
      'type', p_type::text,
      'id', p_id,
      'availability', 'unavailable',
      'unavailable', true,
      'media', '[]'::jsonb
    );
  end if;

  v_media := public.pulse_entity_media(p_type, p_id);
  v_cover := public.pulse_entity_fallback_cover(p_type, p_id);

  case p_type
    when 'collection' then
      select jsonb_build_object(
               'type', 'collection', 'id', c.id,
               'availability', 'available', 'unavailable', false,
               'title', c.name, 'subtitle', c.description, 'body', null,
               'cover_path', coalesce(c.cover_path, v_cover ->> 'path'),
               'cover_blurhash', coalesce(c.cover_blurhash, v_cover ->> 'blurhash'),
               'cover_width', nullif(v_cover ->> 'width', '')::integer,
               'cover_height', nullif(v_cover ->> 'height', '')::integer,
               'media', v_media,
               'child_count', c.item_count, 'like_count', c.like_count,
               'created_at', c.created_at,
               'author', jsonb_build_object(
                 'id', pr.id, 'username', pr.username::text,
                 'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
                 'is_verified', pr.is_verified
               ),
               'attached_target', null
             )
        into v
        from public.collections c
        join public.profiles pr on pr.id = c.user_id
       where c.id = p_id;

    when 'subcollection' then
      select jsonb_build_object(
               'type', 'subcollection', 'id', s.id,
               'availability', 'available', 'unavailable', false,
               'title', s.name, 'subtitle', s.description, 'body', null,
               'cover_path', coalesce(s.cover_path, v_cover ->> 'path'),
               'cover_blurhash', coalesce(s.cover_blurhash, v_cover ->> 'blurhash'),
               'cover_width', nullif(v_cover ->> 'width', '')::integer,
               'cover_height', nullif(v_cover ->> 'height', '')::integer,
               'media', v_media,
               'child_count', s.item_count, 'like_count', s.like_count,
               'created_at', s.created_at,
               'author', jsonb_build_object(
                 'id', pr.id, 'username', pr.username::text,
                 'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
                 'is_verified', pr.is_verified
               ),
               'attached_target', null
             )
        into v
        from public.subcollections s
        join public.profiles pr on pr.id = s.user_id
       where s.id = p_id;

    when 'item' then
      select jsonb_build_object(
               'type', 'item', 'id', i.id,
               'availability', 'available', 'unavailable', false,
               'title', i.title,
               'subtitle', coalesce(nullif(i.description, ''), i.brand),
               'body', null,
               'cover_path', coalesce(i.cover_path, v_cover ->> 'path'),
               'cover_blurhash', coalesce(i.cover_blurhash, v_cover ->> 'blurhash'),
               'cover_width', coalesce(i.cover_width, nullif(v_cover ->> 'width', '')::integer),
               'cover_height', coalesce(i.cover_height, nullif(v_cover ->> 'height', '')::integer),
               'media', v_media,
               'child_count', i.media_count, 'like_count', i.like_count,
               'created_at', i.created_at,
               'author', jsonb_build_object(
                 'id', pr.id, 'username', pr.username::text,
                 'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
                 'is_verified', pr.is_verified
               ),
               'attached_target', null
             )
        into v
        from public.items i
        join public.profiles pr on pr.id = i.user_id
       where i.id = p_id;

    when 'post' then
      select jsonb_build_object(
               'type', 'post', 'id', p.id,
               'availability', 'available', 'unavailable', false,
               'title', null, 'subtitle', null, 'body', p.body,
               'kind', p.kind::text,
               'cover_path', v_cover ->> 'path',
               'cover_blurhash', v_cover ->> 'blurhash',
               'cover_width', nullif(v_cover ->> 'width', '')::integer,
               'cover_height', nullif(v_cover ->> 'height', '')::integer,
               'media', v_media,
               'child_count', p.reply_count, 'like_count', p.like_count,
               'created_at', p.created_at,
               'author', jsonb_build_object(
                 'id', pr.id, 'username', pr.username::text,
                 'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
                 'is_verified', pr.is_verified
               ),
               'attached_target',
                 case
                   when p_depth < 1 and p.entity_type is not null and p.entity_id is not null
                     then public.pulse_target_payload_depth(
                       p.entity_type, p.entity_id, p_depth + 1
                     )
                   else null
                 end
             )
        into v
        from public.posts p
        join public.profiles pr on pr.id = p.author_id
       where p.id = p_id;

    when 'comment' then
      select jsonb_build_object(
               'type', 'comment', 'id', c.id,
               'availability', 'available', 'unavailable', false,
               'title', null, 'subtitle', null, 'body', c.body,
               'cover_path', null, 'cover_blurhash', null,
               'cover_width', null, 'cover_height', null,
               'media', '[]'::jsonb,
               'child_count', c.reply_count, 'like_count', c.like_count,
               'created_at', c.created_at,
               'parent_type', c.entity_type::text,
               'parent_id', c.entity_id,
               'author', jsonb_build_object(
                 'id', pr.id, 'username', pr.username::text,
                 'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
                 'is_verified', pr.is_verified
               ),
               'attached_target', null
             )
        into v
        from public.comments c
        join public.profiles pr on pr.id = c.author_id
       where c.id = p_id;
  end case;

  return coalesce(v, jsonb_build_object(
    'type', p_type::text,
    'id', p_id,
    'availability', 'unavailable',
    'unavailable', true,
    'media', '[]'::jsonb
  ));
end;
$$;


create or replace function public.pulse_target_payload(
  p_type public.entity_type,
  p_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select public.pulse_target_payload_depth(p_type, p_id, 0);
$$;

comment on function public.pulse_target_payload(public.entity_type, uuid) is
  'Canonical PulseTargetEnvelope: author, text, timestamp, ordered 1-4 media, one nested attachment level, and explicit availability.';


create or replace function public.pulse_repost_envelope(
  p_type public.entity_type,
  p_id uuid,
  p_reposter uuid,
  p_quote text,
  p_at timestamptz,
  p_viewer uuid
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'feed_kind',        'repost',
           'kind',             null,
           'post_id',          null,
           'cursor_id',        p_id,
           'entity_type',      p_type::text,
           'entity_id',        p_id,
           'sort_at',          p_at,
           'created_at',       p_at,
           'actor_id',         public.entity_owner(p_type, p_id),
           'reposter_id',      p_reposter,
           'quote_text',       p_quote,
           'body',             null,
           'target_type',      p_type::text,
           'target_id',        p_id,
           'reply_to_post_id', null,
           'root_post_id',     null,
           'like_count',       public.entity_counter(p_type, p_id, 'like_count'),
           'save_count',       public.entity_counter(p_type, p_id, 'save_count'),
           'repost_count',     public.entity_counter(p_type, p_id, 'repost_count'),
           'comment_count',    public.entity_counter(p_type, p_id, 'comment_count'),
           'view_count',       public.entity_counter(p_type, p_id, 'view_count'),
           'reply_count',      0,
           'author',           (select jsonb_build_object(
                                  'id', pr.id, 'username', pr.username::text,
                                  'display_name', pr.display_name,
                                  'avatar_path', pr.avatar_path,
                                  'is_verified', pr.is_verified)
                                  from public.profiles pr
                                 where pr.id = public.entity_owner(p_type, p_id)),
           'reposter',         (select jsonb_build_object(
                                  'id', pr2.id, 'username', pr2.username::text,
                                  'display_name', pr2.display_name,
                                  'avatar_path', pr2.avatar_path,
                                  'is_verified', pr2.is_verified)
                                  from public.profiles pr2 where pr2.id = p_reposter),
           'viewer_liked',     exists (select 1 from public.likes l
                                        where l.entity_type = p_type
                                          and l.entity_id = p_id
                                          and l.user_id = p_viewer),
           'viewer_saved',     exists (select 1 from public.saves s
                                        where s.entity_type = p_type
                                          and s.entity_id = p_id
                                          and s.user_id = p_viewer),
           'viewer_reposted',  exists (select 1 from public.reposts r2
                                        where r2.entity_type = p_type
                                          and r2.entity_id = p_id
                                          and r2.user_id = p_viewer),
           -- Keep older clients media-capable while new clients consume target.
           'media',            public.pulse_entity_media(p_type, p_id),
           'target',           public.pulse_target_payload(p_type, p_id)
         );
$$;


-- ---------------------------------------------------------------------------
-- Following feed correctness
-- ---------------------------------------------------------------------------

-- The existing signature is retained. The following branch now includes the
-- viewer's own reposts and applies actor suspension/block/mute gates equally to
-- posts and reposts. Its existing composite (timestamp,id) cursor remains
-- backward compatible.
create or replace function public.pulse_feed_ranked_v1(
  p_limit integer default 25,
  p_before timestamptz default null,
  p_before_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  -- Forward declaration replaced with the complete body below. Keeping it
  -- before pulse_feed lets PostgreSQL validate that dependency atomically.
  return '[]'::jsonb;
end;
$$;

create or replace function public.pulse_feed(
  p_limit integer default 25,
  p_before timestamptz default null,
  p_mode text default 'following',
  p_before_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me      uuid    := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_take  integer := greatest(1, least(coalesce(p_limit, 25), 50)) + 1;
begin
  if p_mode not in ('following', 'foryou') then
    raise exception 'bad_mode';
  end if;

  -- Keep the mature discovery ranking from 0021. Rich target envelopes are
  -- already supplied by the replaced helpers above.
  if p_mode = 'foryou' then
    return public.pulse_feed_ranked_v1(
      p_limit => v_limit,
      p_before => p_before,
      p_before_id => p_before_id
    );
  end if;

  return coalesce((
    with heads as (
      (
        select 'post'::text as feed_kind,
               p.id as cursor_id,
               p.id as post_id,
               null::public.entity_type as repost_type,
               null::uuid as repost_id,
               null::uuid as reposter_id,
               null::text as quote_text,
               p.created_at as sort_at
          from public.posts p
          join public.profiles actor on actor.id = p.author_id
         where p.deleted_at is null
           and p.hidden_at is null
           and p.reply_to_post_id is null
           and actor.is_suspended = false
           and (
             p.author_id = me
             or exists (
               select 1 from public.follows f
                where f.follower_id = me and f.following_id = p.author_id
             )
           )
           and public.can_view_entity('post'::public.entity_type, p.id)
           and not exists (
             select 1 from public.blocks b
              where (b.blocker_id = me and b.blocked_id = p.author_id)
                 or (b.blocker_id = p.author_id and b.blocked_id = me)
           )
           and not exists (
             select 1 from public.mutes mu
              where mu.muter_id = me and mu.muted_id = p.author_id
           )
           and (
             p_before is null
             or (p_before_id is null and p.created_at < p_before)
             or (p_before_id is not null
                 and (p.created_at, p.id) < (p_before, p_before_id))
           )
         order by p.created_at desc, p.id desc
         limit v_take
      )
      union all
      (
        select 'repost', r.entity_id, null::uuid,
               r.entity_type, r.entity_id, r.user_id, r.quote_text,
               r.created_at
          from public.reposts r
          join public.profiles actor on actor.id = r.user_id
         where actor.is_suspended = false
           and (
             r.user_id = me
             or exists (
               select 1 from public.follows f
                where f.follower_id = me and f.following_id = r.user_id
             )
           )
           and public.can_view_entity(r.entity_type, r.entity_id)
           and not exists (
             select 1 from public.blocks b
              where (b.blocker_id = me and b.blocked_id = r.user_id)
                 or (b.blocker_id = r.user_id and b.blocked_id = me)
           )
           and not exists (
             select 1 from public.mutes mu
              where mu.muter_id = me and mu.muted_id = r.user_id
           )
           and (
             p_before is null
             or (p_before_id is null and r.created_at < p_before)
             or (p_before_id is not null
                 and (r.created_at, r.entity_id) < (p_before, p_before_id))
           )
         order by r.created_at desc, r.entity_id desc
         limit v_take
      )
    ),
    page as (
      select *
        from heads
       order by sort_at desc, cursor_id desc
       limit v_take
    )
    select jsonb_agg(
             (
               case
                 when h.feed_kind = 'post'
                   then public.pulse_post_envelope(h.post_id, me)
                 else public.pulse_repost_envelope(
                   h.repost_type, h.repost_id, h.reposter_id,
                   h.quote_text, h.sort_at, me
                 )
               end
             ) || jsonb_build_object(
               'cursor', jsonb_build_object(
                 'sort_at', h.sort_at,
                 'id', h.cursor_id
               )
             )
             order by h.sort_at desc, h.cursor_id desc
           )
      from page h
  ), '[]'::jsonb);
end;
$$;

-- Preserve the previous For You implementation under an internal name before
-- pulse_feed above calls it. The body is intentionally a wrapper around a new
-- score-stable implementation, not recursive pulse_feed.
create or replace function public.pulse_feed_ranked_v1(
  p_limit integer default 25,
  p_before timestamptz default null,
  p_before_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_take integer := greatest(1, least(coalesce(p_limit, 25), 50)) + 1;
begin
  return coalesce((
    with candidates as (
      select 'post'::text as feed_kind,
             p.id as cursor_id,
             p.id as post_id,
             null::public.entity_type as repost_type,
             null::uuid as repost_id,
             null::uuid as reposter_id,
             null::text as quote_text,
             p.author_id as actor_id,
             p.created_at as sort_at,
             (
               ln(1 + p.like_count * 3 + p.save_count * 5
                    + p.repost_count * 4 + p.comment_count * 2
                    + p.view_count * 0.2) * 0.9
               / (1 + extract(epoch from (now() - p.created_at)) / 172800.0)
               + 3.0 / (1 + extract(epoch from (now() - p.created_at)) / 86400.0)
               + case when exists (
                   select 1 from public.follows f
                    where f.follower_id = me and f.following_id = p.author_id
                 ) then 0.6 else 0 end
               + case when p.author_id = me then -1.2 else 0 end
             )::real as score
        from public.posts p
        join public.profiles actor on actor.id = p.author_id
       where p.deleted_at is null
         and p.hidden_at is null
         and p.reply_to_post_id is null
         and actor.is_suspended = false
         and public.can_view_entity('post'::public.entity_type, p.id)
         and not exists (
           select 1 from public.blocks b
            where (b.blocker_id = me and b.blocked_id = p.author_id)
               or (b.blocker_id = p.author_id and b.blocked_id = me)
         )
         and not exists (
           select 1 from public.mutes mu
            where mu.muter_id = me and mu.muted_id = p.author_id
         )
         and (
           p_before is null
           or (p_before_id is null and p.created_at < p_before)
           or (p_before_id is not null
               and (p.created_at, p.id) < (p_before, p_before_id))
         )
       order by p.created_at desc
       limit 600
    ),
    capped as (
      select c.*,
             row_number() over (
               partition by c.actor_id
               order by c.score desc, c.sort_at desc, c.cursor_id desc
             ) as actor_rank
        from candidates c
    ),
    page as (
      select *
        from capped
       where actor_rank <= 3
       order by score desc, sort_at desc, cursor_id desc
       limit v_take
    )
    select jsonb_agg(
             public.pulse_post_envelope(p.post_id, me)
             || jsonb_build_object(
               'score', p.score,
               'cursor', jsonb_build_object(
                 'score', p.score,
                 'sort_at', p.sort_at,
                 'id', p.cursor_id
               )
             )
             order by p.score desc, p.sort_at desc, p.cursor_id desc
           )
      from page p
  ), '[]'::jsonb);
end;
$$;


-- ---------------------------------------------------------------------------
-- Shared Reddit-style comment tree RPC
-- ---------------------------------------------------------------------------

create index if not exists comments_root_top_page_idx
  on public.comments (
    entity_type, entity_id, like_count desc, created_at desc, id desc
  )
  where parent_id is null;

create index if not exists comments_parent_page_idx
  on public.comments (parent_id, created_at, id);


create or replace function public.get_comment_thread(
  p_type public.entity_type,
  p_id uuid,
  p_limit integer default 20,
  p_cursor jsonb default null,
  p_sort text default 'top'
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
  v_cursor_at timestamptz := nullif(p_cursor ->> 'created_at', '')::timestamptz;
  v_cursor_id uuid := nullif(p_cursor ->> 'id', '')::uuid;
  v_cursor_likes integer := nullif(p_cursor ->> 'like_count', '')::integer;
begin
  if p_sort not in ('top', 'new') then
    raise exception 'bad_sort';
  end if;

  if not public.can_view_entity(p_type, p_id) then
    return jsonb_build_object(
      'nodes', '[]'::jsonb,
      'has_more', false,
      'next_cursor', null,
      'unavailable', true
    );
  end if;

  return (
    with recursive root_candidates as (
      select c.*
        from public.comments c
        left join public.profiles pr on pr.id = c.author_id
       where c.entity_type = p_type
         and c.entity_id = p_id
         and c.parent_id is null
         and c.hidden_at is null
         and (
           c.deleted_at is not null
           or (
             pr.is_suspended = false
             and (
               me is null
               or not exists (
                 select 1 from public.blocks b
                  where (b.blocker_id = me and b.blocked_id = c.author_id)
                     or (b.blocker_id = c.author_id and b.blocked_id = me)
               )
             )
           )
         )
         and (
           p_cursor is null
           or (
             p_sort = 'new'
             and (c.created_at, c.id) < (v_cursor_at, v_cursor_id)
           )
           or (
             p_sort = 'top'
             and (c.like_count, c.created_at, c.id)
                 < (v_cursor_likes, v_cursor_at, v_cursor_id)
           )
         )
       order by
         case when p_sort = 'top' then c.like_count end desc nulls last,
         c.created_at desc,
         c.id desc
       limit v_limit + 1
    ),
    numbered_roots as (
      select r.*,
             row_number() over (
               order by
                 case when p_sort = 'top' then r.like_count end desc nulls last,
                 r.created_at desc,
                 r.id desc
             ) as page_number
        from root_candidates r
    ),
    page_roots as (
      select * from numbered_roots where page_number <= v_limit
    ),
    recursive_tree as (
      select r.id, r.parent_id, r.id as root_id, 0 as relative_depth,
             r.created_at
        from page_roots r
      union all
      select child.id, child.parent_id, tree.root_id,
             tree.relative_depth + 1, child.created_at
        from recursive_tree tree
        join public.comments child on child.parent_id = tree.id
       where tree.relative_depth < 24
         and child.entity_type = p_type
         and child.entity_id = p_id
         and child.hidden_at is null
    ),
    hydrated as (
      select c.*, tree.root_id, tree.relative_depth,
             parent.author_id as parent_author_id,
             parent_profile.username::text as parent_username,
             case when c.deleted_at is null then c.body else null end as visible_body,
             c.deleted_at is not null as is_deleted,
             jsonb_build_object(
               'id', pr.id,
               'username', pr.username::text,
               'display_name', pr.display_name,
               'avatar_path', pr.avatar_path,
               'is_verified', pr.is_verified
             ) as author,
             exists (
               select 1 from public.likes l
                where l.user_id = me
                  and l.entity_type = 'comment'::public.entity_type
                  and l.entity_id = c.id
             ) as viewer_liked,
             exists (
               select 1 from public.saves s
                where s.user_id = me
                  and s.entity_type = 'comment'::public.entity_type
                  and s.entity_id = c.id
             ) as viewer_saved,
             exists (
               select 1 from public.reposts rp
                where rp.user_id = me
                  and rp.entity_type = 'comment'::public.entity_type
                  and rp.entity_id = c.id
             ) as viewer_reposted
        from recursive_tree tree
        join public.comments c on c.id = tree.id
        left join public.profiles pr on pr.id = c.author_id
        left join public.comments parent on parent.id = c.parent_id
        left join public.profiles parent_profile on parent_profile.id = parent.author_id
       where c.deleted_at is not null
          or (
            pr.is_suspended = false
            and (
              me is null
              or not exists (
                select 1 from public.blocks b
                 where (b.blocker_id = me and b.blocked_id = c.author_id)
                    or (b.blocker_id = c.author_id and b.blocked_id = me)
              )
            )
          )
    ),
    ordered_nodes as (
      select h.*,
             row_number() over (
               partition by h.root_id
               order by h.relative_depth, h.created_at, h.id
             ) as branch_order
        from hydrated h
    ),
    last_root as (
      select *
        from page_roots
       order by page_number desc
       limit 1
    )
    select jsonb_build_object(
      'nodes', coalesce((
        select jsonb_agg(
                 jsonb_build_object(
                   'id', n.id,
                   'entity_type', n.entity_type::text,
                   'entity_id', n.entity_id,
                   'author_id', n.author_id,
                   'root_id', n.root_id,
                   'parent_id', n.parent_id,
                   'depth', n.depth,
                   'relative_depth', n.relative_depth,
                   'body', n.visible_body,
                   'author', n.author,
                   'created_at', n.created_at,
                   'edited_at', n.edited_at,
                   'deleted', n.is_deleted,
                   'tombstone', n.is_deleted,
                   'like_count', n.like_count,
                   'save_count', n.save_count,
                   'repost_count', n.repost_count,
                   'reply_count', n.reply_count,
                   'replying_to', case
                     when n.parent_id is null then null
                     else jsonb_build_object(
                       'id', n.parent_id,
                       'author_id', n.parent_author_id,
                       'username', n.parent_username
                     )
                   end,
                   'viewer', jsonb_build_object(
                     'liked', n.viewer_liked,
                     'saved', n.viewer_saved,
                     'reposted', n.viewer_reposted
                   )
                 )
                 order by
                   (select pr.page_number from page_roots pr where pr.id = n.root_id),
                   n.branch_order
               )
          from ordered_nodes n
      ), '[]'::jsonb),
      'has_more', (select count(*) > v_limit from numbered_roots),
      'next_cursor', (
        select jsonb_build_object(
                 'created_at', r.created_at,
                 'id', r.id,
                 'like_count', r.like_count
               )
          from last_root r
      ),
      'unavailable', false
    )
  );
end;
$$;


-- ---------------------------------------------------------------------------
-- ACL
-- ---------------------------------------------------------------------------

revoke execute on function public.pulse_entity_media(public.entity_type, uuid)
  from public, anon, authenticated;
revoke execute on function public.pulse_entity_fallback_cover(public.entity_type, uuid)
  from public, anon, authenticated;
revoke execute on function public.pulse_target_payload_depth(public.entity_type, uuid, integer)
  from public, anon, authenticated;
revoke execute on function public.pulse_target_payload(public.entity_type, uuid)
  from public, anon, authenticated;
revoke execute on function public.pulse_repost_envelope(
  public.entity_type, uuid, uuid, text, timestamptz, uuid
) from public, anon, authenticated;
revoke execute on function public.pulse_feed_ranked_v1(integer, timestamptz, uuid)
  from public, anon, authenticated;

revoke execute on function public.pulse_feed(integer, timestamptz, text, uuid)
  from public, anon;
grant execute on function public.pulse_feed(integer, timestamptz, text, uuid)
  to authenticated, service_role;

revoke execute on function public.get_comment_thread(
  public.entity_type, uuid, integer, jsonb, text
) from public;
grant execute on function public.get_comment_thread(
  public.entity_type, uuid, integer, jsonb, text
) to anon, authenticated, service_role;

commit;
