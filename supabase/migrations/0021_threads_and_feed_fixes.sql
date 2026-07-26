-- ============================================================================
-- 0021_threads_and_feed_fixes.sql — thread-first Pulse backend
--
-- Implements docs/ROUND3_PLAN.md C0 items 1–5.
--
--   1. Comments become full social citizens: `save_count` + `repost_count`
--      columns (backfilled from live saves/reposts rows), the polymorphic
--      counter trigger (`bump_entity_counter`) and the `entity_counter`
--      reader gain the comment branches, and `pulse_target_payload`'s
--      comment branch gains the parent-entity pointer — which together fix
--      the 0018 following-branch feed-poisoning risk for
--      `entity_type='comment'` repost rows (their envelope called
--      `entity_counter('comment', …, 'save_count')` against columns that
--      did not exist).
--   2. `get_post_thread(p_post, p_limit, p_before, p_sort)` — the X thread
--      payload: post envelope + stats + paged comments with batched viewer
--      like/save/repost state (LEFT JOINs, no N+1). `create_post` now
--      rejects `p_reply_to` with 'replies_use_comments' (comments are the
--      one discussion primitive; the reply-kind twin is deprecated).
--   3. `user_posts(p_user, p_limit, p_before)` — profile Posts tab: the
--      author's posts/quotes + their entity reposts, pulse-envelope shaped.
--   4. `pulse_feed`: composite keyset cursor `(created_at, id)` via new
--      `p_before_id` (stops the same-timestamp skip), extra-row has_more
--      (see CONTRACT below), For-you candidates now include entity reposts,
--      and a 30d→90d→all-time window fallback ladder when a page comes up
--      short.
--   5. `search_all` gains a `posts` section (tsv + GIN, visibility/blocks
--      respected like the other sections).
--
-- ── PAGINATION CONTRACT (new, additive) ─────────────────────────────────────
-- `pulse_feed` and `user_posts` return UP TO p_limit+1 envelopes. Clients
-- must render the first p_limit and treat `length > p_limit` as has_more —
-- the envelope array shape itself is unchanged (no wrapper object, so the
-- 0018 client parsers keep working; a client that renders all rows and
-- pages by min cursor also stays correct, it just shows one extra row).
-- Every envelope now carries an additive `cursor_id` key (post id for post
-- rows, target entity id for repost rows); page with
-- `p_before = sort_at` and `p_before_id = cursor_id` of the LAST RENDERED
-- row. `get_post_thread` wraps its comments, so it carries an explicit
-- `has_more` bool instead.
--
-- ── RECONSTRUCTION NOTES (0003/0010 bodies are not in this repo) ────────────
-- `bump_entity_counter`, `entity_counter` and `search_all` are replaced with
-- bodies reconstructed from the live-schema mirror (web/src/lib/
-- database.types.ts) + supabase/README.md conventions:
--   · bump_entity_counter covers every (entity_type × counter column) pair
--     that exists as a real column — enumerated from database.types.ts:
--       collections    like/save/repost/comment/view_count
--       subcollections like/save/repost/comment/view_count
--       items          like/save/repost/comment/view_count
--       posts          like/save/repost/comment/view_count
--       comments       like_count + (new) save_count/repost_count
--     Pairs with no column are explicit no-ops (else-branches), never
--     errors. The counter column is taken from TG_ARGV[0] when the trigger
--     passes one, else derived from TG_TABLE_NAME
--     (likes/saves/reposts/entity_views/comments) — so the function is a
--     drop-in under either wiring style. It returns NEW/OLD (not null) so
--     it is also safe if any trigger is BEFORE instead of AFTER.
--   · entity_counter answers the five envelope counters for all five
--     entity types, returns 0 (never an error) for a column a type lacks,
--     and maps comment 'comment_count' → reply_count (the discussion-size
--     analog). Strictly a superset of any plausible prior behaviour.
--   · search_all reproduces the four section shapes both clients parse
--     (verified against web/src/lib/types.ts SearchPerson/SearchCollection/
--     SearchItem/SearchTag and mobile results.dart/profile.dart parsers)
--     and appends `posts`.
--
-- Posture per 0012/0017/0018: SECURITY DEFINER, search_path pinned to '',
-- fully-qualified references, EXECUTE revoked then granted to a named
-- surface. New internal helper `pulse_repost_envelope` is fenced like the
-- other pulse_* helpers (no REST surface).
--
-- Stable snake_case error texts added:
--   replies_use_comments   create_post called with p_reply_to (deprecated)
--   bad_sort               get_post_thread p_sort not top|new
--   post_not_found         get_post_thread target missing/hidden/invisible
--
-- ── STATUS: ✅ APPLIED 2026-07-27 ────────────────────────────────────────────
-- Smoke (all under JWT impersonation as aria, rolled-back DO blocks): thread
-- top/new ordering + viewer.liked + has_more + bad_sort ✓ · user_posts 4
-- envelopes w/ cursor_id ✓ · pulse_feed p_limit+1 extra-row + same-timestamp
-- twin recovered via (p_before, p_before_id) ✓ · foryou 6 rows off the 90d
-- ladder rung ✓ · comment toggle_save/toggle_repost {active:true,count:1} +
-- column bumps ✓ · create_post(p_reply_to) → replies_use_comments ✓ ·
-- search_all posts section (7 rows) + anon loses a privatized account ✓ ·
-- advisors 0 ERROR, +4 accepted definer-executable WARNs (get_post_thread/
-- user_posts × anon+authenticated); pulse_feed never anon-executable and
-- pulse_repost_envelope fully fenced ✓
--
-- PREFLIGHT (verify live BEFORE applying — the whole file is one
-- transaction, so a mismatch aborts cleanly):
--   P1. `select count(*) from public.posts where kind = 'reply'` must be 0
--       (the create_post guard assumes the reply twin is dead).
--   P2. `select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n
--        on n.oid = p.pronamespace where n.nspname='public' and
--        p.proname='entity_counter'` — confirm the args are exactly
--       (p_type public.entity_type, p_id uuid, p_col text) RETURNS integer.
--       CREATE OR REPLACE cannot rename params or change the return type
--       (42P13); if they differ, edit §3 to match the live names, or DROP
--       and recreate restoring the live ACL.
--   P3. Same check for search_all — expected (p_q text, p_limit integer)
--       RETURNS jsonb.
--   P4. Confirm `bump_entity_counter` is the trigger function attached to
--       likes/saves/reposts/entity_views (`select tgname, tgrelid::regclass,
--        pg_get_triggerdef(oid) from pg_trigger where tgfoid =
--        'public.bump_entity_counter'::regproc`) and diff the live body
--       against §2 — §2 handles both TG_ARGV and table-name wiring, but eyes
--       on the live source is the real no-dropped-branch guarantee.
--   P5. Diff live search_all body against §9 for any section key this
--       reconstruction missed.
--
-- APPLY: MCP apply_migration as version 0021_threads_and_feed_fixes.
--
-- SMOKE (JWT impersonation as aria/kenji, roll back writes):
--   S1. toggle_save('comment', <id>) / toggle_repost('comment', <id>) →
--       {active:true, count:1}; comments row shows save_count/repost_count=1.
--   S2. As kenji: repost one of aria's comments; as a kenji-follower load
--       pulse_feed('following') → the repost row renders with
--       target.body/author/parent_type/parent_id, counts non-error.
--   S3. get_post_thread on a seeded post: 'top' orders by like_count desc,
--       'new' by created_at desc; viewer.liked true for a liked comment;
--       has_more flips when p_limit < comment count; p_sort='x' → bad_sort.
--   S4. user_posts(aria) → her posts/quotes + entity reposts, envelope keys
--       identical to pulse_feed entries (plus cursor_id).
--   S5. Composite cursor: create two posts with identical created_at
--       (insert as owner in the smoke tx), page with p_limit=1 — second page
--       (p_before = created_at, p_before_id = cursor_id) returns the twin
--       instead of skipping it.
--   S6. pulse_feed p_limit=3 returns ≤4 rows (extra-row contract);
--       'foryou' returns rows even when nothing is <30d old (ladder).
--   S7. create_post(p_reply_to => <any uuid>) → 'replies_use_comments'.
--   S8. search_all('<seeded post word>') → posts section with
--       id/body/author/created_at/counts; private content stays absent.
--   S9. get_advisors: 0 ERROR (new WARNs only in the accepted
--       definer-executable class).
--
-- AFTER APPLY: regenerate web/src/lib/database.types.ts, update
-- BACKEND_API.md §2, flip this header + the supabase/README.md 0021 row to
-- applied.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Comments: save_count + repost_count, backfilled
-- ----------------------------------------------------------------------------
alter table public.comments
  add column if not exists save_count   integer not null default 0,
  add column if not exists repost_count integer not null default 0;

comment on column public.comments.save_count is
  'Trigger-maintained. 0021: comments are full social citizens.';
comment on column public.comments.repost_count is
  'Trigger-maintained. 0021: comments are full social citizens.';

-- Backfill from any saves/reposts rows that predate the columns (their
-- trigger bumps hit a missing branch and were lost).
update public.comments c
   set save_count = s.n
  from (select entity_id, count(*)::integer as n
          from public.saves
         where entity_type = 'comment'::public.entity_type
         group by entity_id) s
 where s.entity_id = c.id
   and c.save_count <> s.n;

update public.comments c
   set repost_count = r.n
  from (select entity_id, count(*)::integer as n
          from public.reposts
         where entity_type = 'comment'::public.entity_type
         group by entity_id) r
 where r.entity_id = c.id
   and c.repost_count <> r.n;

-- Column privileges: nothing to do — 0007/0018 turned comments' INSERT and
-- UPDATE grants into explicit column lists, so the new counter columns are
-- unwritable by `authenticated` by construction (SELECT is table-level and
-- picks them up automatically).


-- ----------------------------------------------------------------------------
-- 2. bump_entity_counter — the polymorphic counter trigger, now with the
--    comment save/repost branches. Exhaustive over every counter column that
--    exists (see RECONSTRUCTION NOTES); missing pairs no-op.
-- ----------------------------------------------------------------------------
create or replace function public.bump_entity_counter()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type public.entity_type;
  v_id   uuid;
  v_col  text;
  v_step integer;
begin
  if tg_op = 'INSERT' then
    v_type := new.entity_type;  v_id := new.entity_id;  v_step := 1;
  elsif tg_op = 'DELETE' then
    v_type := old.entity_type;  v_id := old.entity_id;  v_step := -1;
  else
    return null; -- never wired for UPDATE
  end if;

  -- Column from trigger arg when provided, else derived from the source
  -- table — drop-in under either wiring style.
  v_col := coalesce(tg_argv[0],
                    case tg_table_name
                      when 'likes'        then 'like_count'
                      when 'saves'        then 'save_count'
                      when 'reposts'      then 'repost_count'
                      when 'entity_views' then 'view_count'
                      when 'comments'     then 'comment_count'
                    end);

  case v_type
    when 'collection' then
      case v_col
        when 'like_count'    then update public.collections set like_count    = greatest(like_count    + v_step, 0) where id = v_id;
        when 'save_count'    then update public.collections set save_count    = greatest(save_count    + v_step, 0) where id = v_id;
        when 'repost_count'  then update public.collections set repost_count  = greatest(repost_count  + v_step, 0) where id = v_id;
        when 'comment_count' then update public.collections set comment_count = greatest(comment_count + v_step, 0) where id = v_id;
        when 'view_count'    then update public.collections set view_count    = greatest(view_count    + v_step, 0) where id = v_id;
        else null;
      end case;

    when 'subcollection' then
      case v_col
        when 'like_count'    then update public.subcollections set like_count    = greatest(like_count    + v_step, 0) where id = v_id;
        when 'save_count'    then update public.subcollections set save_count    = greatest(save_count    + v_step, 0) where id = v_id;
        when 'repost_count'  then update public.subcollections set repost_count  = greatest(repost_count  + v_step, 0) where id = v_id;
        when 'comment_count' then update public.subcollections set comment_count = greatest(comment_count + v_step, 0) where id = v_id;
        when 'view_count'    then update public.subcollections set view_count    = greatest(view_count    + v_step, 0) where id = v_id;
        else null;
      end case;

    when 'item' then
      case v_col
        when 'like_count'    then update public.items set like_count    = greatest(like_count    + v_step, 0) where id = v_id;
        when 'save_count'    then update public.items set save_count    = greatest(save_count    + v_step, 0) where id = v_id;
        when 'repost_count'  then update public.items set repost_count  = greatest(repost_count  + v_step, 0) where id = v_id;
        when 'comment_count' then update public.items set comment_count = greatest(comment_count + v_step, 0) where id = v_id;
        when 'view_count'    then update public.items set view_count    = greatest(view_count    + v_step, 0) where id = v_id;
        else null;
      end case;

    when 'post' then
      case v_col
        when 'like_count'    then update public.posts set like_count    = greatest(like_count    + v_step, 0) where id = v_id;
        when 'save_count'    then update public.posts set save_count    = greatest(save_count    + v_step, 0) where id = v_id;
        when 'repost_count'  then update public.posts set repost_count  = greatest(repost_count  + v_step, 0) where id = v_id;
        when 'comment_count' then update public.posts set comment_count = greatest(comment_count + v_step, 0) where id = v_id;
        when 'view_count'    then update public.posts set view_count    = greatest(view_count    + v_step, 0) where id = v_id;
        else null;
      end case;

    when 'comment' then
      case v_col
        when 'like_count'    then update public.comments set like_count    = greatest(like_count    + v_step, 0) where id = v_id;
        -- NEW (0021): comments are saveable/repostable citizens
        when 'save_count'    then update public.comments set save_count    = greatest(save_count    + v_step, 0) where id = v_id;
        when 'repost_count'  then update public.comments set repost_count  = greatest(repost_count  + v_step, 0) where id = v_id;
        -- comment_count on a comment is reply_count territory —
        -- bump_comment_counters owns it; view_count has no column. No-op.
        else null;
      end case;
  end case;

  if tg_op = 'INSERT' then return new; else return old; end if;
end;
$$;

comment on function public.bump_entity_counter() is
  'Polymorphic counter trigger for likes/saves/reposts/entity_views (and comment_count where wired). 0021: comment save_count/repost_count branches added; unknown (type, column) pairs no-op.';


-- ----------------------------------------------------------------------------
-- 3. entity_counter — the polymorphic counter reader, comment branch fixed.
--    ⚠ CORF assumes live args (p_type, p_id, p_col) returns integer — see
--    PREFLIGHT P2.
-- ----------------------------------------------------------------------------
create or replace function public.entity_counter(
  p_type public.entity_type,
  p_id uuid,
  p_col text
) returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v integer;
begin
  -- null-safe: a plpgsql CASE with no matching arm raises CASE_NOT_FOUND,
  -- which is exactly the feed-poisoning failure mode this migration removes.
  if p_type is null or p_id is null then
    return 0;
  end if;

  case p_type
    when 'collection' then
      select case p_col
               when 'like_count'          then c.like_count
               when 'save_count'          then c.save_count
               when 'repost_count'        then c.repost_count
               when 'comment_count'       then c.comment_count
               when 'view_count'          then c.view_count
               when 'item_count'          then c.item_count
               when 'subcollection_count' then c.subcollection_count
               else 0 end
        into v from public.collections c where c.id = p_id;

    when 'subcollection' then
      select case p_col
               when 'like_count'    then s.like_count
               when 'save_count'    then s.save_count
               when 'repost_count'  then s.repost_count
               when 'comment_count' then s.comment_count
               when 'view_count'    then s.view_count
               when 'item_count'    then s.item_count
               else 0 end
        into v from public.subcollections s where s.id = p_id;

    when 'item' then
      select case p_col
               when 'like_count'    then i.like_count
               when 'save_count'    then i.save_count
               when 'repost_count'  then i.repost_count
               when 'comment_count' then i.comment_count
               when 'view_count'    then i.view_count
               when 'media_count'   then i.media_count
               else 0 end
        into v from public.items i where i.id = p_id;

    when 'post' then
      select case p_col
               when 'like_count'    then p.like_count
               when 'save_count'    then p.save_count
               when 'repost_count'  then p.repost_count
               when 'comment_count' then p.comment_count
               when 'view_count'    then p.view_count
               when 'reply_count'   then p.reply_count
               else 0 end
        into v from public.posts p where p.id = p_id;

    when 'comment' then
      select case p_col
               when 'like_count'    then cm.like_count
               when 'save_count'    then cm.save_count    -- NEW (0021)
               when 'repost_count'  then cm.repost_count  -- NEW (0021)
               when 'comment_count' then cm.reply_count   -- discussion-size analog
               when 'reply_count'   then cm.reply_count
               else 0 end                                 -- view_count: no column → 0
        into v from public.comments cm where cm.id = p_id;
  end case;

  return coalesce(v, 0);
end;
$$;

comment on function public.entity_counter(public.entity_type, uuid, text) is
  'Polymorphic counter reader. 0021: comment save/repost branches added; unknown (type, column) pairs return 0, never error.';


-- ----------------------------------------------------------------------------
-- 4. pulse_target_payload — comment branch gains the parent-entity pointer
--    (additive keys; every other branch byte-identical to 0018).
-- ----------------------------------------------------------------------------
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
      -- 0021: + parent_type/parent_id so a reposted comment can deep-link to
      -- the discussion it lives under.
      select jsonb_build_object(
               'type', 'comment', 'id', cm.id, 'unavailable', false,
               'title', null, 'subtitle', null, 'body', cm.body,
               'cover_path', null, 'cover_blurhash', null,
               'cover_width', null, 'cover_height', null,
               'child_count', cm.reply_count, 'like_count', cm.like_count,
               'created_at', cm.created_at,
               'parent_type', cm.entity_type::text,
               'parent_id', cm.entity_id,
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
  'Internal: embedded preview of a post''s attached/quoted target for the pulse envelope. Not REST-callable. 0021: comment branch carries parent_type/parent_id.';


-- ----------------------------------------------------------------------------
-- 5. pulse_post_envelope — byte-identical to 0018 plus the additive
--    `cursor_id` key (composite-keyset contract).
-- ----------------------------------------------------------------------------
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
           'cursor_id',        p.id,
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
  'Internal: one post as a pulse-stream entry (the envelope contract). Not REST-callable. 0021: + cursor_id.';


-- ----------------------------------------------------------------------------
-- 6. pulse_repost_envelope — NEW internal helper. The 0018 following-branch
--    repost object, factored out so pulse_feed (both modes) and user_posts
--    emit the identical shape. Safe for entity_type='comment' now that
--    entity_counter/pulse_target_payload handle it.
-- ----------------------------------------------------------------------------
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
                                        where l.entity_type = p_type and l.entity_id = p_id
                                          and l.user_id = p_viewer),
           'viewer_saved',     exists (select 1 from public.saves s
                                        where s.entity_type = p_type and s.entity_id = p_id
                                          and s.user_id = p_viewer),
           'viewer_reposted',  exists (select 1 from public.reposts r2
                                        where r2.entity_type = p_type and r2.entity_id = p_id
                                          and r2.user_id = p_viewer),
           'media',            '[]'::jsonb,
           'target',           public.pulse_target_payload(p_type, p_id)
         );
$$;

comment on function public.pulse_repost_envelope(public.entity_type, uuid, uuid, text, timestamptz, uuid) is
  'Internal: one repost row as a pulse-stream entry (0018 shape + cursor_id). Not REST-callable.';


-- ----------------------------------------------------------------------------
-- 7. create_post — p_reply_to is rejected: comments are the one discussion
--    primitive. Everything else byte-equivalent to 0018 (signature unchanged
--    for contract stability; ACL preserved by CORF).
--    PREFLIGHT P1 must confirm zero kind='reply' posts exist live.
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
  v_me          uuid := public.require_auth();
  v_body        text := nullif(trim(coalesce(p_body, '')), '');
  v_kind        public.post_kind;
  v_post        uuid;
  v_media_count integer := 0;
  v_path        text;
  m             record;
begin
  -- replies are dead: the discussion primitive is comments (get_post_thread)
  if p_reply_to is not null then
    raise exception 'replies_use_comments';
  end if;

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

  -- kind is derived; p_kind is accepted for contract stability ----------------
  v_kind := case
              when p_entity_type = 'post'::public.entity_type then 'quote'::public.post_kind
              else 'post'::public.post_kind
            end;

  insert into public.posts (author_id, kind, body, entity_type, entity_id)
  values (v_me, v_kind, v_body, p_entity_type, p_entity_id)
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

  -- notifications: quotes notify like a repost would (notify() drops self
  -- and blocked pairs itself). The reply branch is gone with p_reply_to.
  if v_kind = 'quote'::public.post_kind then
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
  'Create a post/quote (the only insert path for posts). 0021: p_reply_to raises replies_use_comments — discussion lives in comments/get_post_thread. Returns the post''s pulse envelope.';


-- ----------------------------------------------------------------------------
-- 8. pulse_feed — composite keyset cursor + extra-row has_more + For-you
--    entity reposts + window ladder.
--    (the 3-arg signature must be dropped or PostgREST sees two overloads)
-- ----------------------------------------------------------------------------
drop function if exists public.pulse_feed(integer, timestamptz, text);

create function public.pulse_feed(
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
  me        uuid       := auth.uid();
  v_limit   integer    := greatest(1, least(coalesce(p_limit, 25), 50));
  v_take    integer;
  v_windows interval[] := array[interval '30 days', interval '90 days', null::interval];
  v_win     interval;
  v_out     jsonb      := '[]'::jsonb;
begin
  v_take := v_limit + 1; -- extra-row has_more contract (see header)

  if p_mode not in ('following', 'foryou') then
    raise exception 'bad_mode';
  end if;

  if p_mode = 'foryou' then
    -- Ranked discovery over posts + entity reposts: engagement with
    -- time-decay + freshness + viewer tag-taste + cached author-match +
    -- follow bonus, ≤3 rows per actor. Window widens 30d→90d→all-time until
    -- a full page (v_take rows) exists. Foryou pages are score-ordered;
    -- clients keep paging with min(sort_at)/its cursor_id on screen.
    foreach v_win in array v_windows loop
      v_out := coalesce((
        with post_c as (
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
             and (p_before is null
                  or (p_before_id is null and p.created_at < p_before)
                  or (p_before_id is not null and (p.created_at, p.id) < (p_before, p_before_id)))
             and (v_win is null or p.created_at > now() - v_win)
           order by p.created_at desc
           limit 600
        ),
        repost_c as (
          -- 0021: entity reposts circulate in discovery (seeded/legacy
          -- activity). Reposter gated like a post author; target via the
          -- visibility oracle.
          select r.user_id as reposter_id, r.entity_type, r.entity_id,
                 r.quote_text, r.created_at
            from public.reposts r
            join public.profiles pr on pr.id = r.user_id
           where pr.is_suspended = false
             and (
                   r.user_id = me
                or pr.account_visibility = 'public'::public.visibility
                or exists (select 1 from public.follows f
                            where f.follower_id = me and f.following_id = r.user_id)
                 )
             and not exists (select 1 from public.blocks b
                              where (b.blocker_id = me and b.blocked_id = r.user_id)
                                 or (b.blocker_id = r.user_id and b.blocked_id = me))
             and not exists (select 1 from public.mutes mu
                              where mu.muter_id = me and mu.muted_id = r.user_id)
             and (p_before is null
                  or (p_before_id is null and r.created_at < p_before)
                  or (p_before_id is not null and (r.created_at, r.entity_id) < (p_before, p_before_id)))
             and (v_win is null or r.created_at > now() - v_win)
             and public.can_view_entity(r.entity_type, r.entity_id)
           order by r.created_at desc
           limit 200
        ),
        affinity as (
          -- surf_feed's taste idiom: the viewer's tag weights over tagged entities
          select et.entity_type as a_type, et.entity_id as a_id, sum(ut.weight)::real as aff
            from public.entity_tags et
            join public.user_taste ut on ut.tag_id = et.tag_id and ut.user_id = me
           group by et.entity_type, et.entity_id
        ),
        scored_posts as (
          select 'post'::text              as fk,
                 c.id                      as cid,
                 c.author_id               as actor,
                 null::public.entity_type  as r_type,
                 null::uuid                as r_id,
                 null::uuid                as r_user,
                 null::text                as r_quote,
                 c.created_at,
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
            from post_c c
            left join affinity ap on ap.a_type = 'post'::public.entity_type and ap.a_id = c.id
            left join affinity ae on ae.a_type = c.entity_type and ae.a_id = c.entity_id
            left join public.user_matches um on um.user_id = me and um.other_id = c.author_id
        ),
        scored_reposts as (
          -- target engagement (like/save via entity_counter — bounded by the
          -- 200-row candidate cap) + repost freshness + taste + reposter match
          select 'repost'::text as fk,
                 rc.entity_id   as cid,
                 rc.reposter_id as actor,
                 rc.entity_type as r_type,
                 rc.entity_id   as r_id,
                 rc.reposter_id as r_user,
                 rc.quote_text  as r_quote,
                 rc.created_at,
                 ( ln(1 + public.entity_counter(rc.entity_type, rc.entity_id, 'like_count') * 3
                        + public.entity_counter(rc.entity_type, rc.entity_id, 'save_count') * 5) * 0.6
                     / (1 + extract(epoch from (now() - rc.created_at)) / 172800.0)
                   + 3.0 / (1 + extract(epoch from (now() - rc.created_at)) / 86400.0)
                   + coalesce(ae.aff, 0) * 0.35
                   + coalesce(um.score, 0) * 0.8
                   + case when exists (select 1 from public.follows f
                                        where f.follower_id = me and f.following_id = rc.reposter_id)
                          then 0.6 else 0 end
                   + case when rc.reposter_id = me then -1.2 else 0 end
                 )::real as score
            from repost_c rc
            left join affinity ae on ae.a_type = rc.entity_type and ae.a_id = rc.entity_id
            left join public.user_matches um on um.user_id = me and um.other_id = rc.reposter_id
        ),
        capped as (
          select s.*,
                 row_number() over (partition by s.actor order by s.score desc) as arn
            from (select * from scored_posts union all select * from scored_reposts) s
        ),
        page as (
          select *
            from capped
           where arn <= 3
           order by score desc, created_at desc, cid desc
           limit v_take
        )
        select jsonb_agg(
                 case when page.fk = 'post'
                      then public.pulse_post_envelope(page.cid, me)
                      else public.pulse_repost_envelope(page.r_type, page.r_id, page.r_user,
                                                        page.r_quote, page.created_at, me)
                 end
                 order by page.score desc, page.created_at desc, page.cid desc)
          from page
      ), '[]'::jsonb);

      exit when jsonb_array_length(v_out) > v_limit; -- full page + extra row
    end loop;

    return v_out;
  end if;

  -- following (default): chronological posts + reposts from people you
  -- follow. Semantics preserved from 0018; 0021 adds the composite cursor,
  -- v_take extra-row, deterministic (sort_at, cursor_id) ordering, and the
  -- factored repost envelope (comment reposts now render instead of
  -- poisoning the page).
  return coalesce((
    with heads as (
      (
        select 'post'::text               as fk,
               p.id                       as cid,
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
           and (p_before is null
                or (p_before_id is null and p.created_at < p_before)
                or (p_before_id is not null and (p.created_at, p.id) < (p_before, p_before_id)))
         order by p.created_at desc
         limit v_take
      )
      union all
      (
        select 'repost', r.entity_id, r.entity_type, r.entity_id, r.user_id, r.quote_text, r.created_at
          from public.reposts r
         where r.user_id in (select f.following_id from public.follows f
                              where f.follower_id = me)
           and (p_before is null
                or (p_before_id is null and r.created_at < p_before)
                or (p_before_id is not null and (r.created_at, r.entity_id) < (p_before, p_before_id)))
           and public.can_view_entity(r.entity_type, r.entity_id)
         order by r.created_at desc
         limit v_take
      )
    ),
    page as (
      select * from heads order by sort_at desc, cid desc limit v_take
    )
    select jsonb_agg(
             case when h.fk = 'post'
                  then public.pulse_post_envelope(h.cid, me)
                  else public.pulse_repost_envelope(h.rt, h.rid, h.ruser, h.rquote, h.sort_at, me)
             end
             order by h.sort_at desc, h.cid desc)
      from page h
  ), '[]'::jsonb);
end;
$$;

comment on function public.pulse_feed(integer, timestamptz, text, uuid) is
  'The Pulse stream. p_mode=following (chronological) or foryou (ranked, 30d→90d→all-time ladder, includes entity reposts). Returns up to p_limit+1 envelopes (length>p_limit ⇒ has_more); page with (sort_at, cursor_id) of the last rendered row as (p_before, p_before_id).';


-- ----------------------------------------------------------------------------
-- 9. get_post_thread — the X thread payload
-- ----------------------------------------------------------------------------
create or replace function public.get_post_thread(
  p_post uuid,
  p_limit integer default 30,
  p_before timestamptz default null,
  p_sort text default 'top'
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me      uuid    := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 100));
  v_post  public.posts%rowtype;
begin
  if p_sort not in ('top', 'new') then
    raise exception 'bad_sort';
  end if;

  select * into v_post
    from public.posts p
   where p.id = p_post
     and p.deleted_at is null
     and p.hidden_at is null;

  if not found or not public.can_view_entity('post'::public.entity_type, p_post) then
    raise exception 'post_not_found';
  end if;

  -- Paged flat comment list (parent_id + depth let clients thread it).
  -- 'top' = like_count desc then recency; 'new' = recency. p_before is a
  -- created_at keyset in both modes (for 'top' the client pages with the
  -- min(created_at) on screen; ranking applies within the remaining set).
  -- Viewer state is batched via LEFT JOINs — one query, no N+1.
  return (
    with base as (
      select c.id, c.body, c.author_id, c.created_at, c.like_count,
             c.save_count, c.repost_count, c.reply_count, c.parent_id, c.depth
        from public.comments c
        join public.profiles pr on pr.id = c.author_id
       where c.entity_type = 'post'::public.entity_type
         and c.entity_id = p_post
         and c.deleted_at is null
         and c.hidden_at is null
         and pr.is_suspended = false
         and (me is null or not exists (select 1 from public.blocks b
                where (b.blocker_id = me and b.blocked_id = c.author_id)
                   or (b.blocker_id = c.author_id and b.blocked_id = me)))
         and (p_before is null or c.created_at < p_before)
       order by case when p_sort = 'top' then c.like_count end desc nulls last,
                c.created_at desc, c.id desc
       limit v_limit + 1
    ),
    numbered as (
      select b.*,
             row_number() over (
               order by case when p_sort = 'top' then b.like_count end desc nulls last,
                        b.created_at desc, b.id desc) as rn
        from base b
    ),
    enriched as (
      select n.*,
             (vl.user_id is not null) as v_liked,
             (vs.user_id is not null) as v_saved,
             (vr.user_id is not null) as v_reposted,
             jsonb_build_object(
               'id', pr.id, 'username', pr.username::text,
               'display_name', pr.display_name,
               'avatar_path', pr.avatar_path,
               'is_verified', pr.is_verified) as author
        from numbered n
        join public.profiles pr on pr.id = n.author_id
        left join public.likes vl
               on me is not null and vl.user_id = me
              and vl.entity_type = 'comment'::public.entity_type and vl.entity_id = n.id
        left join public.saves vs
               on me is not null and vs.user_id = me
              and vs.entity_type = 'comment'::public.entity_type and vs.entity_id = n.id
        left join public.reposts vr
               on me is not null and vr.user_id = me
              and vr.entity_type = 'comment'::public.entity_type and vr.entity_id = n.id
    )
    select jsonb_build_object(
             'post',  public.pulse_post_envelope(p_post, me),
             'stats', jsonb_build_object(
                        'like_count',    v_post.like_count,
                        'repost_count',  v_post.repost_count,
                        'save_count',    v_post.save_count,
                        'comment_count', v_post.comment_count,
                        'view_count',    v_post.view_count),
             'comments', coalesce(
               jsonb_agg(jsonb_build_object(
                 'id',           e.id,
                 'body',         e.body,
                 'author',       e.author,
                 'created_at',   e.created_at,
                 'like_count',   e.like_count,
                 'save_count',   e.save_count,
                 'repost_count', e.repost_count,
                 'reply_count',  e.reply_count,
                 'parent_id',    e.parent_id,
                 'depth',        e.depth,
                 'viewer',       jsonb_build_object(
                                   'liked',    e.v_liked,
                                   'saved',    e.v_saved,
                                   'reposted', e.v_reposted)
               ) order by e.rn) filter (where e.rn <= v_limit),
               '[]'::jsonb),
             'has_more', coalesce(max(e.rn), 0) > v_limit
           )
      from enriched e
  );
end;
$$;

comment on function public.get_post_thread(uuid, integer, timestamptz, text) is
  'The post thread payload: {post, stats, comments[], has_more}. p_sort=top (like_count desc then recency) | new (recency). Page with p_before = min(created_at) on screen. Errors: bad_sort, post_not_found.';


-- ----------------------------------------------------------------------------
-- 10. user_posts — profile Posts tab: the author's posts/quotes + their
--     entity reposts, pulse-envelope shaped. Same extra-row has_more
--     contract as pulse_feed. Returns jsonb (an array) exactly like
--     pulse_feed so both clients reuse one parser.
-- ----------------------------------------------------------------------------
create or replace function public.user_posts(
  p_user uuid,
  p_limit integer default 25,
  p_before timestamptz default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me      uuid    := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_take  integer;
begin
  v_take := v_limit + 1;

  if p_user is null or not public.can_see_owner(p_user) then
    return '[]'::jsonb;
  end if;

  return coalesce((
    with heads as (
      (
        select 'post'::text             as fk,
               p.id                     as cid,
               null::public.entity_type as rt,
               null::uuid               as rid,
               null::uuid               as ruser,
               null::text               as rquote,
               p.created_at             as sort_at
          from public.posts p
         where p.author_id = p_user
           and p.deleted_at is null
           and p.hidden_at is null
           and p.reply_to_post_id is null
           and (p_before is null or p.created_at < p_before)
           and public.can_view_entity('post'::public.entity_type, p.id)
         order by p.created_at desc
         limit v_take
      )
      union all
      (
        select 'repost', r.entity_id, r.entity_type, r.entity_id, r.user_id, r.quote_text, r.created_at
          from public.reposts r
         where r.user_id = p_user
           and (p_before is null or r.created_at < p_before)
           and public.can_view_entity(r.entity_type, r.entity_id)
         order by r.created_at desc
         limit v_take
      )
    ),
    page as (
      select * from heads order by sort_at desc, cid desc limit v_take
    )
    select jsonb_agg(
             case when h.fk = 'post'
                  then public.pulse_post_envelope(h.cid, me)
                  else public.pulse_repost_envelope(h.rt, h.rid, h.ruser, h.rquote, h.sort_at, me)
             end
             order by h.sort_at desc, h.cid desc)
      from page h
  ), '[]'::jsonb);
end;
$$;

comment on function public.user_posts(uuid, integer, timestamptz) is
  'Profile Posts tab: p_user''s posts/quotes + entity reposts as pulse envelopes. Returns up to p_limit+1 entries (length>p_limit ⇒ has_more); page with p_before = min(sort_at) on screen.';


-- ----------------------------------------------------------------------------
-- 11. posts full-text search: tsv + GIN
--     posts.search_tsv already exists in the live schema (see
--     database.types.ts) — guard both DDL statements so this section is a
--     no-op when 0003 already provisioned them.
-- ----------------------------------------------------------------------------
alter table public.posts
  add column if not exists search_tsv tsvector
    generated always as (to_tsvector('simple', coalesce(body, ''))) stored;

do $$
begin
  if not exists (
    select 1
      from pg_index i
      join pg_class t on t.oid = i.indrelid
      join pg_namespace n on n.oid = t.relnamespace
      join pg_attribute a on a.attrelid = t.oid and a.attnum = any (i.indkey)
     where n.nspname = 'public'
       and t.relname = 'posts'
       and a.attname = 'search_tsv'
  ) then
    create index posts_search_tsv_idx on public.posts using gin (search_tsv);
  end if;
end $$;


-- ----------------------------------------------------------------------------
-- 12. search_all — + posts section. Section shapes reproduce exactly what
--     both clients parse (see RECONSTRUCTION NOTES); text match is
--     tsv-first with an ilike fallback so results are correct regardless of
--     the live tsv config ('simple' vs 'english').
-- ----------------------------------------------------------------------------
create or replace function public.search_all(
  p_q text,
  p_limit integer default 20
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me      uuid    := auth.uid();
  v_q     text    := trim(coalesce(p_q, ''));
  v_like  text;
  v_limit integer := greatest(1, least(coalesce(p_limit, 20), 50));
begin
  if v_q = '' then
    return jsonb_build_object(
      'people', '[]'::jsonb, 'collections', '[]'::jsonb,
      'items', '[]'::jsonb, 'tags', '[]'::jsonb, 'posts', '[]'::jsonb);
  end if;

  v_like := '%' || v_q || '%';

  return jsonb_build_object(
    'people', coalesce((
      select jsonb_agg(x.j)
        from (
          select jsonb_build_object(
                   'id', pr.id, 'username', pr.username::text,
                   'display_name', pr.display_name,
                   'avatar_path', pr.avatar_path,
                   'banner_path', pr.banner_path,
                   'is_verified', pr.is_verified,
                   'bio', pr.bio,
                   'location', pr.location,
                   'follower_count', pr.follower_count,
                   'following_count', pr.following_count,
                   'collection_count', pr.collection_count,
                   'item_count', pr.item_count,
                   'created_at', pr.created_at) as j
            from public.profiles pr
           where pr.is_suspended = false
             -- preflight P5: private accounts must stay unlisted for
             -- non-followers (search_all is definer + anon-callable)
             and public.can_see_owner(pr.id)
             and (me is null or not exists (select 1 from public.blocks b
                    where (b.blocker_id = me and b.blocked_id = pr.id)
                       or (b.blocker_id = pr.id and b.blocked_id = me)))
             and (pr.search_tsv @@ websearch_to_tsquery('simple', v_q)
                  or pr.username::text ilike v_like
                  or pr.display_name ilike v_like)
           order by (pr.username::text ilike (v_q || '%')) desc,
                    pr.follower_count desc, pr.created_at desc
           limit v_limit
        ) x
    ), '[]'::jsonb),

    'collections', coalesce((
      select jsonb_agg(x.j)
        from (
          select jsonb_build_object(
                   'id', c.id, 'name', c.name, 'slug', c.slug,
                   'cover_path', c.cover_path, 'cover_blurhash', c.cover_blurhash,
                   'item_count', c.item_count, 'like_count', c.like_count,
                   'username', pr.username::text,
                   'display_name', pr.display_name,
                   'avatar_path', pr.avatar_path) as j
            from public.collections c
            join public.profiles pr on pr.id = c.user_id
           where c.deleted_at is null
             and c.hidden_at is null
             and (c.search_tsv @@ websearch_to_tsquery('simple', v_q)
                  or c.name ilike v_like)
             and public.can_view_entity('collection'::public.entity_type, c.id)
           order by c.like_count desc, c.created_at desc
           limit v_limit
        ) x
    ), '[]'::jsonb),

    'items', coalesce((
      select jsonb_agg(x.j)
        from (
          select jsonb_build_object(
                   'id', i.id, 'title', i.title, 'brand', i.brand,
                   'cover_path', i.cover_path, 'cover_blurhash', i.cover_blurhash,
                   'cover_width', i.cover_width, 'cover_height', i.cover_height,
                   'like_count', i.like_count,
                   'username', pr.username::text,
                   'display_name', pr.display_name,
                   'avatar_path', pr.avatar_path) as j
            from public.items i
            join public.profiles pr on pr.id = i.user_id
           where i.deleted_at is null
             and i.hidden_at is null
             and (i.search_tsv @@ websearch_to_tsquery('simple', v_q)
                  or i.title ilike v_like)
             and public.can_view_entity('item'::public.entity_type, i.id)
           order by i.like_count desc, i.created_at desc
           limit v_limit
        ) x
    ), '[]'::jsonb),

    'tags', coalesce((
      select jsonb_agg(x.j)
        from (
          select jsonb_build_object(
                   'id', t.id, 'slug', t.slug, 'name', t.name,
                   'use_count', t.use_count) as j
            from public.tags t
           where t.name ilike v_like or t.slug ilike v_like
           order by t.use_count desc, t.name asc
           limit v_limit
        ) x
    ), '[]'::jsonb),

    -- NEW (0021): posts — id, body excerpt, author, created_at, counts.
    'posts', coalesce((
      select jsonb_agg(x.j)
        from (
          select jsonb_build_object(
                   'id', p.id,
                   'body', left(p.body, 280),
                   'kind', p.kind::text,
                   'created_at', p.created_at,
                   'like_count', p.like_count,
                   'save_count', p.save_count,
                   'repost_count', p.repost_count,
                   'comment_count', p.comment_count,
                   'view_count', p.view_count,
                   'author', jsonb_build_object(
                     'id', pr.id, 'username', pr.username::text,
                     'display_name', pr.display_name,
                     'avatar_path', pr.avatar_path,
                     'is_verified', pr.is_verified)) as j
            from public.posts p
            join public.profiles pr on pr.id = p.author_id
           where p.deleted_at is null
             and p.hidden_at is null
             and p.reply_to_post_id is null
             and p.body is not null
             and (p.search_tsv @@ websearch_to_tsquery('simple', v_q)
                  or p.body ilike v_like)
             and public.can_view_entity('post'::public.entity_type, p.id)
           order by p.created_at desc
           limit v_limit
        ) x
    ), '[]'::jsonb)
  );
end;
$$;

comment on function public.search_all(text, integer) is
  'Global search: {people, collections, items, tags, posts}. 0021 adds posts (visibility/blocks respected via can_view_entity like the other sections).';


-- ----------------------------------------------------------------------------
-- 13. Grants — 0012/0018 posture. CORF preserves existing ACLs
--     (create_post, search_all, entity_counter, pulse_post_envelope,
--     pulse_target_payload keep theirs); only genuinely new signatures need
--     explicit fencing.
-- ----------------------------------------------------------------------------

-- internal helper: no REST surface, like the other pulse_* helpers
revoke execute on function public.pulse_repost_envelope(public.entity_type, uuid, uuid, text, timestamptz, uuid) from public, anon, authenticated;

-- pulse_feed (new 4-arg signature): mirrors the dropped 3-arg ACL —
-- authenticated + service_role, never anon
revoke execute on function public.pulse_feed(integer, timestamptz, text, uuid) from public, anon;
grant  execute on function public.pulse_feed(integer, timestamptz, text, uuid) to authenticated, service_role;

-- get_post_thread / user_posts: anon-readable like get_closeup (the web
-- /p/[id] and profile pages are public SEO surfaces; viewer state simply
-- reads false for anon)
revoke execute on function public.get_post_thread(uuid, integer, timestamptz, text) from public;
grant  execute on function public.get_post_thread(uuid, integer, timestamptz, text) to anon, authenticated, service_role;

revoke execute on function public.user_posts(uuid, integer, timestamptz) from public;
grant  execute on function public.user_posts(uuid, integer, timestamptz) to anon, authenticated, service_role;
