# ROUND 3 PLAN — perf, thread-first Pulse, share, notifications, identity

> 2026-07-27. Grounded in a 5-agent audit (R1 web-perf/create, R2 visual/share, R3 pulse-phase-2,
> R4 notifications/identity, R5 completeness). P0s already shipped ahead of this plan:
> 0019 slug autogen + 0020 RLS insert-returning fix (onboarding shelf creation works, live).
> Execution: C0 (DB) ∥ W1 → then mobile chain M1→M2 ∥ web chain W2→W3→W4 → verify → ship v1.3.0.

## C0 — Migration `0021_threads_and_feed_fixes` (author → I apply → smoke → regen types)

1. **Comments become full social citizens**: add `save_count`, `repost_count` to comments; extend
   the counter-trigger dispatch + `entity_counter` comment branch; verify/fix the 0018 repost
   branch for `entity_type='comment'` rows (feed-poisoning risk: envelope built on columns that
   didn't exist).
2. **`get_post_thread(p_post, p_limit, p_before, p_sort)`** — the X thread payload: post envelope
   (with media + target) + stats + paged comments with batched viewer like/save/repost state.
   Comments (not `kind='reply'` posts) are the one discussion primitive — verify live that zero
   reply-kind posts exist, then have `create_post` reject `p_reply_to` (deprecate the dead twin).
3. **`user_posts(p_user, p_limit, p_before)`** — profile Posts tab feed (posts + reposts + quotes
   by author, same envelope).
4. **`pulse_feed` fixes**: composite keyset cursor `(created_at, id)` + `has_more` flag (stops the
   same-timestamp skip and For-you's silent truncation); For-you candidates include entity
   reposts (seeded/legacy activity circulates); window fallback ladder 30d→90d→all-time.
5. **`search_all` gains posts**: generated tsv on `posts.body` + GIN, posts segment in the payload.
6. Data fix alongside: repair seeded cover paths that 404 (`media/1111/…`), verified live.

## W1 — Web performance overhaul (starts immediately, independent)

R1's five lag causes, in impact order: (1) **next/image everywhere** through BlurhashImage
(remotePatterns already configured; real srcset/sizes; thumbnail rail stops loading originals);
(2) **masonry windowing** — `content-visibility:auto` + `contain-intrinsic-size` per tile, page cap
with trim; (3) **kill per-tile backdrop-filter on touch** — flat scrim overlays; glass stays on the
two chrome bars only; (4) **closeup modal loading.tsx** + instant skeleton (kill the dead-tap);
(5) **CSS entrances replace per-tile framer-motion** (`k-feed-enter` like Pulse) + dynamic-import
the viewer/closeup internals; ImmersiveViewer gestures move from React state to ref-written
transforms (compositor-speed pinch/pan). Verify with a before/after route-size table.

## M1 (mobile) / W2 (web) — Share, links, notifications, misc quality

- **Dead links (ship first)**: `KlectLinks.webOrigin` → dart-define, default
  `https://klect-web.vercel.app`; web `publicUrl` gains mobile's bucket-prefix stripping.
- **One share chooser** per client behind every share entry: [Send to a friend | Copy link |
  System share]. Send-to-friend = conversation picker (generalize mobile ForwardSheet; web mirrors
  EntitySharePicker) firing the existing `entity_share` message shape — works for posts too.
- **Shared posts render in chat** (both `fetchEntityPreview` post branch + web resolver); fix the
  entity-share bubble stretch (`CrossAxisAlignment.stretch`→`.center`); web chat gets an
  optimistic pending bubble.
- **Notifications stage 0**: shell-level realtime listener (badge live from app start, not first
  Alerts visit) + `KBanner` top banner (glass, avatar + verb + thumb, tap deep-links, swipe
  dismiss, suppressed on the originating screen); web: hoisted channel in the signed-in layout +
  banner + nav badge (`countUnreadNotifications` is currently dead code); mobile unread count via
  head-count instead of materializing ids.
- **Onboarding hardening**: `_finish` idempotent (skip already-created templates on retry),
  parallelize the RPC chain, sign-out escape hatch, and BOTH clients stop leaking raw Postgres
  text (generic copy + detail demoted).
- Misc: pulse composer PopScope + draft persistence; offline first-page cache (Surf/Pulse/inbox)
  via KeyValueStore; `fetchSuggestedCollectors` filters suspended; web settings gains a
  Notifications section; align default Pulse tab = For-you on both.

## M2 (mobile) / W3 (web) — Thread-first Pulse (needs C0)

- **Post thread page** replaces closeup as the post destination (mobile `/post/:id`; web `/p/[id]`
  + intercepting modal): X anatomy — author header, full-size body, inline bounded media, stats
  row (likes · reposts · saves), comment action bars, reply-first composer, Top/Newest sort,
  load-more.
- **Comment action bar** (like · save · repost-with-Quote · reply · share) on both clients.
- **Pulse visually splits from Surf**: no double-tap immersive / hero on pulse rows, plain tap →
  thread, long-press peek stays; single photos bounded inline, not masonry-shaped.
- **Filter drawer** under the tabs (animated collapse): Type [All·Text·Photos·Collections·Quotes],
  Time [Today·Week·Month·All], Shared-taste toggle, + search-within-pulse (search_all posts).
- **Profile Posts tab** (both) via `user_posts`.
- Bug fixes riding along: web post view fetches `post_media` (photos vanish today), mobile
  comment-target card renders the comment body, web stream `entryKey` includes `target_id`,
  clients adopt the composite cursor + `has_more`.

## W4 — Web Create parity (PICK→FRAME→FILE)

Media-first three-beat flow on web mirroring mobile: full-bleed pick grid (drag-drop + file
picker), canvas-based FRAME editor (crop/rotate, token aspect presets Tall 0.62 / Square 1 / Wide
1.6 / Original, live masonry-tile preview), compact FILE step with inline shelf/group creation
that returns to the flow; defer uploads to save (upsert paths make re-crop cheap).

## M-ID — App identity (rides in M1)

"K + shelf" mark: single-story grotesque K whose lower leg flattens into a shelf plane, oxblood on
noir. Rendered programmatically to PNG (dart:ui paint → asset), then `flutter_launcher_icons`
generates Android adaptive (foreground/background/monochrome) + iOS set; web `icon.tsx` +
`apple-icon.tsx` redrawn with the same glyph. Also: `flutter_local_notifications` + the required
Gradle desugaring flags (validated on this machine's memory-tuned config) for
backgrounded-but-running display. **FCM real push stays gated** on the user creating a Firebase
project (google-services.json + service-account secret); the deployed `push-fanout` edge function
source gets recovered via MCP and committed.

## Deferred (visible, not forgotten)
Web group create/manage · per-message delete-for-me · delivered ticks · quote-counts-as-repost ·
TURN server · Play Store listing · full offline reading beyond first-page cache.

## Ship gate
verify.sh all green (sequential phases) → APK v1.3.0 → release (site `latest` URL auto-serves) →
push → Vercel redeploy → live smoke → PROJECT_STATE update.
