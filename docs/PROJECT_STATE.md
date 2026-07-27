# KLECT — PROJECT STATE

> **This file is the status board. Read it first. Update it last.**
> Last updated: 2026-07-27 · Session: Pinterest follow panel + X-style quote composer · shipped as v1.4.2

---

## Status board

| # | Area | State | Notes |
|---|---|---|---|
| 1 | Supabase schema (`new_klect`) | ✅ **DONE & VERIFIED** | 34 tables, 87 RLS policies, 45 triggers, 14 realtime tables, 4 storage buckets. Smoke-tested under real JWT impersonation. |
| 2 | Design tokens (`packages/tokens`) | ✅ **DONE** | `tokens.json` → Dart + CSS + TS. `node packages/tokens/build.mjs`. |
| 3 | Backend API contract | ✅ **DONE** | See `BACKEND_API.md`. All RPCs live and tested. |
| 4 | Flutter mobile app (`mobile/`) | ✅ **DONE (features)** | All feature screens implemented, zero placeholders. v1.4.2 adds the wide avatar-led follow outcome panel and a full-screen, keyboard-safe X-style quote composer with immutable original previews plus up to four editable commentary photos. Native tap feedback remains centralized; sound defaults on and haptics now default off while explicit preferences persist. `dart analyze` 0 issues, 113 tests pass. |
| 5 | Next.js web + admin (`web/`) | ✅ **DONE (features)** | All 32 page routes + 3 auth route handlers + sitemap/robots implemented incl. intercepting closeup modal and full `/admin` — zero placeholders. v1.3.1 adds responsive profile/composer polish and `/settings/app`. Group *management* UI is mobile-only for now (web renders groups fine). |
| 6 | Test / build / bug sweep | 🟡 **automated gates ✅ / manual A–H pending** | 2026-07-27 gates green: mobile analyze + 113 tests + clean v1.4.2 APK; web 9 tests + tsc + lint + production build. Manual CHECKLIST.md sections A–H (63 seen-it-work items) plus real-device follow-panel, quote-composer, keyboard, native-click, and optional-haptic feel still need to be walked through. |
| 7 | Chat upgrade (`CHAT_PLAN.md`) | ✅ **DONE & VERIFIED** | Migration **0017 applied to live DB** + all 5 group RPCs smoke-tested under JWT impersonation (incl. owner auto-transfer). Advisors: 0 ERROR. `database.types.ts` regenerated. |
| 9 | Round 3 (`ROUND3_PLAN.md`) | ✅ **DONE & VERIFIED — v1.3.0** | **P0s**: 0019 slug autogen + 0020 RLS insert-returning (onboarding shelf creation was broken since 0001/0008 — fixed live, no app update needed); 7 phantom seed covers repaired. **0021 applied** (preflight caught+fixed a private-account search leak): `get_post_thread`, `user_posts`, comment save/repost counters, composite feed cursor + has_more, For-you window ladder, post search. Web perf overhaul (next/image, windowed masonry, glass-per-tile removed, ref-driven viewer). Thread-first Pulse both clients (X thread pages, comment action bars, filter drawer + post search, profile Posts tabs, Pulse/Surf gesture split). Share chooser w/ Send-to-a-friend both clients; dead `klect.app` links fixed via KLECT_WEB_ORIGIN dart-define. Notifications: shell-level realtime + banners + tray (desugaring) + live badges; push-fanout edge fn source recovered; FCM gated on user's Firebase project. K+shelf app icon all densities. Web Create = PICK→FRAME→FILE with canvas cropper (1:1 crop math with mobile). verify.sh all green; APK v1.3.0 released; Vercel deployed. |
| 8 | Redesign (`REDESIGN_PLAN.md`) | ✅ **DONE & VERIFIED** | **0018 applied** (post_media, `create_post`, For-you feed, LIMIT/empty-repost fixes, counter INSERT hardening; 6 smoke assertions green). Oxblood rebrand + bundled Fraunces/Instrument Sans. Mobile: header/bleed/image bugs fixed, settings depth, media-first Create + cropper, Pulse X-parity. Web: create_post composer (fixed live 42501), quote chooser, For-you tabs, full mobile-responsiveness pass. All verify.sh phases green 2026-07-27. |

**Verification (actually run, not assumed — full sweep 2026-07-26):**
- `bash scripts/verify.sh` **all green**: tokens 3/3 (one warn-only hex in the blurhash decoder,
  legit math not a design value) · mobile `pub get` / `analyze` (0 issues) / `test` (all pass) /
  `flutter build web --release` · web `tsc --noEmit` / `next lint` / `next build` (31 routes).
- ⚠ Machine quirk: running `flutter build web --release` and `next build` **concurrently** starves
  the workers and both can crash spuriously (Next worker exit 0xC0000409, dart2js "failed to
  compile"). Each passes cleanly in isolation — run the verify phases sequentially on this machine.
- Riverpod 3's `NotifierProvider.family` **does** accept a constructor arg (`InteractionController.new`
  taking `EntityRef`) — verified by compilation, in case it looks wrong to you.

**v1.3.1 verification (2026-07-27):**
- Mobile: `flutter analyze --no-pub` **0 issues**; complete `flutter test --no-pub`
  **84/84 passed**; release APK verified as `com.klect.klect`, version `1.3.1` / code `5`,
  SHA-256 `6b862bb3baa0fdc2eba1f85ec4edff48d124e28f56a93b8069fcd7a79d8e28db`.
- Web: Vitest **9/9**, `tsc --noEmit`, `next lint`, and `next build` all green.
  Production deployment `dpl_21gAWwZgzMzVphpY4vZvvWWEdeN5` is **READY** at
  `https://klect-web.vercel.app`; post-deploy error/fatal log scan and Chrome console are clean.
- Mobile-width production check at 390×844: profile document width equals viewport width,
  avatar is fully visible, stats use a 2×2 grid, and the five-section tab rail scrolls horizontally.
- GitHub release `v1.3.1` is published with `klect.apk`; the stable
  `releases/latest/download/klect.apk` URL resolves with HTTP 200 and the correct APK MIME type.

**v1.4.0 verification (2026-07-27):**
- Mobile: `dart analyze` **0 issues**; complete `flutter test` **100/100 passed**; release APK
  verified as `com.klect.klect`, version `1.4.0` / code `6`, SHA-256
  `a0222a8641254a3fadecae0a3c5300a52008e2304497b8997e5099dd1d4219a6`.
- GitHub release `v1.4.0` is published from commit `0e0d6eb` with the required `klect.apk` asset.
  The public latest-release API reports the expected tag, APK MIME type, byte size, and digest;
  `releases/latest/download/klect.apk` follows through to HTTP 200.
- The existing Android update checker and website download button both use that stable URL, so
  no Supabase or Vercel change was required. Physical normal/vibrate/silent-mode feel testing
  remains pending because no Android device was attached to the build machine.

**v1.4.1 verification (2026-07-27):**
- Mobile: `flutter analyze --no-pub` **0 issues**; complete Flutter test suite **107/107 passed**;
  clean release APK verified as `com.klect.klect`, version `1.4.1` / code `7`, min SDK 24,
  target SDK 36, SHA-256
  `05f50ef7184025ac17516084d2e5317dc396b0827192da14bfeae41a730a15b8`.
- PR **#1** was merged to `main` at commit `14cff3e9c21a417d633590a470853af09e41f4ab`.
  GitHub release `v1.4.1` is published with `klect.apk` (102,134,307 bytes,
  `application/vnd.android.package-archive`); GitHub's asset digest matches the local clean build.
  `releases/latest/download/klect.apk` follows through to HTTP 200.
- APK inspection found no bundled feedback audio or `audioplayers` artifacts. The existing update
  checker and website download button continue to use the stable latest-release URL, so no
  Supabase or Vercel change was required. Physical normal/vibrate/silent-mode, touch-sounds,
  hardware/gesture-back, and music-playback checks remain pending because no Android device was
  attached to the build machine.

**v1.4.2 verification (2026-07-27):**
- Mobile: `dart analyze` **0 issues**; complete Flutter test suite **113/113 passed**; clean release
  APK verified as `com.klect.klect`, version `1.4.2` / code `8`, min SDK 24, target SDK 36,
  size 102,314,499 bytes, SHA-256
  `699d602114788c19f25d226bb5ab3f4cf0fd9843dd80c92527df7fca1930fdbb`.
- PR **#2** was merged to `main` at commit `f05d7e8b94ca60fd43d58f6a409ea728669293f0`.
  GitHub release `v1.4.2` is published with the required `klect.apk` asset and
  `application/vnd.android.package-archive` MIME type. The latest-release API reports the expected
  tag, filename, size, state, and digest; the stable `releases/latest/download/klect.apk` URL
  follows through to HTTP 200.
- A fresh download of the public asset matched the local clean build byte-for-byte. APK inspection
  reconfirmed version `1.4.2+8` and found no custom WAV/MP3/OGG or `audioplayers` artifacts.
  No Supabase schema, Vercel, or web changes were required. Physical Gboard, small/large text,
  dark/light theme, offline queueing, avatar-failure, and first-launch haptic checks remain pending
  because no Android device was attached to the build machine.

Legend: ✅ done · 🟡 in progress · ⬜ not started · 🔴 blocked

---

## Verified facts (do not re-derive these)

**Supabase project `new_klect`**
- ref `dikhuygcwxnrsckqglzg` · region ap-southeast-2 · Postgres 17
- URL `https://dikhuygcwxnrsckqglzg.supabase.co`
- publishable key `sb_publishable_nwJjxG8yJ01lTjrv6pXQww_mQ9MNq5t`
- The service-role key is **not** in this repo and must never be. Server-only work uses edge functions.

**Migrations applied** (16, in order) — see [`../supabase/README.md`](../supabase/README.md) for the
table of what each one does. `0001`–`0012` build and harden the schema; `0013` adds FK indexes and
splits overlapping policies; `0014` seeds demo content; `0015` adds feed type-interleaving; `0016`
adds match caching + a nightly `pg_cron` maintenance job.

**Demo data already in the database** — the surf feed returns a full, realistic grid:

8 users · 8 collections · 13 subcollections · 52 items · ~100 photos · ~700 likes/saves/reposts ·
follows, views, comments and posts. Enough that the masonry, counts, matching and Pulse feed all
render like a live product.

| user | id | note |
|---|---|---|
| `aria` | `1111…1111` | Anime > JJK / One Piece, **plus a private collection for RLS testing** |
| `kenji` | `2222…2222` | Resin Shelf; follows aria; has liked/saved/reposted/commented |
| `klectmod` | `3333…3333` | has the **`moderator`** role → sees the admin console |
| `noor` `silas` `mira` `dev` `yuki` | `4444…44441`–`5` | cameras, vinyl, plants, tech, cards |

These were seeded directly into `auth.users`, so they have **no usable password**. To sign in as one,
set a password in the Supabase dashboard (Authentication → Users), or just sign up fresh — the
signup trigger creates the profile automatically.

Remove all demo content at any time with:
```sql
delete from auth.users where email like '%@klect.test';
```

> ⚠️ **Demo images are absolute `https://picsum.photos/...` URLs, not Storage keys.**
> Both clients must route every image through one helper that uses the value verbatim when it starts
> with `http`, and calls `getPublicUrl()` otherwise. This is specified in `BACKEND_API.md` §4.

**Toolchain on this machine**
- Node 24.16, npm 11.13 — `D:\D drive\coding\Ideas\hackathon`
- Flutter stable 3.44.8 + Dart 3.12.2 at `C:\src\flutter` (web enabled)
- **JDK 17.0.19** at `C:\dev\jdk-17.0.19+10` · **Android SDK 36** at `C:\dev\android-sdk`
  (build-tools 36.0.0, platform-tools, all licences accepted). `flutter doctor` shows
  **`[√] Android toolchain`** — so **`flutter build apk` works on this machine.**

  Environment for any Android build:
  ```bash
  export JAVA_HOME=/c/dev/jdk-17.0.19+10
  export ANDROID_HOME=/c/dev/android-sdk
  export PATH="/c/src/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
  ```
- ❌ **iOS `.ipa` cannot be built here and never will be** — Apple requires macOS + Xcode. Use a Mac,
  or a cloud macOS runner (Codemagic / GitHub Actions `macos-latest`). The Dart is platform-correct.
- ❌ Visual Studio absent → Windows *desktop* target unavailable. Irrelevant; we target iOS/Android/web.

---

## Supabase advisor status

Run `get_advisors` after any migration. Current state:

| advisor | ERROR | WARN | INFO |
|---|---|---|---|
| security | **0** | 51 | 0 |
| performance | **0** | 0 (was 10, fixed in `0013`) | 68 |

**Fixed:** extensions moved out of `public`; every function `search_path` pinned; `EXECUTE` revoked
wholesale then re-granted to a named surface; 28 unindexed foreign keys covered (`0013`); the two
`FOR ALL` policies split so `SELECT` is served by exactly one policy (`0013`).

**Accepted WARNs, with reasons:**

- *`{anon,authenticated}_security_definer_function_executable` (50).* These are (a) the intended
  public RPC surface — `surf_feed`, `toggle_like`, `admin_*` etc., which is the whole point — and
  (b) the RLS predicate helpers (`can_view_entity`, `visible_to_me`, `entity_owner`, `is_staff`, …).
  Policy expressions are evaluated with the **caller's** privileges, so those helpers *must* remain
  executable or every policy on the database breaks. Each admin RPC re-checks `is_staff()`/`is_admin()`
  internally, so REST-reachability grants nothing.
  Residual risk, stated plainly: `entity_owner` and `entity_counter` will answer for an entity you
  cannot otherwise see — but only if you already hold its UUID, which is unguessable and never
  emitted for hidden content. If you later want this closed, move just those two into a schema
  PostgREST doesn't expose and update the ~6 plpgsql bodies that call them by name (policies store
  OIDs and will follow the move automatically).
- *`auth_leaked_password_protection` (1).* **Action required from you** — this is a dashboard setting,
  not SQL. Enable it at
  Authentication → Providers → Email → "Prevent use of leaked passwords" in the Supabase dashboard.

**INFO `unused_index` (40)** is expected: the database has no production traffic yet, so nothing has
touched the search/trigram/feed indexes. Re-check once real usage exists before dropping anything.

## Known limitations & open decisions

1. **Figma MCP is not authorized** in this session (non-interactive OAuth). The design system is delivered
   as code (`packages/tokens`) plus `DESIGN_SYSTEM.md`. If you get Figma access, push tokens with
   `figma-generate-library`; do not re-invent values.
2. **iOS/Android release builds** need a Mac (iOS) and a JDK+Android SDK (Android). The Flutter source is
   written to be platform-correct; CI or a dev machine with those SDKs can build it unchanged.
3. **Calls** use WebRTC with Supabase Realtime as the signalling channel (`call_signals` table +
   `calls` row state). A TURN server is required for reliable connectivity across NATs — none is
   configured yet. Add credentials in the client config when you have one.

---

## Session log

### 2026-07-26 — initial build
- Explored env; found prior `Klecto` project (v1 schema) and used it as a blueprint, not a base.
- Chose Flutter/Dart for mobile (Impeller = jank-free 120fps masonry) and Next.js/TS for web (SEO + RSC).
- Authored and applied 12 migrations to `new_klect` from empty.
- Fixed 3 real bugs during schema work:
  - non-IMMUTABLE expression in a notification index → replaced with a bump-on-repeat dedupe strategy;
  - a counter "guard trigger" that would have fought the counter triggers → replaced with column-level GRANTs;
  - `ORDER BY/LIMIT` inside UNION branches → parenthesised subqueries.
- Hardened per the Supabase advisors: extensions moved out of `public`, every function search_path pinned,
  `EXECUTE` revoked wholesale then re-granted to a small, named RPC surface.
- Smoke-tested: signup trigger, structural counters, all four toggles, comment fanout, notification dedupe,
  report dedupe, RLS isolation (private collection invisible to another user), anon SEO browsing,
  counter tamper-resistance, admin metrics + report queue.

---

### 2026-07-26 — status audit (post feature build)
- Audited every feature surface in both apps (3 parallel agents, file-by-file reads, not filename guesses):
  - `mobile/`: all 31 `*_screen.dart` + `root_shell.dart` across 12 feature folders are real
    implementations wired to Riverpod providers → `KlectApi`/Supabase. Zero placeholders.
  - `web/`: all 31 page routes, 3 auth route handlers, sitemap/robots implemented, incl. the
    `@modal/(.)closeup` intercepting route and the 5 `/admin` consoles. Zero placeholders.
- Re-ran the compile gates: `flutter analyze` = 1 test-file warning (lib clean); `tsc --noEmit` = exit 0.
- Rows 4 and 5 flipped to ✅; row 6 (verification sweep) is the only open work.

### 2026-07-26 — chat upgrade + verification sweep
- Fixed the mobile report bug (free text was sent as `p_message`, which is the reported-message
  **uuid** arg; now goes to `p_details` matching web) and the last analyzer warning.
- Wrote `docs/CHAT_PLAN.md` (audit-derived gap list + the group RPC contract) and implemented it:
  - **0017_group_chats** authored AND **applied to the live DB** (Supabase MCP became available
    mid-session). Five RPCs — `create_group`, `add_group_members`, `remove_group_member`,
    `update_group_info`, `set_group_member_role` — smoke-tested under JWT impersonation as `aria`:
    create → add → promote → remove → rename → owner-leave-with-transfer, all passed, test data
    rolled back. Advisors after DDL: 0 ERROR (the 5 new WARNs are the accepted RPC-surface class).
  - Mobile: swipe-to-reply (56px token trigger + haptic), quote-tap-to-jump (10-page history cap +
    highlight pulse), forward (multi-select picker; image attachments **copied** in the private
    `chat` bucket so recipients can read them), in-conversation search (server-side `ilike`,
    highlighted snippets, jump-and-pulse), and the full group UI (`NewGroupScreen` + `MemberPicker`,
    `GroupInfoScreen` with role management, group-aware thread/header/realtime member refresh).
  - `web/src/lib/database.types.ts` regenerated (adds the 5 group RPCs + two entries 0016 had
    missed: `get_matches.p_force`, `nightly_maintenance`).
- Deleted `test/_tmp_create_media_check_test.dart` — a leftover "TEMPORARY, delete after run"
  scratch harness from an earlier session, failing on a wrong blurhash expectation.
- Ran the full `verify.sh` sweep to green (see Verification above).
- Still deferred from the chat plan: per-message delete-for-me, "delivered" tick tier, last-seen
  outside an open thread, full emoji picker, web group-management parity.
- **Chat discoverability fix:** the inbox had no entry point in the mobile chrome — added
  `MessagesAction` (chat-bubble icon + realtime unread badge off `unreadMessageCountProvider`) as
  the trailing app-bar action on both Surf and Pulse. Web: Messages/Alerts/profile are auth-only
  nav items by design; they appear after sign-in.
- **APK distribution:** the release APK is downloadable from the website — hero button
  "Get the Android app" + footer link on `/`, serving `web/public/downloads/klect.apk`
  (re-copy after every `flutter build apk`). New `download` icon added to the web icon set.
- **Local serving:** `npm --prefix klect/web run start` on port 3112 (`.claude/launch.json`,
  autoPort). If 3112 is squatted by an orphaned `next start-server.js` from a dead session, kill
  that node process rather than hopping ports.
- **GitHub:** https://github.com/Zarosky00/klect-app (public, `main`). NOTE: the account's older
  *private* `klect` repo (pushed 2026-06-10) is unrelated prior work — never push there.
  APK ships as a release asset: https://github.com/Zarosky00/klect-app/releases (v1.0.0,
  `klect.apk`); the site's download button points at it. `web/public/downloads/` is gitignored.
- **Vercel (production):** https://klect-web.vercel.app — project `klect-web` under team
  `ak-ash-s-projects` (`team_JvJqCf8EOWaYD7AOSrPIvvMx`). Deployed via a bootstrap shim (the MCP
  deploy tool takes inline files, too small for the real tree): install command clones
  `klect-app`, copies `web/` over the stub, then `npm install` + `next build` in Vercel's cloud.
  `.env.production` (public values only) rides in the shim, NOT in git. Redeploy = re-run the
  same deploy call; it re-clones latest `main`.
  ⚠ Pending user action: add `https://klect-web.vercel.app/**` to Supabase dashboard →
  Authentication → URL Configuration (Site URL + Redirect URLs) so auth emails link to prod.
- **Platform proof:** `flutter build apk --release` → `app-release.apk` (95.9 MB) ✅, and the
  production web build served locally via `next start` renders live DB content with zero console
  errors ✅. Two machine fixes were needed for the APK (this box has **8 GB RAM**): Gradle heap
  right-sized in `mobile/android/gradle.properties` (template's `-Xmx8G` exceeded physical RAM and
  crashed the daemon with a native OOM) and `kotlin.incremental=false` (its cache files hit Windows
  file-lock errors). Both fixes are committed with comments in that file.

### 2026-07-27 — redesign session (`REDESIGN_PLAN.md` executed in full)
- 4-agent audit grounded the plan; user locked: oxblood accent, Fraunces+Instrument Sans, full
  algorithmic For-you, crop/rotate/presets editor.
- **0018_pulse_first_class applied live** (dry-run-validated first in a rolled-back transaction):
  post_media, `create_post` (sole insert path), `pulse_feed` p_mode following|foryou with
  server-embedded targets, LIMIT + empty-repost + viewer_reposted bugs fixed, counter-INSERT
  hardening. Smoke: 6/6 under JWT impersonation. Advisors 0 ERROR (+1 accepted WARN).
- **Rebrand**: oxblood ramps with per-surface WCAG checks (focus ring moved to the hover step to
  clear 3:1 on dark), fonts **bundled** (variable TTFs + OFL licences, FontVariation exact
  450/550/650 weights), the one accent gradient flattened, web on next/font.
- **Mobile**: Surf-header overlap + profile bio-bleed root-caused and fixed; KImageCache
  bounded-retry + tap-to-retry chip; settings rebuilt with depth (section islands, icon chips,
  hero row); cover-orphan bug fixed (PendingCover uploads at save, not pick); Create inverted to
  PICK→FRAME→FILE with a pure-Flutter cropper (token aspect presets + live masonry preview),
  keep-alive uploads, un-stranded inline shelf creation; Pulse: createPost API, rebuilt composer
  (text/photos/entity/quote), Repost|Quote|Undo chooser, For-you|Following tabs, paged/sorted
  comments with batched viewer-likes (fixes the always-false viewerLiked), stagger motion.
- **Web**: composer moved to `create_post` (un-broke live posting), photos+entity+quote parity,
  For-you tabs, envelope target cards, comment pill fixed (was dead), comments upgrades; nav
  rework (Messages in bottom bar, avatar sheet for Profile/Settings/Admin), 16px `input` token
  kills iOS focus-zoom, touch-visible tile/bubble actions, `-webkit-touch-callout` fix,
  full-screen dvh closeup on phones, safe-area top, chat overflow parity (mute/pin/archive/
  block/report + edit/delete own message), admin report actions touch-visible.
- All verify.sh phases green (web phase re-run first-pass green; mobile 4/4). Production Vercel
  redeployed mid-session to un-break posting. Site APK button now points at
  `releases/latest/download/klect.apk` (stable across future releases).
- **In-app update checker shipped as v1.2.0** (`lib/core/updates/`, banner in root shell):
  Android-only, checks `releases/latest` at most every 6h with cached fallback and
  skip-this-version persistence; "Update now" opens the latest-release APK in the browser
  (deliberate: no REQUEST_INSTALL_PACKAGES/FileProvider plumbing). `kAppVersion` in
  `lib/core/app_version.dart` must move in lockstep with pubspec.yaml + the release tag —
  releasing without bumping all three breaks the banner logic. 15 tests cover it.

### 2026-07-27 — mobile/web usability patch (v1.3.1)
- Fixed the Android profile clipping shown in device screenshots by keeping the avatar inside
  the header sliver's paint bounds. Replaced fixed stat gaps with four equal columns and made
  five-tab profiles horizontally scrollable, so long names/counts/tabs no longer collide.
- Rebuilt the mobile Pulse composer as scrollable content plus a fixed action bar. `Add photo`
  and `Quote`/`Post` remain visible at phone height and with the keyboard open; quote target
  previews and selected photos stay in the scrollable section. Added a regression widget test.
- Added Settings → App → **Check for updates**. Manual checks bypass the background six-hour
  throttle and skipped-version preference, and clearly report update available / current /
  unavailable. About now reads the shared version constant instead of a stale hardcoded `1.0.0`.
- Web parity: responsive profile name/stats/tab rail; labeled composer media actions and a real
  `Quote` label; new `/settings/app` page explains automatic web updates and links the latest APK.
- Released Android `v1.3.1`, pushed `main`, configured the three required public Vercel production
  environment variables, and deployed the verified web build to production. No Supabase schema
  or data changes were required.

### 2026-07-27 — native tap feedback correction (v1.4.1)
- Removed `audioplayers`, the seven custom WAV cues, sound generation tooling, preloading, gain
  policy, and action-specific audio mapping. Android now uses `SystemSoundType.click`; iOS follows
  platform convention with selection haptic only. Separate persisted sound/haptic preferences
  remain enabled by default.
- Centralized the effect at accepted UI-control boundaries (`KPressable`, `KGestureRegion`, KLECT
  app-bar back buttons, tabs, images/cards, settings inputs, filters, retry/action controls).
  Disabled/busy controls, scrolling, dragging, system back, edge gestures, route restoration,
  server confirmation, queued replay, rollback, and background synchronization add no effect.
  Comments and replies now receive the same single accepted-tap response.
- Replaced the large follow card with a compact top-right pill using one-line contextual copy,
  small status glyphs, timed slide/fade presentation, reduced-motion fallback, live-region
  semantics, and tap/upward/horizontal dismissal. Like/save/repost success stays toast-free.
- Added controller, platform-channel, shared-control, nested-duplicate, app/system-back, social,
  comment/reply, and compact-toast coverage. Released the verified Android build as `v1.4.1`
  through PR #1.

### 2026-07-27 — Pinterest follow panel + X-style quote composer (v1.4.2)
- Replaced the compact follow pill with a centered, near-full-width inverse-surface panel that uses
  the target profile avatar or initials, contextual follow/unfollow/queued/error copy, safe-area
  placement, live semantics, reduced-motion support, timed entrance/exit, and gesture dismissal.
- Rebuilt Pulse posting and quoting as one full-screen, keyboard-safe composer with a fixed header
  and media toolbar, scrollable draft content, immediate preloaded quote data with provider
  fallback, X-style immutable original cards, complete 1–4 image grids, and unavailable tombstones.
- Commentary now accepts up to four photos with original-byte retention, crop presets,
  quarter-turn rotation, image-pipeline reprocessing, horizontal reordering, individual removal,
  preparation indicators, retryable failures, and the unchanged `create_post` contract.
- Haptics now default off while sound defaults on and explicitly persisted choices remain intact.
  Added follow-panel golden/widget coverage, keyboard-inset and quote-preview regressions, and
  preference tests. Released the verified Android build as `v1.4.2` through PR #2.

### 2026-07-27 — in-app sideload updater (pending merge and release)
- Built in an isolated sibling worktree on `agent/in-app-apk-updater`, leaving the active social /
  redesign checkout, branch, index, and uncommitted files untouched.
- This supersedes the earlier browser-download behavior: GitHub release checks now require a
  successfully uploaded `klect.apk` asset and cache its direct HTTPS URL, expected byte count, and
  SHA-256 digest. Old cached release metadata remains compatible through the stable latest URL.
- "Update in KLECT" streams the APK to private cache with visible progress, rejects truncated or
  digest-mismatched files, and opens Android's system installer through a narrowly scoped,
  non-exported FileProvider. If needed, Android first opens the per-app "Allow from this source"
  setting; after returning, the already verified APK is reused via "Continue install".
- Validation: `flutter analyze --no-pub` 0 issues; complete Flutter suite 116/116 passed; clean
  Android release APK compiled and packaged successfully with the expected
  `REQUEST_INSTALL_PACKAGES` permission and `com.klect.klect.update_file_provider` authority.
  Physical-device permission, install, replacement, and restart behavior remains to be verified
  after this branch is merged into a version newer than v1.4.2 and released with the same signer.

---

## Next actions

1. Install v1.4.2 on a real Android phone and verify the wide avatar follow panel, every
   follow/unfollow/queued/error state, quote preview loading, four-photo edit/reorder/remove flow,
   and composer layout with Gboard open at small/large text sizes in dark/light themes. Confirm
   haptics start disabled for a fresh install, explicit sound/haptic preferences persist, offline
   queueing behaves correctly, avatar failures fall back to initials, and Settings → Check for
   updates reports v1.4.2 is current.
2. Walk through manual sections A–H of `CHECKLIST.md` (63 items — gestures, optimistic social
   mechanics, realtime chat/calls incl. the new groups, moderation flows, RLS from a second
   account, craft). Section I is automated by `verify.sh` and is green.
3. Web parity for chat management (edit/pin/mute/archive/group admin on web) — deliberate gap.
4. Triage the current production `npm audit --omit=dev` result (3 high, 0 critical; `next`,
   transitive `postcss` and `sharp`). The registry's proposed fix is an invalid Next.js downgrade,
   so do not apply `npm audit fix --force`; upgrade through a tested supported Next release.
5. TURN server for reliable WebRTC calls across NATs (still unconfigured).
