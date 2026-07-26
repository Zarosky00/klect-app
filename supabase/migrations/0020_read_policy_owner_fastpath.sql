-- ============================================================================
-- 0020_read_policy_owner_fastpath.sql — fix INSERT…RETURNING under RLS for
-- subcollections and items.
--
-- BUG (P0, found while smoke-testing 0019): `INSERT … RETURNING` (which both
-- clients use as `.insert(...).select()`) failed with "new row violates
-- row-level security policy" on `subcollections`. The read policy was a bare
-- `can_view_entity('subcollection', id)` — a SECURITY DEFINER function that
-- LOOKS THE ROW UP BY ID. During the inserting statement the new row is not
-- yet visible to that lookup (same-command MVCC visibility), so the RETURNING
-- visibility check evaluated false. Client-side subcollection creation has
-- therefore been broken since 0008. `items` has the identical policy shape
-- (mobile item creation dodges it via the create_item RPC, but any direct
-- insert-returning hits it). Collections were never affected — their read
-- policy is inline over the row's own columns.
--
-- Fix: add an inline owner fast-path evaluated over the NEW row itself, before
-- the self-lookup. Semantics preserved (owners can always see their own rows —
-- can_view_entity already returns true for owners of committed rows); bonus:
-- owner-scoped queries now skip the definer-function call entirely.
--
-- STATUS: applied 2026-07-27 via MCP apply_migration. Full onboarding-shaped
-- smoke (slugless collection + subcollection with RETURNING, under JWT
-- impersonation) passes end-to-end; rolled back.
-- ============================================================================

alter policy subcollections_read on public.subcollections
  using (
    (( select auth.uid() ) = user_id)
    or can_view_entity('subcollection'::entity_type, id)
  );

alter policy items_read on public.items
  using (
    (( select auth.uid() ) = user_id)
    or can_view_entity('item'::entity_type, id)
  );
