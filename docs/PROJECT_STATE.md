# KLECT — PROJECT STATE

> **This file is the status board. Read it first. Update it last.**
> Last updated: 2026-07-27 · Session: redesign — rebrand, Create, Pulse X-parity, mobile-web

---

## Status board

| # | Area | State | Notes |
|---|---|---|---|
| 1 | Supabase schema (`new_klect`) | ✅ **DONE & VERIFIED** | 34 tables, 87 RLS policies, 45 triggers, 14 realtime tables, 4 storage buckets. Smoke-tested under real JWT impersonation. |
| 2 | Design tokens (`packages/tokens`) | ✅ **DONE** | `tokens.json` → Dart + CSS + TS. `node packages/tokens/build.mjs`. |
| 3 | Backend API contract | ✅ **DONE** | See `BACKEND_API.md`. All RPCs live and tested. |
| 4 | Flutter mobile app (`mobile/`) | ✅ **DONE (features)** | All feature screens implemented, zero placeholders. Chat upgraded to WhatsApp parity: swipe-to-reply, quote-jump, forward (with storage copy), in-conversation search, full **group chats** (create / add / remove / roles / rename / leave). `flutter analyze` 0 issues, all tests pass. |
| 5 | Next.js web + admin (`web/`) | ✅ **DONE (features)** | All 31 page routes + 3 auth route handlers + sitemap/robots implemented incl. intercepting closeup modal and full `/admin` — zero placeholders. `tsc` exit 0. Group *management* UI is mobile-only for now (web renders groups fine). |
| 6 | Test / build / bug sweep | 🟡 **automated gates ✅ / manual A–H pending** | `verify.sh` fully green 2026-07-26 (tokens 3/3 · mobile pub get/analyze/test/build web · web tsc/lint/build). Manual CHECKLIST.md sections A–H (63 seen-it-work items) still to walk through. |
| 7 | Chat upgrade (`CHAT_PLAN.md`) | ✅ **DONE & VERIFIED** | Migration **0017 applied to live DB** + all 5 group RPCs smoke-tested under JWT impersonation (incl. owner auto-transfer). Advisors: 0 ERROR. `database.types.ts` regenerated. |
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

---

## Next actions

1. Walk through manual sections A–H of `CHECKLIST.md` (63 items — gestures, optimistic social
   mechanics, realtime chat/calls incl. the new groups, moderation flows, RLS from a second
   account, craft). Section I is automated by `verify.sh` and is green.
2. Web parity for chat management (edit/pin/mute/archive/group admin on web) — deliberate gap.
3. ~~Optional platform proof: `flutter build apk`~~ ✅ done — 95.9 MB release APK builds clean.
4. TURN server for reliable WebRTC calls across NATs (still unconfigured).
