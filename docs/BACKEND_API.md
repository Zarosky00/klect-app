# KLECT — Backend API contract

Everything below is **live and tested** on `new_klect` (`dikhuygcwxnrsckqglzg`).
Both clients code against exactly this. If you need something that isn't here, add a migration —
do not work around it in the client.

```
URL   https://dikhuygcwxnrsckqglzg.supabase.co
KEY   sb_publishable_nwJjxG8yJ01lTjrv6pXQww_mQ9MNq5t
```

---

## 1. The entity model

`entity_type` = `'collection' | 'subcollection' | 'item' | 'post' | 'comment'`

All social actions are **polymorphic** over `(entity_type, entity_id)`. One code path in the client
serves likes on a collection, a subcollection, an item, a post, or a comment.

```
collections ──< subcollections ──< items ──< item_media
     │                 │             │
     └─────────────────┴─────────────┴──── likes / saves / reposts / comments / entity_views / entity_tags
```

Every entity row carries live counters: `like_count`, `save_count`, `repost_count`,
`comment_count`, `view_count` (+ `item_count`, `subcollection_count`, `media_count`, `reply_count`).
**These are maintained by database triggers. Never COUNT(*) in a client. Never write to them —
column privileges make it physically impossible.**

Visibility inherits **down**: an item with `visibility = null` takes its subcollection's, which takes
its collection's. `visibility` ∈ `public | followers | private`.

---

## 2. RPCs — the entire write surface

Call with `supabase.rpc('name', {...})`.

### Interactions — all idempotent, all return authoritative state

| RPC | Args | Returns |
|---|---|---|
| `toggle_like` | `p_type`, `p_id` | `{ active: bool, count: int }` |
| `toggle_save` | `p_type`, `p_id`, `p_note?` | `{ active: bool, count: int }` |
| `toggle_repost` | `p_type`, `p_id`, `p_quote?` | `{ active: bool, count: int }` |
| `toggle_follow` | `p_user` | `{ active: bool, count: int }` (target's follower_count) |
| `record_view` | `p_type`, `p_id` | `int` — deduped per viewer per day |
| `add_comment` | `p_type`, `p_id`, `p_body`, `p_parent?` | `{ id: uuid, count: int }` |
| `delete_comment` | `p_comment` | `{ count: int }` |
| `submit_report` | `p_reason`, `p_type?`, `p_id?`, `p_user?`, `p_message?`, `p_details?` | `{ id, already_reported }` |

**Optimistic-UI contract:** apply the delta locally the instant the finger lifts → fire the RPC →
overwrite local state with the returned `{active, count}`. Because the RPC is idempotent, a
double-fire, a retry, or an offline replay can never corrupt the count.

`p_reason` ∈ `spam | nudity | harassment | hate | violence | self_harm | ip_violation |
misinformation | impersonation | other`

### Feeds & discovery

| RPC | Args | Returns |
|---|---|---|
| `surf_feed` | `p_limit=30`, `p_offset=0`, `p_seed`, `p_filter` | `setof surf_card` — **the Pinterest grid** |
| `pulse_feed` | `p_limit=25`, `p_before?` | `jsonb[]` — **the X stream** |
| `get_closeup` | `p_type`, `p_id` | `jsonb` — **the single-tap detail payload** |
| `search_all` | `p_q`, `p_limit=20` | `{ people, collections, items, tags }` |
| `get_matches` | `p_limit=20` | collectors ranked by taste overlap (recomputes on call) |

`p_filter` ∈ `all | following | items | collections`.
`p_seed` — pass a **stable per-user string** (e.g. the user id, or user id + session date). It
deterministically jitters ranking so two people never see the same order while one person's
pagination stays stable across pages.

`surf_card` columns:
```
entity_type, entity_id, owner_id, username, display_name, avatar_path, is_verified,
title, subtitle, cover_path, cover_blurhash, width, height, accent_color,
like_count, save_count, repost_count, comment_count, view_count, child_count,
created_at, score, viewer_liked, viewer_saved, viewer_reposted, viewer_follows
```
`width`/`height` are the cover's intrinsic pixels — **use them to reserve the masonry tile before the
image loads** so the grid never reflows. `cover_blurhash` is the placeholder.

`surf_feed` **interleaves the three entity types** on a fixed cadence (item every slot, subcollection
every 3rd, collection every 6th), best-first within each type. So a page reads like
`item item subcollection item collection item item subcollection …`. Your grid must render all three
card shapes — do not assume every card is an item.

> ### ⚠️ Image path rule — applies to EVERY `cover_path`, `avatar_path`, `banner_path`, `storage_path`
> **If the value starts with `http://` or `https://`, use it verbatim as the image URL.
> Otherwise resolve it as a Supabase Storage object key** via
> `supabase.storage.from(bucket).getPublicUrl(path)`.
> The seeded demo content uses absolute URLs; real uploads use storage keys. Write one helper
> (`resolveImageUrl(path, bucket)`) and route every image through it.

`get_closeup` always returns `entity_type, entity_id, owner, viewer{liked,saved,reposted,follows,is_owner},
counts{like,save,repost,comment,view}, tags[]`, plus, by type:
- **item** → `item`, `media[]` (ordered), `breadcrumb{collection, subcollection}`, `siblings[]`
- **subcollection** → `subcollection`, `breadcrumb{collection}`, `items[]`
- **collection** → `collection`, `subcollections[]`, `items[]`
- **post** → `post`

### Messaging

| RPC | Args | Returns |
|---|---|---|
| `start_dm` | `p_other` | `uuid` conversation id — one DM per pair, ever; enforces the recipient's `allow_messages_from` |
| `mark_conversation_read` | `p_conversation` | void — zeroes unread + clears message notifications |
| `mark_notifications_read` | `p_ids?` | `int` — null = mark all |

Send a message by **inserting into `messages`**. Triggers then update the conversation preview,
bump every other member's `unread_count`, and create notifications.

### Admin (every one re-checks `is_staff()` / `is_admin()` server-side)

| RPC | Args |
|---|---|
| `admin_metrics` | — |
| `admin_list_reports` | `p_status='open'`, `p_limit`, `p_offset` |
| `admin_resolve_report` | `p_report`, `p_action`, `p_reason?`, `p_suspend_days?` |
| `admin_moderate_entity` | `p_type`, `p_id`, `p_hidden`, `p_reason?` |
| `admin_set_user_state` | `p_user`, `p_suspended`, `p_days?`, `p_reason?` |
| `admin_set_verified` | `p_user`, `p_verified` |
| `admin_set_role` | `p_user`, `p_role`, `p_grant` *(superadmin only)* |
| `admin_user_detail` | `p_user` |

`p_action` ∈ `none | warn | hide_content | delete_content | suspend_user | ban_user | restore_content`.
Resolving one report auto-resolves every other open report about the same target.

Gate the admin UI on `select role from user_roles where user_id = auth.uid()` — but note the server
enforces it regardless, so a leaked route exposes nothing.

---

## 3. Realtime

Published tables: `collections, subcollections, items, posts, comments, messages, conversations,
conversation_members, message_reactions, notifications, calls, call_participants, call_signals, profiles`.
RLS is honoured on the stream.

**Live counters:** do **not** subscribe to `likes`. Subscribe to `UPDATE` on the entity row itself —
one event carries every fresh counter at once.

```dart
supabase.channel('item:$id')
  .onPostgresChanges(
    event: PostgresChangeEvent.update, schema: 'public', table: 'items',
    filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: id),
    callback: (p) => setCounts(p.newRecord))
  .subscribe();
```

**Typing indicators / presence:** use Realtime **broadcast + presence**, never a table.

**Calls:** create a `calls` row (`status='ringing'`) → both sides exchange SDP/ICE through
`call_signals` inserts (`type` ∈ `offer|answer|ice|renegotiate|bye`) → move `status` to `active`,
then `ended` with `duration_seconds`. A TURN server is still required for cross-NAT reliability.

---

## 4. Storage

| bucket | public | limit | path convention |
|---|---|---|---|
| `avatars` | yes | 5 MB | `{user_id}/{uuid}.webp` |
| `banners` | yes | 10 MB | `{user_id}/{uuid}.webp` |
| `media` | yes | 25 MB | `{user_id}/{item_id}/{uuid}.webp` |
| `chat` | no | 25 MB | `{user_id}/{conversation_id}/{uuid}.webp` |

**The first path segment must be the uploader's user id** — the storage policy enforces it.

After uploading, insert an `item_media` row with `storage_path`, `width`, `height`, `blurhash`.
A trigger sets the parent item's `cover_*` from position 0 automatically.

---

## 5. Errors to handle explicitly

| Condition | Surface |
|---|---|
| `42501` from a toggle/comment | content became invisible or you're blocked → refresh the card, don't retry |
| `Account suspended` | route to a suspension screen; every write RPC raises this |
| `This person is not accepting messages` | from `start_dm` — respect `allow_messages_from` |
| unique violation on `follows`/`likes` | already applied; treat as success |
