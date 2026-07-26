-- ============================================================================
-- 0019_slug_autogen.sql — server-side slug generation for collections and
-- subcollections.
--
-- BUG (P0, user-reported with screenshot): onboarding's "pick interests →
-- shelves" step failed with `null value in column "slug" of relation
-- "collections" violates not-null constraint`. Root cause: both clients insert
-- collections/subcollections WITHOUT a slug (mobile klect_api.dart even says
-- "slugs are handled server-side"), but the live schema had NO default, NO
-- trigger and NO slug function — nothing server-side ever filled it. Every
-- client-side shelf/group creation since 0001 failed; demo content worked only
-- because the 0014 seed supplied slugs by hand.
--
-- Fix: public.slugify() + BEFORE INSERT triggers that derive the slug from
-- `name` when the client omits it, honouring the live constraints:
--   collections    slug ~ '^[a-z0-9-]{1,80}$'  UNIQUE (user_id, slug)
--   subcollections slug ~ '^[a-z0-9-]{1,80}$'  UNIQUE (collection_id, slug)
-- Collisions get -2, -3… suffixes (random tail after 50 tries). Client-supplied
-- slugs are left untouched. Items have no slug column — nothing to do there.
--
-- Posture per 0012: definer, search_path pinned, EXECUTE revoked (trigger
-- functions need no callable surface).
--
-- STATUS: applied 2026-07-27 via MCP apply_migration; smoke-tested under JWT
-- impersonation (slugless insert → 'vinyl-era', duplicate name → 'vinyl-era-2',
-- subcollection scope honoured), rolled back cleanly.
-- ============================================================================

create or replace function public.slugify(p_text text) returns text
language sql
immutable
set search_path = ''
as $$
  select left(
    coalesce(
      nullif(btrim(regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9]+', '-', 'g'), '-'), ''),
      'shelf'
    ),
    60
  );
$$;

comment on function public.slugify(text) is
  'Lowercase-dash slug, ≤60 chars, never empty. Used by the slug-default triggers.';

create or replace function public.collections_slug_default() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base      text;
  v_candidate text;
  v_i         integer := 1;
begin
  if new.slug is not null and new.slug <> '' then
    return new;
  end if;
  v_base := public.slugify(new.name);
  v_candidate := v_base;
  while exists (
    select 1 from public.collections c
    where c.user_id = new.user_id and c.slug = v_candidate and c.id is distinct from new.id
  ) loop
    v_i := v_i + 1;
    if v_i > 50 then
      v_candidate := v_base || '-' || substr(md5(gen_random_uuid()::text), 1, 6);
      exit;
    end if;
    v_candidate := v_base || '-' || v_i;
  end loop;
  new.slug := v_candidate;
  return new;
end;
$$;

create or replace function public.subcollections_slug_default() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_base      text;
  v_candidate text;
  v_i         integer := 1;
begin
  if new.slug is not null and new.slug <> '' then
    return new;
  end if;
  v_base := public.slugify(new.name);
  v_candidate := v_base;
  while exists (
    select 1 from public.subcollections s
    where s.collection_id = new.collection_id and s.slug = v_candidate and s.id is distinct from new.id
  ) loop
    v_i := v_i + 1;
    if v_i > 50 then
      v_candidate := v_base || '-' || substr(md5(gen_random_uuid()::text), 1, 6);
      exit;
    end if;
    v_candidate := v_base || '-' || v_i;
  end loop;
  new.slug := v_candidate;
  return new;
end;
$$;

drop trigger if exists collections_slug_default on public.collections;
create trigger collections_slug_default
  before insert on public.collections
  for each row execute function public.collections_slug_default();

drop trigger if exists subcollections_slug_default on public.subcollections;
create trigger subcollections_slug_default
  before insert on public.subcollections
  for each row execute function public.subcollections_slug_default();

revoke execute on function public.slugify(text)                     from public, anon, authenticated;
revoke execute on function public.collections_slug_default()        from public, anon, authenticated;
revoke execute on function public.subcollections_slug_default()     from public, anon, authenticated;
