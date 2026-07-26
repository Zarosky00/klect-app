# Supabase — `new_klect`

| | |
|---|---|
| project ref | `dikhuygcwxnrsckqglzg` |
| region | ap-southeast-2 |
| Postgres | 17 |
| URL | `https://dikhuygcwxnrsckqglzg.supabase.co` |
| publishable key | `sb_publishable_nwJjxG8yJ01lTjrv6pXQww_mQ9MNq5t` |

The API contract is documented in [`../docs/BACKEND_API.md`](../docs/BACKEND_API.md).

## Migrations applied (in order)

| # | name | what it does |
|---|---|---|
| 0001 | `foundation` | extensions, 14 enums, `profiles`, `user_roles`, `push_tokens`, signup trigger, role helpers |
| 0002 | `catalog` | `collection_templates`, `collections`, `subcollections`, `items`, `item_media`, `tags`, `entity_tags` |
| 0003 | `social_graph_and_counters` | `posts`, `comments`, polymorphic `likes`/`saves`/`reposts`/`entity_views`, `follows`, `blocks`, `mutes`, **the counter trigger engine**, polymorphic cleanup |
| 0004 | `messaging_calls_notifications` | conversations, members, messages, reactions, receipts, calls, call signalling, notifications + fanout |
| 0005 | `moderation_and_admin` | `reports`, `moderation_actions`, `audit_log`, taste vectors, matching |
| 0006 | `rls_helpers_and_guards` | `can_see_owner`, `visible_to_me`, `can_view_entity` (visibility inherits down the hierarchy), conversation membership helpers |
| 0007 | `column_privileges` | revokes UPDATE, re-grants only user-editable columns — counters become physically unwritable by clients |
| 0008 | `rls_policies` | RLS enabled + forced on all 34 tables, 87 policies |
| 0009 | `interaction_rpcs` | `toggle_like/save/repost/follow`, `record_view`, `add_comment`, `submit_report`, `start_dm`, read-marking |
| 0010 | `feeds_and_discovery` | `surf_feed` (Pinterest), `pulse_feed` (X), `get_closeup`, `search_all`, `get_matches` |
| 0011 | `admin_realtime_storage_seed` | admin RPCs, realtime publication, 4 storage buckets + policies, 18 templates + 54 tags |
| 0012 | `harden_functions_and_grants` | advisor remediation: extensions out of `public`, pinned `search_path`, EXECUTE revoked then re-granted to a named RPC surface |
| 0013 | `perf_indexes_and_policy_split` | 28 foreign-key covering indexes; split the two `FOR ALL` policies so `SELECT` is served by one policy |
| 0014 | `demo_seed` | 8 users, 8 collections, 13 subcollections, 52 items, ~100 photos, plus follows/likes/saves/reposts/views/comments so the grid looks real |
| 0015 | `surf_feed_type_interleave` | feed diversity — items/subcollections/collections interleaved on a fixed cadence instead of pure score order |
| 0016 | `match_freshness_and_maintenance` | `get_matches` caches for 6h and invalidates on taste change; nightly `pg_cron` job for match warming, signal cleanup, stuck calls, expired suspensions |
| 0017 | `group_chats` | group-management RPCs (`create_group`, `add_group_members`, `remove_group_member`, `update_group_info`, `set_group_member_role`) with system messages + owner auto-transfer. Applied 2026-07-26; all five RPCs smoke-tested under JWT impersonation (incl. ownership transfer on owner leave), advisors 0 ERROR |

## Pulling these into the repo as files

The authoritative copy lives in the project's `supabase_migrations.schema_migrations` table.
To materialise them here:

```bash
npx supabase link --project-ref dikhuygcwxnrsckqglzg
```

```bash
npx supabase db pull
```

## Two design decisions worth knowing before you change anything

**1. Counters are columns, not queries.**
`like_count`, `save_count`, `repost_count`, `comment_count`, `view_count`, `item_count`,
`subcollection_count`, `media_count` and `reply_count` are maintained by triggers on write. Clients
read the column and apply an optimistic delta. This is why counts feel instant and why the feed can
rank by engagement without a single aggregate.

Clients **cannot** write them — not by convention, but because `0007_column_privileges` revoked
`UPDATE` on those columns from the `authenticated` role. Triggers run as the table owner, so they
are unaffected. This was chosen over BEFORE-UPDATE guard triggers, which would have fought the
counter triggers themselves.

**2. Social tables are polymorphic over `(entity_type, entity_id)`.**
One `likes` table serves collections, subcollections, items, posts and comments. Postgres can't
foreign-key that, so `purge_entity_social()` runs BEFORE DELETE on each parent table to clean up.
If you add a new entity type: extend the `entity_type` enum, add it to the `case` in
`bump_entity_counter`, `bump_comment_counters`, `entity_owner`, `entity_counter`,
`can_view_entity` and `purge_entity_social`, and add a `purge` trigger to the new table.

## Demo data

Three seeded auth users exist (`aria`, `kenji`, `klectmod`) with a populated Anime > JJK/One Piece
tree, a private collection for RLS testing, and one open report. `klectmod` holds the `moderator`
role. See `../docs/PROJECT_STATE.md`.
