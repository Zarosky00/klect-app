# REDESIGN PLAN — "Kill the generic" pass

> Written 2026-07-26 from a 4-agent audit (web-mobile, mobile design, create flow, pulse).
> User decisions locked: **oxblood red** accent (no gradients) · **sharp editorial serif + neutral
> grotesque** type · **full algorithmic For-you** · **crop/rotate/presets** photo editor.
> Execution order: B1 ∥ B2 → B3 → B4 → B5m (mobile chain) while B5w → B6 (web chain) → B7 verify+ship.

## B1 — Backend: migration `0018_pulse_first_class.sql` (author → apply → smoke → regen types)

1. **`post_media`** table mirroring `item_media` (id, post_id FK, user_id, storage_path, width,
   height, blurhash, position); RLS owner-write / `can_view_entity('post', …)` read; extend the
   `media` bucket path policy for `{user_id}/posts/{post_id}/…`.
2. **`create_post` RPC** — the only insert path for posts: `p_body`, `p_kind` (post|quote|reply),
   `p_entity_type/p_entity_id` (share a collection/subcollection/item OR quote a post via
   `entity_type='post'`), `p_media jsonb` (array of uploaded descriptors → post_media rows),
   `p_reply_to`. Validates visibility, blocks, suspension; returns the full post envelope.
3. **`pulse_feed` rewrite**: fix the LIMIT-after-jsonb_agg bug (limit inside the union subquery);
   add `p_mode text default 'following'` — `'foryou'` ranks by engagement (like/repost/comment
   counts with time-decay) + viewer tag-taste match + author diversity cap, excluding blocked/muted;
   embed the target payload server-side (quoted post's body/author/media; entity title/cover) so
   clients stop resolving attachments client-side — this also fixes "repost of a post renders empty".
4. **Hardening**: revoke INSERT on all counter columns from `authenticated` on posts (audit
   collections/subcollections/items/comments for the same gap); revoke direct INSERT on posts
   (create_post is the path). Follow 0012 posture (definer, pinned search_path, named grants).
5. Apply via Supabase MCP, smoke under JWT impersonation (create post w/ media descriptor, quote a
   post, foryou vs following ordering, LIMIT respected), `get_advisors`, regenerate
   `web/src/lib/database.types.ts`, update `BACKEND_API.md` §2/§4.

## B2 — Rebrand: tokens + fonts (single source: `packages/tokens/tokens.json`)

- **Colour**: replace the amber family with **oxblood** — dark accent ≈ `#A6323F` ramp (hover
  lighter, subtle at low alpha), light theme deeper ≈ `#7C2531`; update **every** amber-carrying
  token: `accent.*`, `action.save(+Subtle)`, `match.peak`, `border.focus`, `elevation.glow`, and
  re-derive `text.onAccent` (ivory). `semantic.warning` stays amber — it's a warning colour, not
  brand. **Delete gradient usages of accent** (grep both apps). Verify WCAG AA for onAccent text
  and accent-on-surface at both themes.
- **Type**: display = **Fraunces** (opsz/soft axes, editorial bite), UI = **Instrument Sans**;
  mono unchanged. **Bundle TTFs in `mobile/` via pubspec `fonts:`** (kills the Roboto first-paint
  and the runtime google_fonts fetch), keep exact weights (450/550/650 via variable-font
  `FontVariation` or nearest static, consistently). Web: `next/font/google` with the same pair,
  `display: swap`. Update `tokens.json` font families + `DESIGN_SYSTEM.md`, run `node
  packages/tokens/build.mjs`, commit regenerated Dart+CSS+TS together (AGENTS.md rule 6).

## B3 — Mobile: bug fixes + depth (sequential after B2 lands in tokens.g.dart)

1. **Surf header overlap**: `k_app_bar.dart` — titlePadding.bottom += `bottom.preferredSize.height`;
   fade subtitle with collapse progress (read `FlexibleSpaceBarSettings` like profile's
   `_CollapsedTitle`).
2. **Profile bio bleed**: wrap `_ProfileAppBar` flexibleSpace in `ClipRect` + `BackdropFilter`
   (`Blurs.chrome`) like every other glass surface.
3. **Image loading**: `k_blurhash_image.dart` — failure chip over blurhash when `failed`, tap
   error state to evict+retry, bounded-retry CacheManager.
4. **Settings depth**: grouped inset sections (one surface container per section, hairline
   dividers), tinted icon chips, profile hero row, use surface tiers 2/3 + elevation tokens.
5. **Cover-orphan bug**: `cover_field.dart` uploads on pick with no journal — defer upload to save
   (or journal + reconcile like item media).

## B4 — Mobile: Create redesign (media-first, after B3)

- **Flow inversion — 3 beats**: (1) **PICK** — Create tab opens a full-bleed recents grid with
  live camera tile + multi-select counts (entity choice collapses to an intent row, defaulting to
  Item); (2) **FRAME** — per-photo editor: pinch/drag **crop** with preset chips driven by tokens
  (Tall = `Aspect.gridMin` 0.62 · Square 1.0 · Wide = `Aspect.gridMax` 1.6 · Original) + quarter
  rotate + **live masonry-tile preview** ("this is your card on Surf"); (3) **FILE** — one compact
  sheet: title, destination (shelf›group inline creation *returning to the flow* — fixes the
  stranding bug), visibility; details collapsed behind "Add details".
- **Cropper**: pure Flutter — thread `Rect? cropRect` + quarterTurns through `UploadTask` into the
  existing `_prepareSync` isolate (`img.copyCrop` after `bakeOrientation`, before `copyResize`) —
  single decode, blurhash/dimensions stay correct, re-crop before save is free. No native plugins.
- Hoist `MediaUploadController` to a keepAlive provider keyed by draft (uploads survive
  navigation); parallelise save round-trips; purge dev copy ("2048px… quality 82" → human words).
  KEEP: upload journal/WAL, permission UX, item-row-first ordering.

## B5 — Pulse: X parity (mobile B5m after B4; web B5w parallel with mobile chain)

- **Composer (both clients)**: text posts (finally, on mobile), image attach (→ `media` bucket →
  `create_post` p_media), entity share card, quote mode pre-filled from the repost chooser.
- **Repost pill → chooser**: X-style sheet — Repost / Quote / Undo (mobile `k_action_bar.dart`,
  web `ActionBar.tsx`). Quote opens the composer with the subject embedded.
- **Tabs**: For-you ▸ Following segmented header, per-tab cursors, `pulse_feed(p_mode)`.
- **Cards**: render embedded targets from the new envelope (quoted-post card with author+media;
  entity cards with covers). Post closeup shows the attached entity/quote.
- **Comments to X quality**: batched viewer-like seeding (fixes mobile viewerLiked bug), load-more
  pagination, Top/Newest sort, reply collapse; comment pill opens post closeup on web (today it's
  dead — quick fix ships first).
- **Motion**: staggered entrance via `KMotion.staggerDelay`, composed-post slide-in, like burst;
  respect reduced-motion. Web: CSS entrance equivalents.

## B6 — Web mobile responsiveness (parallel with mobile chain, after B5w)

1. **Nav**: Messages reachable (bottom bar rework: Surf·Pulse·Create·Alerts·Messages + top-bar
   avatar menu → Profile/Settings/Admin/theme/sign-out) — fixes "options aren't available".
2. **Inputs ≥16px** on touch (stops iOS focus-zoom "pinch zoom" complaint) — bump field text to
   16 via a touch media query, don't lock user scaling (a11y).
3. **Touch affordances**: tiles/EntityCards get always-visible-on-coarse-pointer caption + action
   row (`pointer: coarse` media), `-webkit-touch-callout: none` on pressables so long-press peek
   wins over iOS image sheet; message-bubble actions get a tap-to-reveal/long-press path.
4. **Closeup on phones**: full-screen `dvh` sheet instead of 92vw dialog.
5. **Safe areas**: top inset padding on sticky bars.
6. **Chat parity quick wins**: overflow menu gains mute/pin/archive/block/report; edit + delete own
   message; admin report-queue buttons visible on touch.

## B7 — Verify + ship

`bash scripts/verify.sh` (phases sequential — parallel builds OOM this 8 GB box) → fix to green →
`flutter build apk --release` → GitHub release v1.1.0 + site button bump → git push → Vercel
redeploy (same bootstrap call) → smoke the live URL → update `PROJECT_STATE.md`.

## Out of scope (recorded, not forgotten)
Full photo filters; web group-management console; delivered-tick tier; TURN server; PWA manifest.
