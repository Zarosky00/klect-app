-- Pulse engagement and unified profile activity (v1.6.3).
--
-- This migration is additive at the RPC boundary. Existing pulse_feed,
-- user_posts, and thread clients remain supported while mobile and web move to
-- the JSONB cursor contracts below.

begin;

-- ---------------------------------------------------------------------------
-- Quote counters
-- ---------------------------------------------------------------------------

alter table public.collections
  add column if not exists quote_count integer not null default 0;
alter table public.subcollections
  add column if not exists quote_count integer not null default 0;
alter table public.items
  add column if not exists quote_count integer not null default 0;
alter table public.posts
  add column if not exists quote_count integer not null default 0;

alter table public.collections
  drop constraint if exists collections_quote_count_check;
alter table public.collections
  add constraint collections_quote_count_check check (quote_count >= 0);
alter table public.subcollections
  drop constraint if exists subcollections_quote_count_check;
alter table public.subcollections
  add constraint subcollections_quote_count_check check (quote_count >= 0);
alter table public.items
  drop constraint if exists items_quote_count_check;
alter table public.items
  add constraint items_quote_count_check check (quote_count >= 0);
alter table public.posts
  drop constraint if exists posts_quote_count_check;
alter table public.posts
  add constraint posts_quote_count_check check (quote_count >= 0);

alter table public.posts
  drop constraint if exists posts_quote_target_check;
alter table public.posts
  add constraint posts_quote_target_check check (
    kind <> 'quote'::public.post_kind
    or (
      entity_id is not null
      and entity_type in (
        'collection'::public.entity_type,
        'subcollection'::public.entity_type,
        'item'::public.entity_type,
        'post'::public.entity_type
      )
    )
  ) not valid;

-- Existing quotes only targeted posts. Validate after the back-compatible
-- constraint is installed so future direct privileged writes cannot drift.
alter table public.posts validate constraint posts_quote_target_check;

create or replace function public.bump_quote_target(
  p_type public.entity_type,
  p_id uuid,
  p_step integer
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_type is null or p_id is null or p_step = 0 then
    return;
  end if;

  case p_type
    when 'collection' then
      update public.collections
         set quote_count = greatest(quote_count + p_step, 0)
       where id = p_id;
    when 'subcollection' then
      update public.subcollections
         set quote_count = greatest(quote_count + p_step, 0)
       where id = p_id;
    when 'item' then
      update public.items
         set quote_count = greatest(quote_count + p_step, 0)
       where id = p_id;
    when 'post' then
      update public.posts
         set quote_count = greatest(quote_count + p_step, 0)
       where id = p_id;
    else
      null; -- comments are not quoteable
  end case;
end;
$$;

create or replace function public.bump_quote_counters()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old_active boolean := false;
  v_new_active boolean := false;
begin
  if tg_op <> 'INSERT' then
    v_old_active := old.kind = 'quote'::public.post_kind
      and old.entity_type in (
        'collection'::public.entity_type,
        'subcollection'::public.entity_type,
        'item'::public.entity_type,
        'post'::public.entity_type
      )
      and old.entity_id is not null
      and old.deleted_at is null
      and old.hidden_at is null;
  end if;

  if tg_op <> 'DELETE' then
    v_new_active := new.kind = 'quote'::public.post_kind
      and new.entity_type in (
        'collection'::public.entity_type,
        'subcollection'::public.entity_type,
        'item'::public.entity_type,
        'post'::public.entity_type
      )
      and new.entity_id is not null
      and new.deleted_at is null
      and new.hidden_at is null;
  end if;

  if tg_op = 'INSERT' then
    if v_new_active then
      perform public.bump_quote_target(new.entity_type, new.entity_id, 1);
    end if;
  elsif tg_op = 'DELETE' then
    if v_old_active then
      perform public.bump_quote_target(old.entity_type, old.entity_id, -1);
    end if;
  else
    if v_old_active and (
      not v_new_active
      or old.entity_type is distinct from new.entity_type
      or old.entity_id is distinct from new.entity_id
    ) then
      perform public.bump_quote_target(old.entity_type, old.entity_id, -1);
    end if;

    if v_new_active and (
      not v_old_active
      or old.entity_type is distinct from new.entity_type
      or old.entity_id is distinct from new.entity_id
    ) then
      perform public.bump_quote_target(new.entity_type, new.entity_id, 1);
    end if;
  end if;

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

drop trigger if exists posts_quote_count on public.posts;
create trigger posts_quote_count
after insert or delete or update of kind, entity_type, entity_id, deleted_at, hidden_at
on public.posts
for each row execute function public.bump_quote_counters();

-- Reconcile counters from source-of-truth rows. Hidden/deleted quote posts do
-- not count; changing those moderation stamps is covered by the trigger.
update public.collections c
   set quote_count = coalesce(q.n, 0)
  from (
    select target.id, count(p.id)::integer as n
      from public.collections target
      left join public.posts p
        on p.kind = 'quote'::public.post_kind
       and p.entity_type = 'collection'::public.entity_type
       and p.entity_id = target.id
       and p.deleted_at is null
       and p.hidden_at is null
     group by target.id
  ) q
 where c.id = q.id;

update public.subcollections s
   set quote_count = coalesce(q.n, 0)
  from (
    select target.id, count(p.id)::integer as n
      from public.subcollections target
      left join public.posts p
        on p.kind = 'quote'::public.post_kind
       and p.entity_type = 'subcollection'::public.entity_type
       and p.entity_id = target.id
       and p.deleted_at is null
       and p.hidden_at is null
     group by target.id
  ) q
 where s.id = q.id;

update public.items i
   set quote_count = coalesce(q.n, 0)
  from (
    select target.id, count(p.id)::integer as n
      from public.items target
      left join public.posts p
        on p.kind = 'quote'::public.post_kind
       and p.entity_type = 'item'::public.entity_type
       and p.entity_id = target.id
       and p.deleted_at is null
       and p.hidden_at is null
     group by target.id
  ) q
 where i.id = q.id;

update public.posts target
   set quote_count = coalesce(q.n, 0)
  from (
    select target_post.id, count(p.id)::integer as n
      from public.posts target_post
      left join public.posts p
        on p.kind = 'quote'::public.post_kind
       and p.entity_type = 'post'::public.entity_type
       and p.entity_id = target_post.id
       and p.deleted_at is null
       and p.hidden_at is null
     group by target_post.id
  ) q
 where target.id = q.id;

create index if not exists likes_entity_actor_page_idx
  on public.likes (entity_type, entity_id, created_at desc, user_id desc);
create index if not exists reposts_entity_actor_page_idx
  on public.reposts (entity_type, entity_id, created_at desc, user_id desc);
create index if not exists posts_quote_target_page_idx
  on public.posts (entity_type, entity_id, created_at desc, id desc)
  where kind = 'quote'::public.post_kind
    and deleted_at is null and hidden_at is null;
create index if not exists posts_author_activity_page_idx
  on public.posts (author_id, created_at desc, id desc)
  where deleted_at is null and hidden_at is null and reply_to_post_id is null;
create index if not exists comments_author_activity_page_idx
  on public.comments (author_id, created_at desc, id desc)
  where deleted_at is null and hidden_at is null;
create index if not exists likes_user_activity_page_idx
  on public.likes (user_id, created_at desc, entity_type, entity_id);
create index if not exists saves_user_activity_page_idx
  on public.saves (user_id, created_at desc, entity_type, entity_id);

create or replace function public.social_target_active(
  p_type public.entity_type,
  p_id uuid
) returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_active boolean := false;
begin
  if p_type is null or p_id is null
     or not public.can_view_entity(p_type, p_id) then
    return false;
  end if;

  case p_type
    when 'collection' then
      select c.deleted_at is null and c.hidden_at is null
        into v_active from public.collections c where c.id = p_id;
    when 'subcollection' then
      select s.deleted_at is null and s.hidden_at is null
        into v_active from public.subcollections s where s.id = p_id;
    when 'item' then
      select i.deleted_at is null and i.hidden_at is null
        into v_active from public.items i where i.id = p_id;
    when 'post' then
      select p.deleted_at is null and p.hidden_at is null
        into v_active from public.posts p where p.id = p_id;
    when 'comment' then
      select c.deleted_at is null and c.hidden_at is null
        into v_active from public.comments c where c.id = p_id;
  end case;

  return coalesce(v_active, false);
end;
$$;

-- Keep the existing generic counter helper useful to old and new envelopes.
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
  if p_type is null or p_id is null then return 0; end if;

  case p_type
    when 'collection' then
      select case p_col
               when 'like_count' then c.like_count
               when 'save_count' then c.save_count
               when 'repost_count' then c.repost_count
               when 'quote_count' then c.quote_count
               when 'comment_count' then c.comment_count
               when 'view_count' then c.view_count
               when 'item_count' then c.item_count
               when 'subcollection_count' then c.subcollection_count
               else 0 end
        into v from public.collections c where c.id = p_id;
    when 'subcollection' then
      select case p_col
               when 'like_count' then s.like_count
               when 'save_count' then s.save_count
               when 'repost_count' then s.repost_count
               when 'quote_count' then s.quote_count
               when 'comment_count' then s.comment_count
               when 'view_count' then s.view_count
               when 'item_count' then s.item_count
               else 0 end
        into v from public.subcollections s where s.id = p_id;
    when 'item' then
      select case p_col
               when 'like_count' then i.like_count
               when 'save_count' then i.save_count
               when 'repost_count' then i.repost_count
               when 'quote_count' then i.quote_count
               when 'comment_count' then i.comment_count
               when 'view_count' then i.view_count
               when 'media_count' then i.media_count
               else 0 end
        into v from public.items i where i.id = p_id;
    when 'post' then
      select case p_col
               when 'like_count' then p.like_count
               when 'save_count' then p.save_count
               when 'repost_count' then p.repost_count
               when 'quote_count' then p.quote_count
               when 'comment_count' then p.comment_count
               when 'view_count' then p.view_count
               when 'reply_count' then p.reply_count
               else 0 end
        into v from public.posts p where p.id = p_id;
    when 'comment' then
      select case p_col
               when 'like_count' then c.like_count
               when 'save_count' then c.save_count
               when 'repost_count' then c.repost_count
               when 'comment_count' then c.reply_count
               when 'reply_count' then c.reply_count
               else 0 end
        into v from public.comments c where c.id = p_id;
  end case;

  return coalesce(v, 0);
end;
$$;

-- Root target payloads gain the server-maintained quote count. Nested payloads
-- remain compatible and are still complete media/attachment envelopes.
create or replace function public.pulse_target_payload(
  p_type public.entity_type,
  p_id uuid
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when payload is null then null
    when coalesce((payload ->> 'unavailable')::boolean, false)
      then payload || jsonb_build_object('quote_count', 0)
    else payload || jsonb_build_object(
      'quote_count', public.entity_counter(p_type, p_id, 'quote_count')
    )
  end
  from (select public.pulse_target_payload_depth(p_type, p_id, 0) as payload) x;
$$;

create or replace function public.pulse_post_envelope(
  p_post uuid,
  p_viewer uuid
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
           'feed_kind', 'post', 'kind', p.kind::text,
           'post_id', p.id, 'cursor_id', p.id,
           'entity_type', 'post', 'entity_id', p.id,
           'sort_at', p.created_at, 'created_at', p.created_at,
           'actor_id', p.author_id, 'reposter_id', null,
           'quote_text', null, 'body', p.body,
           'target_type', p.entity_type::text, 'target_id', p.entity_id,
           'reply_to_post_id', p.reply_to_post_id,
           'root_post_id', p.root_post_id,
           'like_count', p.like_count, 'save_count', p.save_count,
           'repost_count', p.repost_count, 'quote_count', p.quote_count,
           'comment_count', p.comment_count, 'view_count', p.view_count,
           'reply_count', p.reply_count,
           'author', (select jsonb_build_object(
             'id', pr.id, 'username', pr.username::text,
             'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
             'is_verified', pr.is_verified
           ) from public.profiles pr where pr.id = p.author_id),
           'reposter', null,
           'viewer_liked', exists (
             select 1 from public.likes l
              where l.entity_type = 'post'::public.entity_type
                and l.entity_id = p.id and l.user_id = p_viewer
           ),
           'viewer_saved', exists (
             select 1 from public.saves s
              where s.entity_type = 'post'::public.entity_type
                and s.entity_id = p.id and s.user_id = p_viewer
           ),
           'viewer_reposted', exists (
             select 1 from public.reposts r
              where r.entity_type = 'post'::public.entity_type
                and r.entity_id = p.id and r.user_id = p_viewer
           ),
           'media', public.pulse_post_media(p.id),
           'target', public.pulse_target_payload(p.entity_type, p.entity_id)
         )
    from public.posts p
   where p.id = p_post;
$$;

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
           'feed_kind', 'repost', 'kind', null,
           'post_id', null, 'cursor_id', p_id,
           'entity_type', p_type::text, 'entity_id', p_id,
           'sort_at', p_at, 'created_at', p_at,
           'actor_id', public.entity_owner(p_type, p_id),
           'reposter_id', p_reposter, 'quote_text', p_quote,
           'body', null, 'target_type', p_type::text, 'target_id', p_id,
           'reply_to_post_id', null, 'root_post_id', null,
           'like_count', public.entity_counter(p_type, p_id, 'like_count'),
           'save_count', public.entity_counter(p_type, p_id, 'save_count'),
           'repost_count', public.entity_counter(p_type, p_id, 'repost_count'),
           'quote_count', public.entity_counter(p_type, p_id, 'quote_count'),
           'comment_count', public.entity_counter(p_type, p_id, 'comment_count'),
           'view_count', public.entity_counter(p_type, p_id, 'view_count'),
           'reply_count', 0,
           'author', (select jsonb_build_object(
             'id', pr.id, 'username', pr.username::text,
             'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
             'is_verified', pr.is_verified
           ) from public.profiles pr
             where pr.id = public.entity_owner(p_type, p_id)),
           'reposter', (select jsonb_build_object(
             'id', pr.id, 'username', pr.username::text,
             'display_name', pr.display_name, 'avatar_path', pr.avatar_path,
             'is_verified', pr.is_verified
           ) from public.profiles pr where pr.id = p_reposter),
           'viewer_liked', exists (
             select 1 from public.likes l where l.entity_type = p_type
               and l.entity_id = p_id and l.user_id = p_viewer
           ),
           'viewer_saved', exists (
             select 1 from public.saves s where s.entity_type = p_type
               and s.entity_id = p_id and s.user_id = p_viewer
           ),
           'viewer_reposted', exists (
             select 1 from public.reposts r where r.entity_type = p_type
               and r.entity_id = p_id and r.user_id = p_viewer
           ),
           'media', public.pulse_entity_media(p_type, p_id),
           'target', public.pulse_target_payload(p_type, p_id)
         );
$$;

-- ---------------------------------------------------------------------------
-- Explicit post versus quote intent
-- ---------------------------------------------------------------------------

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
  v_me uuid := public.require_auth();
  v_body text := nullif(trim(coalesce(p_body, '')), '');
  v_kind public.post_kind;
  v_post uuid;
  v_media_count integer := 0;
  v_path text;
  m record;
begin
  if p_reply_to is not null then
    raise exception 'replies_use_comments';
  end if;

  v_kind := coalesce(p_kind, 'post'::public.post_kind);
  if v_kind not in ('post'::public.post_kind, 'quote'::public.post_kind) then
    raise exception 'bad_kind';
  end if;

  if v_body is not null and char_length(v_body) > 2000 then
    raise exception 'body_too_long';
  end if;

  if p_media is not null then
    if jsonb_typeof(p_media) <> 'array' then raise exception 'bad_media'; end if;
    v_media_count := jsonb_array_length(p_media);
    if v_media_count > 4 then raise exception 'too_many_media'; end if;
  end if;

  if v_body is null and p_entity_id is null and v_media_count = 0 then
    raise exception 'body_or_attachment_required';
  end if;

  if (p_entity_id is null) <> (p_entity_type is null) then
    raise exception 'bad_target';
  end if;

  if v_kind = 'quote'::public.post_kind then
    if p_entity_type not in (
      'collection'::public.entity_type,
      'subcollection'::public.entity_type,
      'item'::public.entity_type,
      'post'::public.entity_type
    ) or p_entity_id is null then
      raise exception 'quote_target_required';
    end if;
  end if;

  if p_entity_id is not null then
    if not public.can_view_entity(p_entity_type, p_entity_id) then
      raise exception 'entity_not_found';
    end if;
    if public.blocked_with(public.entity_owner(p_entity_type, p_entity_id)) then
      raise exception 'blocked';
    end if;
  end if;

  insert into public.posts (author_id, kind, body, entity_type, entity_id)
  values (v_me, v_kind, v_body, p_entity_type, p_entity_id)
  returning id into v_post;

  if v_media_count > 0 then
    for m in
      select value as d, ordinality as ord
        from jsonb_array_elements(p_media) with ordinality
    loop
      if jsonb_typeof(m.d) <> 'object' then raise exception 'bad_media'; end if;
      v_path := m.d ->> 'storage_path';
      if v_path is null or trim(v_path) = '' then raise exception 'bad_media'; end if;
      if split_part(v_path, '/', 1) <> v_me::text then
        raise exception 'media_not_yours';
      end if;
      if (m.d ? 'width' and jsonb_typeof(m.d -> 'width') not in ('number', 'null'))
      or (m.d ? 'height' and jsonb_typeof(m.d -> 'height') not in ('number', 'null'))
      or (m.d ? 'bytes' and jsonb_typeof(m.d -> 'bytes') not in ('number', 'null'))
      or (m.d ? 'position' and jsonb_typeof(m.d -> 'position') not in ('number', 'null')) then
        raise exception 'bad_media';
      end if;

      insert into public.post_media (
        post_id, user_id, storage_path, alt_text, width, height, blurhash,
        dominant_color, mime_type, bytes, "position"
      ) values (
        v_post, v_me, v_path, nullif(m.d ->> 'alt_text', ''),
        (m.d ->> 'width')::integer, (m.d ->> 'height')::integer,
        nullif(m.d ->> 'blurhash', ''),
        nullif(m.d ->> 'dominant_color', ''),
        nullif(m.d ->> 'mime_type', ''), (m.d ->> 'bytes')::bigint,
        coalesce((m.d ->> 'position')::smallint, (m.ord - 1)::smallint)
      );
    end loop;
  end if;

  if v_kind = 'quote'::public.post_kind then
    perform public.notify(
      public.entity_owner(p_entity_type, p_entity_id), v_me,
      'repost'::public.notification_type, p_entity_type, p_entity_id,
      null, null, null, null,
      nullif(left(coalesce(v_body, ''), 140), '')
    );
  end if;

  return public.pulse_post_envelope(v_post, v_me);
end;
$$;

comment on function public.create_post(
  text, public.post_kind, public.entity_type, uuid, jsonb, uuid
) is
  'Creates a regular Pulse post or an explicit quote of a visible collection, subcollection, item, or post. Replies remain comments.';

-- ---------------------------------------------------------------------------
-- Canonical Pulse feed page
-- ---------------------------------------------------------------------------

create or replace function public.pulse_feed_v2(
  p_mode text default 'following',
  p_limit integer default 25,
  p_cursor jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_anchor timestamptz := coalesce(
    nullif(p_cursor ->> 'anchor_at', '')::timestamptz,
    statement_timestamp()
  );
  v_cursor_score_key bigint := nullif(p_cursor ->> 'score_key', '')::bigint;
  v_cursor_at timestamptz := nullif(p_cursor ->> 'sort_at', '')::timestamptz;
  v_cursor_kind integer := nullif(p_cursor ->> 'kind_rank', '')::integer;
  v_cursor_id uuid := nullif(p_cursor ->> 'primary_id', '')::uuid;
  v_cursor_actor uuid := nullif(p_cursor ->> 'actor_id', '')::uuid;
begin
  if p_mode not in ('following', 'foryou') then raise exception 'bad_mode'; end if;

  if p_cursor is not null and (
    v_cursor_at is null or v_cursor_kind is null
    or v_cursor_id is null or v_cursor_actor is null
    or (p_mode = 'foryou' and v_cursor_score_key is null)
  ) then
    raise exception 'bad_cursor';
  end if;

  if p_mode = 'following' then
    return (
      with candidates as (
        select 'post'::text as feed_kind, 1 as kind_rank,
               p.id as primary_id, p.author_id as actor_id,
               p.id as post_id, null::public.entity_type as repost_type,
               null::uuid as repost_id, null::text as quote_text,
               p.created_at as sort_at
          from public.posts p
          join public.profiles actor on actor.id = p.author_id
         where p.created_at <= v_anchor
           and p.deleted_at is null and p.hidden_at is null
           and p.reply_to_post_id is null and actor.is_suspended = false
           and (p.author_id = me or exists (
             select 1 from public.follows f
              where f.follower_id = me and f.following_id = p.author_id
           ))
           and public.can_view_entity('post'::public.entity_type, p.id)
           and not exists (select 1 from public.blocks b
             where (b.blocker_id = me and b.blocked_id = p.author_id)
                or (b.blocker_id = p.author_id and b.blocked_id = me))
           and not exists (select 1 from public.mutes m
             where m.muter_id = me and m.muted_id = p.author_id)
        union all
        select 'repost', 0, r.entity_id, r.user_id, null::uuid,
               r.entity_type, r.entity_id, r.quote_text, r.created_at
          from public.reposts r
          join public.profiles actor on actor.id = r.user_id
         where r.created_at <= v_anchor and actor.is_suspended = false
           and (r.user_id = me or exists (
             select 1 from public.follows f
              where f.follower_id = me and f.following_id = r.user_id
           ))
           and public.social_target_active(r.entity_type, r.entity_id)
           and not exists (select 1 from public.blocks b
             where (b.blocker_id = me and b.blocked_id = r.user_id)
                or (b.blocker_id = r.user_id and b.blocked_id = me))
           and not exists (select 1 from public.mutes m
             where m.muter_id = me and m.muted_id = r.user_id)
      ), filtered as (
        select c.* from candidates c
         where p_cursor is null
            or (c.sort_at, c.kind_rank, c.primary_id, c.actor_id)
               < (v_cursor_at, v_cursor_kind, v_cursor_id, v_cursor_actor)
      ), numbered as (
        select f.*, row_number() over (
          order by f.sort_at desc, f.kind_rank desc,
                   f.primary_id desc, f.actor_id desc
        ) as rn
        from filtered f
        order by f.sort_at desc, f.kind_rank desc,
                 f.primary_id desc, f.actor_id desc
        limit v_limit + 1
      ), page as (
        select * from numbered where rn <= v_limit
      ), last_row as (
        select * from page order by rn desc limit 1
      )
      select jsonb_build_object(
        'items', coalesce((select jsonb_agg(
          (case when p.feed_kind = 'post'
            then public.pulse_post_envelope(p.post_id, me)
            else public.pulse_repost_envelope(
              p.repost_type, p.repost_id, p.actor_id,
              p.quote_text, p.sort_at, me
            ) end) || jsonb_build_object(
              'cursor', jsonb_build_object(
                'anchor_at', v_anchor, 'score', null,
                'sort_at', p.sort_at, 'kind_rank', p.kind_rank,
                'primary_id', p.primary_id, 'actor_id', p.actor_id
              )
            ) order by p.rn
        ) from page p), '[]'::jsonb),
        'has_more', exists(select 1 from numbered where rn > v_limit),
        'next_cursor', (select jsonb_build_object(
          'anchor_at', v_anchor, 'score', null,
          'sort_at', l.sort_at, 'kind_rank', l.kind_rank,
          'primary_id', l.primary_id, 'actor_id', l.actor_id
        ) from last_row l)
      )
    );
  end if;

  return (
    with raw_candidates as (
      select 'post'::text as feed_kind, 1 as kind_rank,
             p.id as primary_id, p.author_id as actor_id,
             p.id as post_id, null::public.entity_type as repost_type,
             null::uuid as repost_id, null::text as quote_text,
             p.created_at as sort_at,
             (
               ln(1 + p.like_count * 3 + p.save_count * 5
                    + p.repost_count * 4 + p.quote_count * 4
                    + p.comment_count * 2 + p.view_count * 0.2) * 0.9
               / (1 + extract(epoch from (v_anchor - p.created_at)) / 172800.0)
               + 3.0 / (1 + extract(epoch from (v_anchor - p.created_at)) / 86400.0)
               + case when exists (select 1 from public.follows f
                   where f.follower_id = me and f.following_id = p.author_id)
                 then 0.6 else 0 end
               + case when p.author_id = me then -1.2 else 0 end
             )::double precision as score
        from public.posts p
        join public.profiles actor on actor.id = p.author_id
       where p.created_at <= v_anchor
         and p.deleted_at is null and p.hidden_at is null
         and p.reply_to_post_id is null and actor.is_suspended = false
         and public.can_view_entity('post'::public.entity_type, p.id)
         and not exists (select 1 from public.blocks b
           where (b.blocker_id = me and b.blocked_id = p.author_id)
              or (b.blocker_id = p.author_id and b.blocked_id = me))
         and not exists (select 1 from public.mutes m
           where m.muter_id = me and m.muted_id = p.author_id)
      union all
      select 'repost', 0, r.entity_id, r.user_id, null::uuid,
             r.entity_type, r.entity_id, r.quote_text, r.created_at,
             (
               ln(1 + public.entity_counter(r.entity_type, r.entity_id, 'like_count') * 3
                    + public.entity_counter(r.entity_type, r.entity_id, 'save_count') * 5
                    + public.entity_counter(r.entity_type, r.entity_id, 'repost_count') * 4
                    + public.entity_counter(r.entity_type, r.entity_id, 'quote_count') * 4
                    + public.entity_counter(r.entity_type, r.entity_id, 'comment_count') * 2
                    + public.entity_counter(r.entity_type, r.entity_id, 'view_count') * 0.2) * 0.65
               / (1 + extract(epoch from (v_anchor - r.created_at)) / 172800.0)
               + 2.4 / (1 + extract(epoch from (v_anchor - r.created_at)) / 86400.0)
               + case when exists (select 1 from public.follows f
                   where f.follower_id = me and f.following_id = r.user_id)
                 then 0.6 else 0 end
               + case when r.user_id = me then -1.2 else 0 end
             )::double precision
        from public.reposts r
        join public.profiles actor on actor.id = r.user_id
       where r.created_at <= v_anchor and actor.is_suspended = false
         and public.can_see_owner(r.user_id)
         and public.social_target_active(r.entity_type, r.entity_id)
         and not exists (select 1 from public.blocks b
           where (b.blocker_id = me and b.blocked_id = r.user_id)
              or (b.blocker_id = r.user_id and b.blocked_id = me))
         and not exists (select 1 from public.mutes m
           where m.muter_id = me and m.muted_id = r.user_id)
    ), keyed as (
      -- JSON clients can round-trip float8 scores by a last bit differently.
      -- Rank and page on a fixed-point key; retain the full score for display
      -- and diagnostics only.
      select r.*,
             round((r.score::numeric) * 1000000000)::bigint as score_key
        from raw_candidates r
    ), diverse as (
      select r.*, row_number() over (
        partition by r.actor_id
        order by r.score_key desc, r.sort_at desc, r.kind_rank desc,
                 r.primary_id desc, r.actor_id desc
      ) as actor_rank
      from keyed r
    ), filtered as (
      select d.* from diverse d
       where d.actor_rank <= 3 and (
         p_cursor is null
         or (d.score_key, d.sort_at, d.kind_rank, d.primary_id, d.actor_id)
            < (v_cursor_score_key, v_cursor_at, v_cursor_kind,
               v_cursor_id, v_cursor_actor)
       )
    ), numbered as (
      select f.*, row_number() over (
        order by f.score_key desc, f.sort_at desc, f.kind_rank desc,
                 f.primary_id desc, f.actor_id desc
      ) as rn
      from filtered f
      order by f.score_key desc, f.sort_at desc, f.kind_rank desc,
               f.primary_id desc, f.actor_id desc
      limit v_limit + 1
    ), page as (
      select * from numbered where rn <= v_limit
    ), last_row as (
      select * from page order by rn desc limit 1
    )
    select jsonb_build_object(
      'items', coalesce((select jsonb_agg(
        (case when p.feed_kind = 'post'
          then public.pulse_post_envelope(p.post_id, me)
          else public.pulse_repost_envelope(
            p.repost_type, p.repost_id, p.actor_id,
            p.quote_text, p.sort_at, me
          ) end) || jsonb_build_object(
            'score', p.score,
            'cursor', jsonb_build_object(
              'anchor_at', v_anchor, 'score', p.score,
              'score_key', p.score_key,
              'sort_at', p.sort_at, 'kind_rank', p.kind_rank,
              'primary_id', p.primary_id, 'actor_id', p.actor_id
            )
          ) order by p.rn
      ) from page p), '[]'::jsonb),
      'has_more', exists(select 1 from numbered where rn > v_limit),
      'next_cursor', (select jsonb_build_object(
        'anchor_at', v_anchor, 'score', l.score,
        'score_key', l.score_key,
        'sort_at', l.sort_at, 'kind_rank', l.kind_rank,
        'primary_id', l.primary_id, 'actor_id', l.actor_id
      ) from last_row l)
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Engagement actors and quote posts
-- ---------------------------------------------------------------------------

create or replace function public.social_engagement_v1(
  p_type public.entity_type,
  p_id uuid,
  p_tab text default 'like',
  p_limit integer default 25,
  p_cursor jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_tab text := case lower(coalesce(p_tab, ''))
    when 'likes' then 'like' when 'reposts' then 'repost'
    when 'quotes' then 'quote' else lower(coalesce(p_tab, '')) end;
  v_cursor_at timestamptz := nullif(p_cursor ->> 'created_at', '')::timestamptz;
  v_cursor_id uuid := nullif(p_cursor ->> 'id', '')::uuid;
  v_summary jsonb;
begin
  if v_tab not in ('like', 'repost', 'quote') then
    raise exception 'bad_tab';
  end if;
  if p_cursor is not null and (v_cursor_at is null or v_cursor_id is null) then
    raise exception 'bad_cursor';
  end if;

  if not public.social_target_active(p_type, p_id) then
    return jsonb_build_object(
      'target', jsonb_build_object('type', p_type::text, 'id', p_id),
      'summary', jsonb_build_object(
        'like_count', 0, 'repost_count', 0, 'quote_count', 0
      ),
      'tab', v_tab, 'items', '[]'::jsonb,
      'has_more', false, 'next_cursor', null, 'unavailable', true
    );
  end if;

  v_summary := jsonb_build_object(
    'like_count', public.entity_counter(p_type, p_id, 'like_count'),
    'repost_count', public.entity_counter(p_type, p_id, 'repost_count'),
    'quote_count', public.entity_counter(p_type, p_id, 'quote_count')
  );

  if v_tab in ('like', 'repost') then
    return (
      with activity as (
        select l.user_id, l.created_at
          from public.likes l
         where v_tab = 'like' and l.entity_type = p_type and l.entity_id = p_id
        union all
        select r.user_id, r.created_at
          from public.reposts r
         where v_tab = 'repost' and r.entity_type = p_type and r.entity_id = p_id
      ), visible as (
        select a.user_id, a.created_at, pr.username, pr.display_name,
               pr.avatar_path, pr.is_verified
          from activity a
          join public.profiles pr on pr.id = a.user_id
         where pr.is_suspended = false
           and public.can_see_owner(a.user_id)
           and (p_cursor is null
             or (a.created_at, a.user_id) < (v_cursor_at, v_cursor_id))
      ), numbered as (
        select v.*, row_number() over (
          order by v.created_at desc, v.user_id desc
        ) as rn
        from visible v
        order by v.created_at desc, v.user_id desc
        limit v_limit + 1
      ), page as (
        select * from numbered where rn <= v_limit
      ), last_row as (
        select * from page order by rn desc limit 1
      )
      select jsonb_build_object(
        'target', jsonb_build_object('type', p_type::text, 'id', p_id),
        'summary', v_summary, 'tab', v_tab,
        'items', coalesce((select jsonb_agg(jsonb_build_object(
          'kind', 'actor',
          'user', jsonb_build_object(
            'id', p.user_id, 'username', p.username::text,
            'display_name', p.display_name, 'avatar_path', p.avatar_path,
            'is_verified', p.is_verified
          ),
          'viewer_follows', exists (
            select 1 from public.follows f
             where f.follower_id = me and f.following_id = p.user_id
          ),
          'acted_at', p.created_at
        ) order by p.rn) from page p), '[]'::jsonb),
        'has_more', exists(select 1 from numbered where rn > v_limit),
        'next_cursor', (select jsonb_build_object(
          'created_at', l.created_at, 'id', l.user_id
        ) from last_row l),
        'unavailable', false
      )
    );
  end if;

  return (
    with visible as (
      select p.id, p.created_at
        from public.posts p
        join public.profiles pr on pr.id = p.author_id
       where p.kind = 'quote'::public.post_kind
         and p.entity_type = p_type and p.entity_id = p_id
         and p.deleted_at is null and p.hidden_at is null
         and pr.is_suspended = false
         and public.can_view_entity('post'::public.entity_type, p.id)
         and (p_cursor is null
           or (p.created_at, p.id) < (v_cursor_at, v_cursor_id))
    ), numbered as (
      select v.*, row_number() over (
        order by v.created_at desc, v.id desc
      ) as rn
      from visible v
      order by v.created_at desc, v.id desc
      limit v_limit + 1
    ), page as (
      select * from numbered where rn <= v_limit
    ), last_row as (
      select * from page order by rn desc limit 1
    )
    select jsonb_build_object(
      'target', jsonb_build_object('type', p_type::text, 'id', p_id),
      'summary', v_summary, 'tab', v_tab,
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'kind', 'quote', 'entry', public.pulse_post_envelope(p.id, me),
        'acted_at', p.created_at
      ) order by p.rn) from page p), '[]'::jsonb),
      'has_more', exists(select 1 from numbered where rn > v_limit),
      'next_cursor', (select jsonb_build_object(
        'created_at', l.created_at, 'id', l.id
      ) from last_row l),
      'unavailable', false
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Profile Pulse timeline
-- ---------------------------------------------------------------------------

create or replace function public.profile_pulse_activity_v1(
  p_user uuid,
  p_view text default 'all',
  p_limit integer default 25,
  p_cursor jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_view text := lower(coalesce(p_view, ''));
  v_cursor_at timestamptz := nullif(p_cursor ->> 'sort_at', '')::timestamptz;
  v_cursor_kind integer := nullif(p_cursor ->> 'kind_rank', '')::integer;
  v_cursor_id uuid := nullif(p_cursor ->> 'primary_id', '')::uuid;
  v_cursor_actor uuid := nullif(p_cursor ->> 'actor_id', '')::uuid;
begin
  if v_view not in ('all', 'originals', 'reposts', 'quotes', 'media') then
    raise exception 'bad_view';
  end if;
  if p_cursor is not null and (
    v_cursor_at is null or v_cursor_kind is null
    or v_cursor_id is null or v_cursor_actor is null
  ) then raise exception 'bad_cursor'; end if;

  if p_user is null or not public.can_see_owner(p_user) then
    return jsonb_build_object(
      'user_id', p_user, 'view', v_view, 'items', '[]'::jsonb,
      'has_more', false, 'next_cursor', null, 'unavailable', true
    );
  end if;

  return (
    with candidates as (
      select 'post'::text as feed_kind, 1 as kind_rank,
             p.id as primary_id, p.author_id as actor_id,
             p.id as post_id, null::public.entity_type as repost_type,
             null::uuid as repost_id, null::text as quote_text,
             p.created_at as sort_at
        from public.posts p
       where p.author_id = p_user
         and p.deleted_at is null and p.hidden_at is null
         and p.reply_to_post_id is null
         and public.can_view_entity('post'::public.entity_type, p.id)
         and (
           v_view = 'all'
           or (v_view = 'originals' and p.kind = 'post'::public.post_kind)
           or (v_view = 'quotes' and p.kind = 'quote'::public.post_kind)
           or (v_view = 'media' and exists (
             select 1 from public.post_media pm where pm.post_id = p.id
           ))
         )
      union all
      select 'repost', 0, r.entity_id, r.user_id, null::uuid,
             r.entity_type, r.entity_id, r.quote_text, r.created_at
        from public.reposts r
       where r.user_id = p_user and v_view in ('all', 'reposts')
         and public.social_target_active(r.entity_type, r.entity_id)
    ), filtered as (
      select c.* from candidates c
       where p_cursor is null
          or (c.sort_at, c.kind_rank, c.primary_id, c.actor_id)
             < (v_cursor_at, v_cursor_kind, v_cursor_id, v_cursor_actor)
    ), numbered as (
      select f.*, row_number() over (
        order by f.sort_at desc, f.kind_rank desc,
                 f.primary_id desc, f.actor_id desc
      ) as rn
      from filtered f
      order by f.sort_at desc, f.kind_rank desc,
               f.primary_id desc, f.actor_id desc
      limit v_limit + 1
    ), page as (
      select * from numbered where rn <= v_limit
    ), last_row as (
      select * from page order by rn desc limit 1
    )
    select jsonb_build_object(
      'user_id', p_user, 'view', v_view,
      'items', coalesce((select jsonb_agg(
        case when p.feed_kind = 'post'
          then public.pulse_post_envelope(p.post_id, me)
          else public.pulse_repost_envelope(
            p.repost_type, p.repost_id, p.actor_id,
            p.quote_text, p.sort_at, me
          ) end order by p.rn
      ) from page p), '[]'::jsonb),
      'has_more', exists(select 1 from numbered where rn > v_limit),
      'next_cursor', (select jsonb_build_object(
        'sort_at', l.sort_at, 'kind_rank', l.kind_rank,
        'primary_id', l.primary_id, 'actor_id', l.actor_id
      ) from last_row l),
      'unavailable', false
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Public profile discussion chronology (comments are the reply primitive)
-- ---------------------------------------------------------------------------

create or replace function public.profile_discussion_activity_v1(
  p_user uuid,
  p_surface text default 'all',
  p_limit integer default 25,
  p_cursor jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_surface text := lower(coalesce(p_surface, ''));
  v_cursor_at timestamptz := nullif(p_cursor ->> 'created_at', '')::timestamptz;
  v_cursor_id uuid := nullif(p_cursor ->> 'id', '')::uuid;
begin
  if v_surface not in ('all', 'surf', 'pulse') then
    raise exception 'bad_surface';
  end if;
  if p_cursor is not null and (v_cursor_at is null or v_cursor_id is null) then
    raise exception 'bad_cursor';
  end if;

  if p_user is null or not public.can_see_owner(p_user) then
    return jsonb_build_object(
      'user_id', p_user, 'surface', v_surface, 'items', '[]'::jsonb,
      'has_more', false, 'next_cursor', null, 'unavailable', true
    );
  end if;

  return (
    with visible as (
      select c.id, c.body, c.created_at, c.parent_id,
             coalesce(root.root_id, c.id) as root_id,
             c.entity_type, c.entity_id,
             case when c.entity_type = 'post'::public.entity_type
               then 'pulse' else 'surf' end as surface,
             c.like_count, c.save_count, c.repost_count, c.reply_count,
             jsonb_build_object(
               'id', author.id, 'username', author.username::text,
               'display_name', author.display_name,
               'avatar_path', author.avatar_path,
               'is_verified', author.is_verified
             ) as author,
             payload.target,
             case
               when parent.id is null
                 or parent.deleted_at is not null
                 or parent.hidden_at is not null
                 or parent_author.is_suspended
                 or public.blocked_with(parent.author_id)
                 then null
               else jsonb_build_object(
                 'id', parent.id, 'author_id', parent.author_id,
                 'username', parent_author.username::text,
                 'body', parent.body
               )
             end as replying_to
        from public.comments c
        join public.profiles author on author.id = c.author_id
        left join public.comments parent on parent.id = c.parent_id
        left join public.profiles parent_author on parent_author.id = parent.author_id
        left join lateral (
          with recursive chain as (
            select c.id as node_id, c.parent_id, 0 as distance
            union all
            select ancestor.id, ancestor.parent_id, chain.distance + 1
              from chain
              join public.comments ancestor on ancestor.id = chain.parent_id
             where chain.distance < 24
          )
          select chain.node_id as root_id
            from chain
           order by chain.distance desc
           limit 1
        ) root on true
        cross join lateral (
          select public.pulse_target_payload(c.entity_type, c.entity_id) as target
        ) payload
       where c.author_id = p_user
         and c.deleted_at is null and c.hidden_at is null
         and author.is_suspended = false
         and public.social_target_active(c.entity_type, c.entity_id)
         and (
           v_surface = 'all'
           or (v_surface = 'pulse'
               and c.entity_type = 'post'::public.entity_type)
           or (v_surface = 'surf'
               and c.entity_type <> 'post'::public.entity_type)
         )
         and (p_cursor is null
           or (c.created_at, c.id) < (v_cursor_at, v_cursor_id))
    ), numbered as (
      select v.*, row_number() over (
        order by v.created_at desc, v.id desc
      ) as rn
      from visible v
      order by v.created_at desc, v.id desc
      limit v_limit + 1
    ), page as (
      select * from numbered where rn <= v_limit
    ), last_row as (
      select * from page order by rn desc limit 1
    )
    select jsonb_build_object(
      'user_id', p_user, 'surface', v_surface,
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'body', p.body, 'created_at', p.created_at,
        'parent_id', p.parent_id, 'root_id', p.root_id,
        'author', p.author,
        'counts', jsonb_build_object(
          'like', p.like_count, 'save', p.save_count,
          'repost', p.repost_count, 'reply', p.reply_count
        ),
        'viewer', jsonb_build_object(
          'liked', exists (select 1 from public.likes l
            where l.user_id = me
              and l.entity_type = 'comment'::public.entity_type
              and l.entity_id = p.id),
          'saved', exists (select 1 from public.saves s
            where s.user_id = me
              and s.entity_type = 'comment'::public.entity_type
              and s.entity_id = p.id),
          'reposted', exists (select 1 from public.reposts r
            where r.user_id = me
              and r.entity_type = 'comment'::public.entity_type
              and r.entity_id = p.id)
        ),
        'surface', p.surface,
        'context', jsonb_build_object(
          'target_type', p.entity_type::text,
          'target_id', p.entity_id,
          'title', p.target ->> 'title',
          'body', p.target ->> 'body',
          'cover_path', p.target ->> 'cover_path',
          'author', p.target -> 'author',
          'unavailable', coalesce((p.target ->> 'unavailable')::boolean, false)
        ),
        'destination', jsonb_build_object(
          'type', p.entity_type::text, 'id', p.entity_id,
          'highlight_comment_id', p.id
        ),
        'replying_to', p.replying_to
      ) order by p.rn) from page p), '[]'::jsonb),
      'has_more', exists(select 1 from numbered where rn > v_limit),
      'next_cursor', (select jsonb_build_object(
        'created_at', l.created_at, 'id', l.id
      ) from last_row l),
      'unavailable', false
    )
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Owner-only Likes and Saves, split into Surf and Pulse
-- ---------------------------------------------------------------------------

create or replace function public.my_profile_reactions_v1(
  p_action text,
  p_surface text,
  p_limit integer default 25,
  p_cursor jsonb default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_action text := lower(coalesce(p_action, ''));
  v_surface text := lower(coalesce(p_surface, ''));
  v_limit integer := greatest(1, least(coalesce(p_limit, 25), 50));
  v_cursor_at timestamptz := nullif(p_cursor ->> 'created_at', '')::timestamptz;
  v_cursor_type text := nullif(p_cursor ->> 'entity_type', '');
  v_cursor_id uuid := nullif(p_cursor ->> 'entity_id', '')::uuid;
begin
  if v_action not in ('like', 'save') then raise exception 'bad_action'; end if;
  if v_surface not in ('surf', 'pulse') then raise exception 'bad_surface'; end if;
  if p_cursor is not null and (
    v_cursor_at is null or v_cursor_type is null or v_cursor_id is null
  ) then raise exception 'bad_cursor'; end if;

  return (
    with activity as (
      select l.entity_type, l.entity_id, l.created_at
        from public.likes l
       where v_action = 'like' and l.user_id = me
      union all
      select s.entity_type, s.entity_id, s.created_at
        from public.saves s
       where v_action = 'save' and s.user_id = me
    ), visible as (
      select a.*
        from activity a
       where public.social_target_active(a.entity_type, a.entity_id)
         and (
           (v_surface = 'surf' and a.entity_type in (
             'collection'::public.entity_type,
             'subcollection'::public.entity_type,
             'item'::public.entity_type
           ))
           or (v_surface = 'pulse' and a.entity_type in (
             'post'::public.entity_type, 'comment'::public.entity_type
           ))
         )
         and (p_cursor is null or (
           a.created_at, a.entity_type::text, a.entity_id
         ) < (v_cursor_at, v_cursor_type, v_cursor_id))
    ), numbered as (
      select v.*, row_number() over (
        order by v.created_at desc, v.entity_type::text desc, v.entity_id desc
      ) as rn
      from visible v
      order by v.created_at desc, v.entity_type::text desc, v.entity_id desc
      limit v_limit + 1
    ), page as (
      select * from numbered where rn <= v_limit
    ), last_row as (
      select * from page order by rn desc limit 1
    )
    select jsonb_build_object(
      'action', v_action, 'surface', v_surface,
      'items', coalesce((select jsonb_agg(jsonb_build_object(
        'acted_at', p.created_at,
        'target_type', p.entity_type::text,
        'target_id', p.entity_id,
        'entry', case when p.entity_type = 'post'::public.entity_type
          then public.pulse_post_envelope(p.entity_id, me) else null end,
        'target', public.pulse_target_payload(p.entity_type, p.entity_id)
      ) order by p.rn) from page p), '[]'::jsonb),
      'has_more', exists(select 1 from numbered where rn > v_limit),
      'next_cursor', (select jsonb_build_object(
        'created_at', l.created_at,
        'entity_type', l.entity_type::text,
        'entity_id', l.entity_id
      ) from last_row l)
    )
  );
end;
$$;

-- Owner management uses an RPC so soft deletion and quote-count reconciliation
-- stay atomic. Repeating the request is deliberately successful.
create or replace function public.delete_post(
  p_post uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := public.require_auth();
  v_author uuid;
  v_deleted_at timestamptz;
begin
  if p_post is null then raise exception 'post_not_found'; end if;

  select p.author_id, p.deleted_at
    into v_author, v_deleted_at
    from public.posts p
   where p.id = p_post
   for update;

  if not found then raise exception 'post_not_found'; end if;
  if v_author is distinct from me then raise exception 'not_post_owner'; end if;

  if v_deleted_at is null then
    update public.posts
       set deleted_at = statement_timestamp()
     where id = p_post;
  end if;

  return jsonb_build_object('deleted', true, 'post_id', p_post);
end;
$$;

comment on function public.delete_post(uuid) is
  'Owner-only idempotent Pulse post soft deletion. Quote count reconciliation is handled by posts_quote_count.';

-- ---------------------------------------------------------------------------
-- Explicit RPC surface
-- ---------------------------------------------------------------------------

revoke execute on function public.bump_quote_target(
  public.entity_type, uuid, integer
) from public, anon, authenticated;
revoke execute on function public.bump_quote_counters()
  from public, anon, authenticated;
revoke execute on function public.social_target_active(
  public.entity_type, uuid
) from public, anon, authenticated;

-- Existing create_post stays authenticated-only.
revoke execute on function public.create_post(
  text, public.post_kind, public.entity_type, uuid, jsonb, uuid
) from public, anon;
grant execute on function public.create_post(
  text, public.post_kind, public.entity_type, uuid, jsonb, uuid
) to authenticated, service_role;

revoke execute on function public.pulse_feed_v2(text, integer, jsonb)
  from public, anon;
grant execute on function public.pulse_feed_v2(text, integer, jsonb)
  to authenticated, service_role;

revoke execute on function public.social_engagement_v1(
  public.entity_type, uuid, text, integer, jsonb
) from public;
grant execute on function public.social_engagement_v1(
  public.entity_type, uuid, text, integer, jsonb
) to anon, authenticated, service_role;

revoke execute on function public.profile_pulse_activity_v1(
  uuid, text, integer, jsonb
) from public;
grant execute on function public.profile_pulse_activity_v1(
  uuid, text, integer, jsonb
) to anon, authenticated, service_role;

revoke execute on function public.profile_discussion_activity_v1(
  uuid, text, integer, jsonb
) from public;
grant execute on function public.profile_discussion_activity_v1(
  uuid, text, integer, jsonb
) to anon, authenticated, service_role;

revoke execute on function public.my_profile_reactions_v1(
  text, text, integer, jsonb
) from public, anon;
grant execute on function public.my_profile_reactions_v1(
  text, text, integer, jsonb
) to authenticated, service_role;

revoke execute on function public.delete_post(uuid)
  from public, anon;
grant execute on function public.delete_post(uuid)
  to authenticated, service_role;

-- Internal envelope helpers remain non-REST-callable after replacement.
revoke execute on function public.pulse_target_payload(
  public.entity_type, uuid
) from public, anon, authenticated;
revoke execute on function public.pulse_post_envelope(uuid, uuid)
  from public, anon, authenticated;
revoke execute on function public.pulse_repost_envelope(
  public.entity_type, uuid, uuid, text, timestamptz, uuid
) from public, anon, authenticated;

commit;
