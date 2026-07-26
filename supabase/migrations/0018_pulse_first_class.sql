-- ============================================================================
-- 0018_pulse_first_class.sql — posts become first-class Pulse citizens
--
-- Implements docs/REDESIGN_PLAN.md B1 items 1–4.
--
--   1. `post_media` — mirrors `item_media` (same columns/types, same RLS
--      posture: owner-write, `can_view_entity('post', …)` read, cascade FKs,
--      (post_id, "position") + (user_id) indexes). Storage: uploads ride the
--      existing `media`-bucket INSERT policy, which pins only the FIRST path
--      segment to the uploader's uid — so the new path convention
--      `{user_id}/posts/{post_id}/{uuid}.webp` needs NO storage DDL. It is the
--      documented convention as of this migration (create_post additionally
--      refuses any descriptor whose first path segment isn't the caller).
--
--   2. `create_post(p_body, p_kind, p_entity_type, p_entity_id, p_media,
--      p_reply_to) -> jsonb` — THE insert path for posts. Validates auth +
--      suspension (require_auth), body-or-attachment, target visibility
--      (can_view_entity) and blocks, reply threading (root_post_id =
--      coalesce(parent.root, parent.id); posts have no depth column — the
--      `posts_struct` trigger keeps parent reply_count), and turns p_media
--      descriptors into post_media rows. `kind` is DERIVED server-side
--      (p_reply_to → 'reply'; entity_type='post' → 'quote'; else 'post');
--      p_kind is accepted for contract stability. Emits the same
--      notifications a comment-reply / repost would (notify() self-guards
--      against self and blocked pairs). Returns the post's full pulse
--      envelope so composers can prepend it to the stream verbatim.
--
--   3. `pulse_feed(p_limit, p_before, p_mode)` rewrite:
--      · BUG FIX — the old LIMIT sat after jsonb_agg had already collapsed
--        the set to one row, so a page returned up to 100 entries no matter
--        what p_limit said. The limit now applies to the unioned rows BEFORE
--        aggregation (and per-branch limits are p_limit, not 50).
--      · BUG FIX — repost rows hardcoded viewer_reposted=true; it is now the
--        viewer's real state.
--      · `p_mode` ∈ 'following' (default, semantics preserved) | 'foryou' —
--        engagement (ln-damped like/save/repost/comment/view blend) with
--        time-decay + freshness + viewer tag-taste (entity_tags × user_taste,
--        surf_feed's idiom) + cached author match (user_matches) + follow
--        bonus, author diversity cap (max 3 posts/author/page), candidates
--        limited to visible non-blocked non-muted non-suspended authors over
--        the last 30 days. Foryou pages are score-ordered; clients should use
--        min(sort_at) on screen as the next p_before.
--      · Envelope PRESERVED and EXTENDED. Every key the clients parse today
--        (web PulseEntry in web/src/lib/types.ts, mobile PulseEntry/PulseItem)
--        is emitted unchanged: feed_kind, post_id, sort_at, actor_id,
--        reposter_id, quote_text, body, target_type, target_id, like_count,
--        save_count, repost_count, comment_count, view_count, reply_count,
--        author{username,display_name,avatar_path,is_verified},
--        reposter{username,display_name}, viewer_liked/saved/reposted.
--        NEW keys (additive): kind, entity_type, entity_id, created_at,
--        reply_to_post_id, root_post_id, media[] (the post's own photos),
--        target (server-embedded payload of the attached/quoted/reposted
--        thing: type,id,title,subtitle,body,cover_path,cover_blurhash,
--        cover_width,cover_height,child_count,like_count,created_at,author —
--        or {type,id,unavailable:true} when not visible), and author/reposter
--        gain `id` (+ reposter gains avatar_path/is_verified). This is what
--        makes "repost of a post" render: target carries the quoted post's
--        body/author/first-media server-side.
--
--   4. Hardening (extends 0007, which only restricted UPDATE):
--      · `posts`: table-level INSERT revoked from `authenticated` entirely —
--        create_post is the only path. ⚠ The web composer's direct insert
--        (web/src/app/(app)/pulse/_components/PulseComposer.tsx, .from('posts')
--        .insert(...)) will fail with 42501 the moment this applies; B5w
--        replaces it with rpc('create_post', …). Sequence B5w promptly.
--      · `collections` / `subcollections` / `items` / `comments`: table-level
--        INSERT replaced with column lists that exclude every counter column
--        (like/save/repost/comment/view/item/subcollection/media/reply
--        counts), moderation stamps (hidden_at), soft-delete/audit stamps and
--        the generated search_tsv — closing the "seed a row with
--        like_count=999999" gap. Column lists are a superset of what both
--        clients actually insert today (verified against
--        web/src/components/social/queries.ts and
--        mobile/lib/core/api/klect_api.dart).
--      · `item_media` has no counter columns — no gap, unchanged.
--      · NOTED, out of B1's audit list: `profiles` still has table-level
--        INSERT granted to authenticated (counters + is_verified spoofable at
--        insert if a profile row didn't already exist). Clients never insert
--        profiles (signup trigger does); recommend closing in a follow-up.
--      · `posts_check` (body OR entity required) is DROPPED: media-only posts
--        are now legal and a CHECK cannot see post_media. create_post — the
--        only remaining insert path — enforces body-or-attachment instead.
--
-- Posture matches 0012/0017: SECURITY DEFINER, search_path pinned to '',
-- fully-qualified references, EXECUTE revoked from public/anon and granted to
-- a named surface. The three pulse_* envelope helpers are internal: EXECUTE
-- revoked from public/anon/authenticated; only owner-run definer functions
-- (pulse_feed, create_post) call them.
--
-- Stable snake_case error texts (mapped to human copy by the clients):
--   bad_mode                        pulse_feed p_mode not following|foryou
--   body_too_long                   > 2000 chars (matches posts_body_check)
--   body_or_attachment_required     no body, no entity, no media
--   bad_target                      exactly one of p_entity_type/p_entity_id
--   entity_not_found                target invisible to caller
--   reply_not_found                 parent post missing/deleted/invisible
--   blocked                         blocks pair with target author/owner
--   bad_media                       p_media not an array / bad descriptor
--   too_many_media                  more than 4 descriptors
--   media_not_yours                 storage_path not under caller's uid
-- (plus require_auth's existing 'Authentication required' / 'Account
--  suspended', errcode 42501)
--
-- STATUS: ⚠ NOT YET APPLIED to `new_klect` (dikhuygcwxnrsckqglzg).
-- Apply via Supabase MCP `apply_migration` as version 0018_pulse_first_class,
-- then: smoke under JWT impersonation (create post w/ media descriptor, quote
-- a post, foryou vs following ordering, LIMIT respected), run get_advisors,
-- regenerate web/src/lib/database.types.ts, update BACKEND_API.md §2/§4.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. post_media — mirrors item_media
-- ----------------------------------------------------------------------------
create table public.post_media (
  id             uuid        not null default gen_random_uuid() primary key,
  post_id        uuid        not null references public.posts(id)    on delete cascade,
  user_id        uuid        not null references public.profiles(id) on delete cascade,
  storage_path   text        not null,
  alt_text       text        check (char_length(alt_text) <= 300),
  width          integer,
  height         integer,
  blurhash       text,
  dominant_color text,
  mime_type      text,
  bytes          bigint,
  "position"     smallint    not null default 0,
  created_at     timestamptz not null default now()
);

comment on table public.post_media is
  'Photos attached to a Pulse post. Mirrors item_media. Storage convention: media bucket, {user_id}/posts/{post_id}/{uuid}.webp.';

create index post_media_post_idx on public.post_media (post_id, "position");
create index post_media_user_idx on public.post_media (user_id);

alter table public.post_media enable row level security;
alter table public.post_media force  row level security;

create policy post_media_read on public.post_media
  for select using (public.can_view_entity('post'::public.entity_type, post_id));

create policy post_media_insert on public.post_media
  for insert with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.posts p
                where p.id = post_media.post_id
                  and p.author_id = (select auth.uid()))
  );

create policy post_media_update on public.post_media
  for update using (user_id = (select auth.uid()));

create policy post_media_delete on public.post_media
  for delete using (user_id = (select auth.uid()) or public.is_staff());

-- privileges: shaped like item_media's post-0007 posture, but column-scoped
-- INSERT from day one (id/created_at come from defaults; storage_path is
-- immutable after insert, matching item_media's UPDATE column list).
revoke all on table public.post_media from public, anon, authenticated;
grant select on table public.post_media to anon, authenticated;
grant insert (post_id, user_id, storage_path, alt_text, width, height,
              blurhash, dominant_color, mime_type, bytes, "position")
  on public.post_media to authenticated;
grant update (alt_text, blurhash, dominant_color, height, width, "position")
  on public.post_media to authenticated;
grant delete on table public.post_media to authenticated;

-- feed scans (both modes filter exactly this way before ordering by recency)
create index if not exists posts_feed_idx
  on public.posts (created_at desc)
  where deleted_at is null and hidden_at is null and reply_to_post_id is null;


-- ----------------------------------------------------------------------------
-- 2. Internal envelope helpers (not part of the RPC surface)
-- ----------------------------------------------------------------------------

-- All photos of a post, ordered. '[]' when none.
create or replace function public.pulse_post_media(p_post uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
           jsonb_agg(jsonb_build_object(
             'id',             pm.id,
             'storage_path',   pm.storage_path,
             'width',          pm.width,
             'height',         pm.height,
             'blurhash',       pm.blurhash,
             'dominant_color', pm.dominant_color,
             'alt_text',       pm.alt_text,
             'position',       pm."position"
           ) order by pm."position", pm.created_at),
           '[]'::jsonb)
    from public.post_media pm
   where pm.post_id = p_post;
$$;

comment on function public.pulse_post_media(uuid) is
  'Internal: ordered media array for a post envelope. Not REST-callable.';


-- The server-embedded preview of an attached / quoted / reposted thing.
-- Uniform keys across types; {type,id,unavailable:true} when not visible to
-- the caller — so a repost of vanished content renders as a tombstone, never
-- as an empty card.
create or replace function public.pulse_target_payload(p_type public.entity_type, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if p_type is null or p_id is null then
    return null;
  end if;

  if not public.can_view_entity(p_type, p_id) then
    return jsonb_build_object('type', p_type::text, 'id', p_id, 'unavailable', true);
  end if;

  case p_type
    when 'collection' then
      select jsonb_build_object(
               'type', 'collection', 'id', c.id, 'unavailable', false,
               'title', c.name, 'subtitle', c.description, 'body', null,
               'cover_path', c.cover_path, 'cover_blurhash', c.cover_blurhash,
               'cover_width', null, 'cover_height', null,
               'child_count', c.item_count, 'like_count', c.like_count,
               'created_at', c.created_at,
               'author', (select jsonb_build_object(
                            'id', pr.id, 'username', pr.username::text,
                            'display_name', pr.display_name,
                            'avatar_path', pr.avatar_path,
                            'is_verified', pr.is_verified)
                            from public.profiles pr where pr.id = c.user_id))
        into v
        from public.collections c where c.id = p_id;

    when 'subcollection' then
      select jsonb_build_object(
               'type', 'subcollection', 'id', s.id, 'unavailable', false,
               'title', s.name, 'subtitle', s.description, 'body', null,
               'cover_path', s.cover_path, 'cover_blurhash', s.cover_blurhash,
               'cover_width', null, 'cover_height', null,
               'child_count', s.item_count, 'like_count', s.like_count,
               'created_at', s.created_at,
               'author', (select jsonb_build_object(
                            'id', pr.id, 'username', pr.username::text,
                            'display_name', pr.display_name,
                            'avatar_path', pr.avatar_path,
                            'is_verified', pr.is_verified)
                            from public.profiles pr where pr.id = s.user_id))
        into v
        from public.subcollections s where s.id = p_id;

    when 'item' then
      select jsonb_build_object(
               'type', 'item', 'id', i.id, 'unavailable', false,
               'title', i.title, 'subtitle', i.brand, 'body', null,
               'cover_path', i.cover_path, 'cover_blurhash', i.cover_blurhash,
               'cover_width', i.cover_width, 'cover_height', i.cover_height,
               'child_count', i.media_count, 'like_count', i.like_count,
               'created_at', i.created_at,
               'author', (select jsonb_build_object(
                            'id', pr.id, 'username', pr.username::text,
                            'display_name', pr.display_name,
                            'avatar_path', pr.avatar_path,
                            'is_verified', pr.is_verified)
                            from public.profiles pr where pr.id = i.user_id))
        into v
        from public.items i where i.id = p_id;

    when 'post' then
      -- quoted post: body + author + FIRST photo as the cover
      select jsonb_build_object(
               'type', 'post', 'id', pp.id, 'unavailable', false,
               'title', null, 'subtitle', null, 'body', pp.body,
               'kind', pp.kind::text,
               'cover_path', m.storage_path, 'cover_blurhash', m.blurhash,
               'cover_width', m.width, 'cover_height', m.height,
               'child_count', pp.reply_count, 'like_count', pp.like_count,
               'created_at', pp.created_at,
               'author', (select jsonb_build_object(
                            'id', pr.id, 'username', pr.username::text,
                            'display_name', pr.display_name,
                            'avatar_path', pr.avatar_path,
                            'is_verified', pr.is_verified)
                            from public.profiles pr where pr.id = pp.author_id))
        into v
        from public.posts pp
        left join lateral (
          select pm.storage_path, pm.blurhash, pm.width, pm.height
            from public.post_media pm
           where pm.post_id = pp.id
           order by pm."position", pm.created_at
           limit 1
        ) m on true
       where pp.id = p_id;

    when 'comment' then
      select jsonb_build_object(
               'type', 'comment', 'id', cm.id, 'unavailable', false,
               'title', null, 'subtitle', null, 'body', cm.body,
               'cover_path', null, 'cover_blurhash', null,
               'cover_width', null, 'cover_height', null,
               'child_count', cm.reply_count, 'like_count', cm.like_count,
               'created_at', cm.created_at,
               'author', (select jsonb_build_object(
                            'id', pr.id, 'username', pr.username::text,
                            'display_name', pr.display_name,
                            'avatar_path', pr.avatar_path,
                            'is_verified', pr.is_verified)
                            from public.profiles pr where pr.id = cm.author_id))
        into v
        from public.comments cm where cm.id = p_id;
  end case;

  -- can_view said yes but the row raced away: tombstone, not an empty card
  return coalesce(v, jsonb_build_object('type', p_type::text, 'id', p_id, 'unavailable', true));
end;
$$;

comment on function public.pulse_target_payload(public.entity_type, uuid) is
  'Internal: embedded preview of a post''s attached/quoted target for the pulse envelope. Not REST-callable.';


-- One post as a full pulse-stream entry. The single source of the envelope
-- shape — used by pulse_feed (both modes) and returned by create_post.
create or replace function public.pulse_post_envelope(p_post uuid, p_viewer uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'feed_kind',        'post',
           'kind',             p.kind::text,
           'post_id',          p.id,
           'entity_type',      'post',
           'entity_id',        p.id,
           'sort_at',          p.created_at,
           'created_at',       p.created_at,
           'actor_id',         p.author_id,
           'reposter_id',      null,
           'quote_text',       null,
           'body',             p.body,
           'target_type',      p.entity_type::text,
           'target_id',        p.entity_id,
           'reply_to_post_id', p.reply_to_post_id,
           'root_post_id',     p.root_post_id,
           'like_count',       p.like_count,
           'save_count',       p.save_count,
           'repost_count',     p.repost_count,
           'comment_count',    p.comment_count,
           'view_count',       p.view_count,
           'reply_count',      p.reply_count,
           'author',           (select jsonb_build_object(
                                  'id', pr.id, 'username', pr.username::text,
                                  'display_name', pr.display_name,
                                  'avatar_path', pr.avatar_path,
                                  'is_verified', pr.is_verified)
                                  from public.profiles pr where pr.id = p.author_id),
           'reposter',         null,
           'viewer_liked',     exists (select 1 from public.likes l
                                        where l.entity_type = 'post'::public.entity_type
                                          and l.entity_id = p.id and l.user_id = p_viewer),
           'viewer_saved',     exists (select 1 from public.saves s
                                        where s.entity_type = 'post'::public.entity_type
                                          and s.entity_id = p.id and s.user_id = p_viewer),
           'viewer_reposted',  exists (select 1 from public.reposts r
                                        where r.entity_type = 'post'::public.entity_type
                                          and r.entity_id = p.id and r.user_id = p_viewer),
           'media',            public.pulse_post_media(p.id),
           'target',           public.pulse_target_payload(p.entity_type, p.entity_id)
         )
    from public.posts p
   where p.id = p_post;
$$;

comment on function public.pulse_post_envelope(uuid, uuid) is
  'Internal: one post as a pulse-stream entry (the envelope contract). Not REST-callable.';


-- ----------------------------------------------------------------------------
-- 3. create_post — the only insert path for posts
-- ----------------------------------------------------------------------------
create or replace function public.create_post(
  p_body text,
  p_kind public.post_kind default 'post',
  p_entity_type public.entity_type default null,
  p_entity_id uuid default null,
  p_media jsonb default null,
  p_reply_to uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_me            uuid := public.require_auth();
  v_body          text := nullif(trim(coalesce(p_body, '')), '');
  v_kind          public.post_kind;
  v_root          uuid;
  v_parent_author uuid;
  v_parent_root   uuid;
  v_post          uuid;
  v_media_count   integer := 0;
  v_path          text;
  m               record;
begin
  -- body ---------------------------------------------------------------------
  if v_body is not null and char_length(v_body) > 2000 then
    raise exception 'body_too_long';
  end if;

  -- media shape (rows are written after the post exists) ----------------------
  if p_media is not null then
    if jsonb_typeof(p_media) <> 'array' then
      raise exception 'bad_media';
    end if;
    v_media_count := jsonb_array_length(p_media);
    if v_media_count > 4 then
      raise exception 'too_many_media';
    end if;
  end if;

  -- something must be there ---------------------------------------------------
  if v_body is null and p_entity_id is null and v_media_count = 0 then
    raise exception 'body_or_attachment_required';
  end if;

  -- attached entity (share a collection/subcollection/item, or quote a post) --
  if (p_entity_id is null) <> (p_entity_type is null) then
    raise exception 'bad_target';
  end if;
  if p_entity_id is not null then
    if not public.can_view_entity(p_entity_type, p_entity_id) then
      raise exception 'entity_not_found';
    end if;
    if public.blocked_with(public.entity_owner(p_entity_type, p_entity_id)) then
      raise exception 'blocked';
    end if;
  end if;

  -- reply threading -----------------------------------------------------------
  if p_reply_to is not null then
    select pp.author_id, pp.root_post_id
      into v_parent_author, v_parent_root
      from public.posts pp
     where pp.id = p_reply_to
       and pp.deleted_at is null
       and pp.hidden_at is null;
    if not found or not public.can_view_entity('post'::public.entity_type, p_reply_to) then
      raise exception 'reply_not_found';
    end if;
    if public.blocked_with(v_parent_author) then
      raise exception 'blocked';
    end if;
    v_root := coalesce(v_parent_root, p_reply_to);
  end if;

  -- kind is derived; p_kind is accepted for contract stability ----------------
  v_kind := case
              when p_reply_to is not null then 'reply'::public.post_kind
              when p_entity_type = 'post'::public.entity_type then 'quote'::public.post_kind
              else 'post'::public.post_kind
            end;

  insert into public.posts (author_id, kind, body, entity_type, entity_id,
                            reply_to_post_id, root_post_id)
  values (v_me, v_kind, v_body, p_entity_type, p_entity_id, p_reply_to, v_root)
  returning id into v_post;

  -- media descriptors -> post_media rows --------------------------------------
  if v_media_count > 0 then
    for m in
      select value as d, ordinality as ord
        from jsonb_array_elements(p_media) with ordinality
    loop
      if jsonb_typeof(m.d) <> 'object' then
        raise exception 'bad_media';
      end if;
      v_path := m.d->>'storage_path';
      if v_path is null or trim(v_path) = '' then
        raise exception 'bad_media';
      end if;
      -- the object must live under the caller's own storage prefix
      if split_part(v_path, '/', 1) <> v_me::text then
        raise exception 'media_not_yours';
      end if;
      if (m.d ? 'width'    and jsonb_typeof(m.d->'width')    not in ('number','null'))
      or (m.d ? 'height'   and jsonb_typeof(m.d->'height')   not in ('number','null'))
      or (m.d ? 'bytes'    and jsonb_typeof(m.d->'bytes')    not in ('number','null'))
      or (m.d ? 'position' and jsonb_typeof(m.d->'position') not in ('number','null')) then
        raise exception 'bad_media';
      end if;

      insert into public.post_media (post_id, user_id, storage_path, alt_text,
                                     width, height, blurhash, dominant_color,
                                     mime_type, bytes, "position")
      values (v_post, v_me, v_path,
              nullif(m.d->>'alt_text', ''),
              (m.d->>'width')::integer,
              (m.d->>'height')::integer,
              nullif(m.d->>'blurhash', ''),
              nullif(m.d->>'dominant_color', ''),
              nullif(m.d->>'mime_type', ''),
              (m.d->>'bytes')::bigint,
              coalesce((m.d->>'position')::smallint, (m.ord - 1)::smallint));
    end loop;
  end if;

  -- notifications: same shapes notify_social() produces for comment replies
  -- and reposts (notify() drops self-notifications and blocked pairs itself).
  if p_reply_to is not null then
    perform public.notify(v_parent_author, v_me, 'reply'::public.notification_type,
                          'post'::public.entity_type, p_reply_to,
                          null, null, null, null,
                          nullif(left(coalesce(v_body, ''), 140), ''));
  elsif v_kind = 'quote'::public.post_kind then
    perform public.notify(public.entity_owner(p_entity_type, p_entity_id), v_me,
                          'repost'::public.notification_type,
                          p_entity_type, p_entity_id,
                          null, null, null, null,
                          nullif(left(coalesce(v_body, ''), 140), ''));
  end if;

  return public.pulse_post_envelope(v_post, v_me);
end;
$$;

comment on function public.create_post(text, public.post_kind, public.entity_type, uuid, jsonb, uuid) is
  'Create a post/quote/reply (the only insert path for posts). Returns the post''s pulse envelope.';


-- ----------------------------------------------------------------------------
-- 4. pulse_feed — LIMIT fixed, p_mode added, targets embedded
--    (the 2-arg signature must be dropped or PostgREST sees two overloads)
-- ----------------------------------------------------------------------------
drop function if exists public.pulse_feed(integer, timestamptz);

create function public.pulse_feed(
  p_limit integer default 25,
  p_before timestamptz default null,
  p_mode text default 'following'
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me      uuid    := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
begin
  if p_mode not in ('following', 'foryou') then
    raise exception 'bad_mode';
  end if;

  if p_mode = 'foryou' then
    -- Ranked discovery over posts: engagement with time-decay + freshness +
    -- viewer tag-taste + cached author-match + follow bonus, ≤3 posts/author.
    return coalesce((
      with candidates as (
        select p.id, p.author_id, p.entity_type, p.entity_id, p.created_at,
               p.like_count, p.save_count, p.repost_count, p.comment_count, p.view_count
          from public.posts p
          join public.profiles pr on pr.id = p.author_id
         where p.deleted_at is null
           and p.hidden_at is null
           and p.reply_to_post_id is null
           and pr.is_suspended = false
           and (
                 p.author_id = me
              or (pr.account_visibility = 'public'::public.visibility
                  and p.visibility = 'public'::public.visibility)
              or (p.visibility in ('public'::public.visibility, 'followers'::public.visibility)
                  and exists (select 1 from public.follows f
                               where f.follower_id = me and f.following_id = p.author_id))
               )
           and not exists (select 1 from public.blocks b
                            where (b.blocker_id = me and b.blocked_id = p.author_id)
                               or (b.blocker_id = p.author_id and b.blocked_id = me))
           and not exists (select 1 from public.mutes mu
                            where mu.muter_id = me and mu.muted_id = p.author_id)
           and (p_before is null or p.created_at < p_before)
           and p.created_at > now() - interval '30 days'
         order by p.created_at desc
         limit 600
      ),
      affinity as (
        -- surf_feed's taste idiom: the viewer's tag weights over tagged entities
        select et.entity_type as a_type, et.entity_id as a_id, sum(ut.weight)::real as aff
          from public.entity_tags et
          join public.user_taste ut on ut.tag_id = et.tag_id and ut.user_id = me
         group by et.entity_type, et.entity_id
      ),
      scored as (
        select c.*,
               ( ln(1 + c.like_count * 3 + c.save_count * 5 + c.repost_count * 4
                      + c.comment_count * 2 + c.view_count * 0.2) * 0.9
                   / (1 + extract(epoch from (now() - c.created_at)) / 172800.0)  -- engagement decays (2-day scale)
                 + 3.0 / (1 + extract(epoch from (now() - c.created_at)) / 86400.0) -- freshness floor
                 + (coalesce(ap.aff, 0) + coalesce(ae.aff, 0)) * 0.35               -- viewer tag-taste
                 + coalesce(um.score, 0) * 0.8                                      -- cached taste match with the author
                 + case when exists (select 1 from public.follows f
                                      where f.follower_id = me and f.following_id = c.author_id)
                        then 0.6 else 0 end
                 + case when c.author_id = me then -1.2 else 0 end
               )::real as score
          from candidates c
          left join affinity ap on ap.a_type = 'post'::public.entity_type and ap.a_id = c.id
          left join affinity ae on ae.a_type = c.entity_type and ae.a_id = c.entity_id
          left join public.user_matches um on um.user_id = me and um.other_id = c.author_id
      ),
      capped as (
        select s.*,
               row_number() over (partition by s.author_id order by s.score desc) as arn
          from scored s
      ),
      page as (
        select id, score, created_at
          from capped
         where arn <= 3
         order by score desc, created_at desc
         limit v_limit
      )
      select jsonb_agg(public.pulse_post_envelope(page.id, me)
                       order by page.score desc, page.created_at desc)
        from page
    ), '[]'::jsonb);
  end if;

  -- following (default): chronological posts + reposts from people you follow.
  -- Per-branch LIMIT and the page LIMIT both live BEFORE aggregation now.
  return coalesce((
    with heads as (
      (
        select 'post'::text               as fk,
               p.id                       as pid,
               null::public.entity_type   as rt,
               null::uuid                 as rid,
               null::uuid                 as ruser,
               null::text                 as rquote,
               p.created_at               as sort_at
          from public.posts p
         where p.deleted_at is null
           and p.hidden_at is null
           and p.reply_to_post_id is null
           and (p.author_id = me
                or p.author_id in (select f.following_id from public.follows f
                                    where f.follower_id = me))
           and not exists (select 1 from public.blocks b
                            where (b.blocker_id = me and b.blocked_id = p.author_id)
                               or (b.blocker_id = p.author_id and b.blocked_id = me))
           and not exists (select 1 from public.mutes mu
                            where mu.muter_id = me and mu.muted_id = p.author_id)
           and (p_before is null or p.created_at < p_before)
         order by p.created_at desc
         limit v_limit
      )
      union all
      (
        select 'repost', null, r.entity_type, r.entity_id, r.user_id, r.quote_text, r.created_at
          from public.reposts r
         where r.user_id in (select f.following_id from public.follows f
                              where f.follower_id = me)
           and (p_before is null or r.created_at < p_before)
           and public.can_view_entity(r.entity_type, r.entity_id)
         order by r.created_at desc
         limit v_limit
      )
    ),
    page as (
      select * from heads order by sort_at desc limit v_limit
    )
    select jsonb_agg(
             case when h.fk = 'post' then public.pulse_post_envelope(h.pid, me)
             else jsonb_build_object(
               'feed_kind',        'repost',
               'kind',             null,
               'post_id',          null,
               'entity_type',      h.rt::text,
               'entity_id',        h.rid,
               'sort_at',          h.sort_at,
               'created_at',       h.sort_at,
               'actor_id',         public.entity_owner(h.rt, h.rid),
               'reposter_id',      h.ruser,
               'quote_text',       h.rquote,
               'body',             null,
               'target_type',      h.rt::text,
               'target_id',        h.rid,
               'reply_to_post_id', null,
               'root_post_id',     null,
               'like_count',       public.entity_counter(h.rt, h.rid, 'like_count'),
               'save_count',       public.entity_counter(h.rt, h.rid, 'save_count'),
               'repost_count',     public.entity_counter(h.rt, h.rid, 'repost_count'),
               'comment_count',    public.entity_counter(h.rt, h.rid, 'comment_count'),
               'view_count',       public.entity_counter(h.rt, h.rid, 'view_count'),
               'reply_count',      0,
               'author',           (select jsonb_build_object(
                                      'id', pr.id, 'username', pr.username::text,
                                      'display_name', pr.display_name,
                                      'avatar_path', pr.avatar_path,
                                      'is_verified', pr.is_verified)
                                      from public.profiles pr
                                     where pr.id = public.entity_owner(h.rt, h.rid)),
               'reposter',         (select jsonb_build_object(
                                      'id', pr2.id, 'username', pr2.username::text,
                                      'display_name', pr2.display_name,
                                      'avatar_path', pr2.avatar_path,
                                      'is_verified', pr2.is_verified)
                                      from public.profiles pr2 where pr2.id = h.ruser),
               'viewer_liked',     exists (select 1 from public.likes l
                                            where l.entity_type = h.rt and l.entity_id = h.rid
                                              and l.user_id = me),
               'viewer_saved',     exists (select 1 from public.saves s
                                            where s.entity_type = h.rt and s.entity_id = h.rid
                                              and s.user_id = me),
               'viewer_reposted',  exists (select 1 from public.reposts r2
                                            where r2.entity_type = h.rt and r2.entity_id = h.rid
                                              and r2.user_id = me),
               'media',            '[]'::jsonb,
               'target',           public.pulse_target_payload(h.rt, h.rid)
             ) end
             order by h.sort_at desc)
      from page h
  ), '[]'::jsonb);
end;
$$;

comment on function public.pulse_feed(integer, timestamptz, text) is
  'The Pulse stream. p_mode=following (chronological, default) or foryou (ranked). Returns a jsonb array of envelopes; page with p_before = min(sort_at) on screen.';


-- ----------------------------------------------------------------------------
-- 5. Hardening
-- ----------------------------------------------------------------------------

-- media-only posts are legal now; create_post (the sole insert path) enforces
-- body-or-attachment instead — a table CHECK cannot see post_media.
alter table public.posts drop constraint posts_check;

-- posts: create_post is the only path. (0007 already fenced UPDATE; INSERT was
-- still table-wide, so any client could seed like_count etc. — and the web
-- composer inserted directly. That insert 42501s from now on; B5w moves it to
-- rpc('create_post').)
revoke insert on table public.posts from authenticated;

-- counter-column INSERT audit (0007 only fenced UPDATE). Re-grant the
-- user-writable creation surface, excluding: every trigger-maintained counter,
-- hidden_at (moderation), created_at/updated_at/deleted_at/edited_at (defaults
-- & lifecycle), search_tsv (generated), is_featured (staff).
revoke insert on table public.collections from authenticated;
grant insert (id, user_id, template_id, name, slug, description,
              cover_path, cover_blurhash, accent_color, visibility,
              "position", is_pinned)
  on public.collections to authenticated;

revoke insert on table public.subcollections from authenticated;
grant insert (id, user_id, collection_id, name, slug, description,
              cover_path, cover_blurhash, visibility, "position")
  on public.subcollections to authenticated;

revoke insert on table public.items from authenticated;
grant insert (id, user_id, collection_id, subcollection_id, title, description,
              brand, model, year, condition, rarity, acquisition_date,
              acquisition_place, purchase_price, currency, attributes,
              visibility, "position", is_favorite,
              cover_path, cover_blurhash, cover_width, cover_height)
  on public.items to authenticated;

-- comments are written via add_comment (definer — unaffected by grants), but
-- the direct surface stays column-shaped in case a client ever uses it.
-- depth stays server-assigned (add_comment), like the counters.
revoke insert on table public.comments from authenticated;
grant insert (id, entity_type, entity_id, author_id, parent_id, body)
  on public.comments to authenticated;

-- item_media carries no counter columns — no gap, left as-is.


-- ----------------------------------------------------------------------------
-- 6. Grants — 0012/0017 posture. Helpers are internal (no REST surface);
--    the RPC surface mirrors the replaced pulse_feed's ACL
--    (authenticated + service_role, never anon).
-- ----------------------------------------------------------------------------
revoke execute on function public.pulse_post_media(uuid)                              from public, anon, authenticated;
revoke execute on function public.pulse_target_payload(public.entity_type, uuid)      from public, anon, authenticated;
revoke execute on function public.pulse_post_envelope(uuid, uuid)                     from public, anon, authenticated;

revoke execute on function public.create_post(text, public.post_kind, public.entity_type, uuid, jsonb, uuid) from public, anon;
grant  execute on function public.create_post(text, public.post_kind, public.entity_type, uuid, jsonb, uuid) to authenticated, service_role;

revoke execute on function public.pulse_feed(integer, timestamptz, text) from public, anon;
grant  execute on function public.pulse_feed(integer, timestamptz, text) to authenticated, service_role;
