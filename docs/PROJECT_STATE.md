# KLECT — PROJECT STATE

> **This file is the status board. Read it first. Update it last.**
> Last updated: 2026-07-31 · Session: v1.6.4 released on GitHub and deployed to Vercel

---

## Status board

| # | Area | State | Notes |
|---|---|---|---|
| 1 | Supabase schema (`new_klect`) | ✅ **DONE & VERIFIED** | 38 tables, 93 RLS policies, 14 realtime tables, 4 storage buckets and 37 applied migrations. The live chat/calls/notifications contract now includes synced notification preferences, private message hides, call diagnostics/reasons, 256-member group enforcement, 60/500-character identity validation and identity system messages. `pg_net` is enabled and `notifications_push_fanout_webhook` fires push delivery from an `after insert` trigger. |
| 2 | Design tokens (`packages/tokens`) | ✅ **DONE** | `tokens.json` → Dart + CSS + TS. `node packages/tokens/build.mjs`. |
| 3 | Backend API contract | ✅ **DONE** | `pulse_feed_v2`, `social_engagement_v1`, `profile_pulse_activity_v1`, `profile_discussion_activity_v1`, `my_profile_reactions_v1` and owner-only `delete_post` are live alongside the completed notification/message/group/call RPC contract. Calls remain feature-gated off. |
| 4 | Flutter mobile app (`mobile/`) | ✅ **v1.6.4 SHIPPED** | The required `chat-calls-notifications-overhaul` work is released: Alert Center filtering, call lifecycle/surfaces, message deletion, group enforcement/reporting and shared swipeable tabs. Flutter analysis is clean, all 268 local tests pass, and the public APK is permanently signed. Calls remain feature-gated pending production TURN/device validation. |
| 5 | Next.js web + admin (`web/`) | ✅ **v1.6.4 DEPLOYED** | Production deployment `dpl_AEVhNVxfXGioXKXqYgYa17Ej3vMj` is READY at `https://klect-web.vercel.app`. The public home returns HTTP 200 and its Android button uses the stable latest-release `klect.apk` URL. Group management remains Android-first. |
| 6 | Test / build / bug sweep | 🟡 **automated gates ✅ / physical QA pending** | 2026-07-31: local analysis, 268 Flutter tests, the 145-test focused run, Flutter web, web typecheck, 15 Vitest tests and the 31-route Next build pass. PR #12, merged-main CI and the signed-release workflow are green. Two-account/call relay/background/locked and physical accessibility matrices remain. |
| 7 | Chat upgrade (`CHAT_PLAN.md`) | ✅ **KIRO REQUIRED WORK COMPLETE** | All 49 required implementation tasks in `chat-calls-notifications-overhaul/tasks.md` ship in v1.6.4. The 73 remaining `*` entries are explicitly optional property/widget/SQL proof tasks. Group reporting, send-scope lockout, tombstones/delete-for-me, call pill/system actions and sibling-tab paging are released. |
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

**v1.6.0 verification (2026-07-27):**
- Mobile: `flutter analyze --no-pub` **0 issues**; full Windows suite **116/116 passed**;
  Linux CI suite **115/115 passed** with the Windows raster golden intentionally excluded.
  Both local and GitHub clean release APK builds passed.
- PR **#4** merged to `main` at commit
  `d6eac613090589527cc2255a80c1efc85f5e17a4`. GitHub release `v1.6.0` is published
  with `klect.apk` (102,430,563 bytes, `application/vnd.android.package-archive`).
  A fresh public download verified `com.klect.klect`, version `1.6.0` / code `10`,
  min SDK 24, target SDK 36, no custom audio artifacts, and SHA-256
  `cc0342534817ba808e21f77373959278c28b1308a2d3d925a475e2d989afd1ae`.
- Web: TypeScript, 9 Vitest tests and the production Next.js build passed in CI.
  Vercel deployment `dpl_AUW4gtCweYmEuLD2B99bevYbdYt8` is READY and
  `https://klect-web.vercel.app` returns HTTP 200.
- Supabase: `social_integrity_and_comment_threads`, `messaging_groups_preferences`,
  `reliable_call_state` and `user_preferences_rls_initplan` are applied. `push-fanout`
  v2 and JWT-protected `turn-credentials` v1 are ACTIVE. `reliable_calls` is verified
  **false** until Firebase, TURN secrets, native call integration and two-device testing pass.

**v1.6.1 verification (2026-07-28):**
- PR **#5** merged at `26ce6f98eebce8311f0626137ac50c1b03438783`. Mobile analysis is clean,
  all **118/118** tests pass, both GitHub mobile checks pass, and the clean release build verifies
  as `com.klect.klect`, version `1.6.1` / code `11`, min SDK 24 and target SDK 36.
- Supabase migrations `group_controls_v161` and `group_title_limit_consistency` are live. A rolled-
  back production transaction verified policy-controlled edit/add, invite approval and owner delete;
  anonymous execution of the new owner RPCs is revoked. Advisors remain at 0 ERROR.
- GitHub release `v1.6.1` exposes one `klect.apk` asset (102,582,690 bytes,
  `application/vnd.android.package-archive`), SHA-256
  `14a92813282baa973651ecd1c7f9d155415991906cab4948ce4b2a8dce7ea5ad`. The stable latest URL
  resolves through to HTTP 200, and the public APK was installed and launched on an RMX3771 running
  Android 15; the complete Surf accessibility tree rendered without Flutter errors.
- PR **#6** merged at `95b05b602429db2f59785f656629ef18e97d3f77`. Tagged releases now use
  the permanent certificate SHA-256
  `460d934bcca98539907f82259f803080be55b153e7df0edec5878d4bf11b334f` from GitHub Secrets.
  Releases through v1.6.0 used lost per-run debug keys, so existing old installs require one
  uninstall/reinstall; v1.6.1 and later can update in place with the stable key.

**v1.6.2 verification (2026-07-28):**
- PR **#8** merged at `720d77445e8041607d926bed914f53f689e0362f`. Both GitHub mobile
  checks passed, including clean analysis, all **120/120** Flutter tests and signed release builds.
- Pulse now uses a compact X-style shell and renders rich original targets for reposts and quotes:
  owner identity, text/entity details and bounded one-to-four-image layouts appear in both Pulse
  and Profile Posts. Physical Android 15 checks verified the For You, Following and Profile Posts
  paths with live production data.
- Follow notifications now render through a transparent Material overlay with explicit decoration
  suppression, removing the inherited yellow underline. Calls remain honestly feature-gated off;
  the unusable call controls are hidden until Firebase, TURN and native call prerequisites pass.
- The stable-signed local APK verifies as `com.klect.klect`, version `1.6.2` / code `12`, certificate
  SHA-256 `460d934bcca98539907f82259f803080be55b153e7df0edec5878d4bf11b334f`, and was installed
  in place over USB on the attached RMX3771 without clearing app data.

**v1.6.3 verification (2026-07-28):**
- PR **#10** merged at `f54fe38b326102ccefc91b9f62f4a6e944645374`. Both push and
  pull-request CI runs passed: Flutter analyze, **126/126** local tests, Linux tests, two clean
  release APK builds, web typecheck, **15/15** Vitest tests and production Next.js builds.
- Supabase migration `20260728090703_social_activity_profile` is live. Pre-apply rollback tests
  covered complete repost/quote envelopes, explicit entity quotes, quote-counter reconciliation,
  idempotent owner deletion, RPC grants and multi-page composite cursors. Post-apply authenticated
  smoke checks returned both feeds, engagement summaries, profile posts, unified discussions and
  owner-only reactions. For You and discussion pages measured about 175 ms and 38 ms respectively
  on warm production data. Advisor deltas are limited to the intended guarded `SECURITY DEFINER`
  RPC notices and newly created, not-yet-used indexes; no ERROR was introduced.
- Vercel production deployment `dpl_FpFUXGmyTQ9k2c3MUAv5AJVrMsUR` is READY and aliased to
  `https://klect-web.vercel.app`. The public home and a real profile return HTTP 200; anonymous
  `/pulse` correctly redirects to sign-in.
- GitHub release `v1.6.3` publishes `klect.apk` (102,926,635 bytes,
  `application/vnd.android.package-archive`). A fresh public download verifies as
  `com.klect.klect`, version `1.6.3` / code `13`, min SDK 24, target SDK 36, permanent certificate
  SHA-256 `460d934bcca98539907f82259f803080be55b153e7df0edec5878d4bf11b334f`,
  no bundled custom audio, and SHA-256
  `ffd05b9f0c928223e12683ee4e34f95d94cbfa8ccdc40a38ae29d78d95f4d7e6`.
  The latest-release API and stable asset URL report the same version, MIME type, size and digest.
  The connected phone dropped off ADB immediately before installation, so v1.6.3 physical-device
  installation and the manual two-account matrix remain explicitly pending.

**v1.6.4 verification (2026-07-31):**
- PR **#12** merged to `main` at commit `a30510207fd10ceb612a1e128f2875a01a57f0be`.
  Pull-request and merged-main CI passed mobile analysis/tests/APK build plus web typecheck,
  **15/15** Vitest tests and the 31-route production build. The tagged release workflow also
  passed analysis, tests, permanent signing and asset publication.
- Supabase migrations `notifications_calls_messages_overhaul`, `group_spec_consistency` and
  `message_hides_fk_index` are live. Production now reports 38 tables, 93 RLS policies and 37
  migrations; anonymous access to the new RPCs is denied.
- GitHub release `v1.6.4` publishes `klect.apk` (103,865,675 bytes,
  `application/vnd.android.package-archive`). A fresh download through the stable website URL
  verifies as `com.klect.klect`, version `1.6.4` / code `14`, target SDK 36, permanent certificate
  SHA-256 `460d934bcca98539907f82259f803080be55b153e7df0edec5878d4bf11b334f`, and file SHA-256
  `b05bddb04321c55c58f601f59c30ac8e7418ad61b8317decde414ddae0ea39ce`.
- Vercel production deployment `dpl_AEVhNVxfXGioXKXqYgYa17Ej3vMj` is READY and aliased to
  `https://klect-web.vercel.app`. The public home returns HTTP 200, contains the stable
  `releases/latest/download/klect.apk` link, and the post-deploy error log scan is empty.

Legend: ✅ done · 🟡 in progress · ⬜ not started · 🔴 blocked

---

## Verified facts (do not re-derive these)

**Supabase project `new_klect`**
- ref `dikhuygcwxnrsckqglzg` · region ap-southeast-2 · Postgres 17
- URL `https://dikhuygcwxnrsckqglzg.supabase.co`
- publishable key `sb_publishable_nwJjxG8yJ01lTjrv6pXQww_mQ9MNq5t`
- The service-role key is **not** in this repo and must never be. Server-only work uses edge functions.

**Migrations applied** (37, in order) — see [`../supabase/README.md`](../supabase/README.md) for the
table of what each one does. `0001`–`0021` build, harden and extend the original product; the
timestamped migrations add canonical social threads/activity, group preferences/controls, reliable
call state, push fan-out verification, synced notification preferences, message hiding, strict group
capacity/identity enforcement and the covering message-hide foreign-key index.

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
- Android tagged releases use the permanent `klect-release` key held in GitHub Secrets. Its
  encrypted local recovery pair is under
  `D:\D drive\coding\Ideas\hackathon\klect-signing-backup` (use only the `*-stable` files).
- ❌ **iOS `.ipa` cannot be built here and never will be** — Apple requires macOS + Xcode. Use a Mac,
  or a cloud macOS runner (Codemagic / GitHub Actions `macos-latest`). The Dart is platform-correct.
- ❌ Visual Studio absent → Windows *desktop* target unavailable. Irrelevant; we target iOS/Android/web.

---

## Supabase advisor status

Run `get_advisors` after any migration. Current state:

| advisor | ERROR | WARN | INFO |
|---|---|---|---|
| security | **0** | 85 | 1 |
| performance | **0** | 0 | 42 |

**Fixed:** extensions moved out of `public`; every function `search_path` pinned; `EXECUTE` revoked
wholesale then re-granted to a named surface; 28 unindexed foreign keys covered (`0013`); the two
`FOR ALL` policies split so `SELECT` is served by exactly one policy (`0013`); v1.6 preference
policies use `(select auth.uid())`, removing all new `auth_rls_initplan` performance warnings.

**Accepted WARNs, with reasons:**

- *`{anon,authenticated}_security_definer_function_executable`.* These are (a) the intended
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

**INFO:** `feature_flags` deliberately has no client RLS policy because direct table access is
revoked and the authenticated app reads only the safe `call_feature_enabled()` RPC. The 45
`unused_index` notices are expected before meaningful production traffic, including the new
call-participant and enabled-push-token indexes. One pre-existing unindexed-FK notice remains;
re-check query traffic before adding or dropping an index.

## Known limitations & open decisions

1. **Figma MCP is not authorized** in this session (non-interactive OAuth). The design system is delivered
   as code (`packages/tokens`) plus `DESIGN_SYSTEM.md`. If you get Figma access, push tokens with
   `figma-generate-library`; do not re-invent values.
2. **iOS release builds** require macOS/Xcode. Android release builds work locally and in GitHub CI.
3. **Calls:** transactional Postgres state, recipient-validated signalling, token lifecycle tables,
   diagnostics and protected TURN credential issuance are deployed, but `reliable_calls` remains
   server-disabled. **Firebase delivery is now done** (2026-07-30 — see `OPERATIONS.md` §2), so the
   remaining blockers for `v1.7.0` are Cloudflare TURN secrets, Android Core-Telecom integration, and
   two-real-phone relay/background/locked testing. Without TURN, WebRTC fails across most mobile
   carrier NATs, so this stays off until a relay is configured.
4. **v1.6 stretch UI:** group reporting is now implemented. Truly server-paginated inbox filters and
   per-chat wallpaper remain outside the completed Kiro spec.
5. **Pulse visual QA:** v1.6.2 rich target cards were verified on an attached Android 15 RMX3771
   in For You, Following and Profile Posts. Two-account follow-toast behavior and the complete
   physical gesture/keyboard/offline matrix remain manual.

---

## Session log

### 2026-07-31 — chat, calls and notifications Kiro completion
- Completed all 49 required tasks; 73 `*` property/widget/SQL proof tasks remain optional by the
  spec's faster-MVP rule.
- Finished Alert Center filtering/error retention/live announcements, bounded call lifecycle and
  reconnects, permissions and call surfaces, message tombstones/delete-for-me, group validation and
  enforcement/reporting, and the shared pager on Messages, Pulse, Surf and Profile.
- Verification: Flutter analysis 0 issues; 268/268 full tests and 145/145 focused tests pass;
  release web build and Wasm dry run pass. `scripts/verify.sh mobile` itself is unavailable because
  Windows reports WSL `REGDB_E_CLASSNOTREG`; its mobile commands passed directly in PowerShell.
- Applied and contract-checked `notifications_calls_messages_overhaul`, `group_spec_consistency` and
  `message_hides_fk_index` on live `new_klect`. The schema is now 38 tables / 93 policies / 37
  migrations; completion RPCs deny anonymous execution. Advisors report 0 ERROR, with only expected
  unused-index INFO for the brand-new message-hide indexes.

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

### 2026-07-28 — in-app sideload updater integration
- Built in an isolated sibling worktree on `agent/in-app-apk-updater`, leaving the active social /
  redesign checkout, branch, index, and uncommitted files untouched.
- This supersedes the earlier browser-download behavior: GitHub release checks now require a
  successfully uploaded `klect.apk` asset and cache its direct HTTPS URL, expected byte count, and
  SHA-256 digest. Old cached release metadata remains compatible through the stable latest URL.
- "Update in KLECT" streams the APK to private cache with visible progress, rejects truncated or
  digest-mismatched files, and opens Android's system installer through a narrowly scoped,
  non-exported FileProvider. If needed, Android first opens the per-app "Allow from this source"
  setting; after returning, the already verified APK is reused via "Continue install".
- Validation after merging current v1.6.3 into the updater branch: `dart analyze` 0 issues and the
  complete Flutter suite 129/129 passed. The standalone Android release APK had already compiled
  and packaged successfully with the expected
  `REQUEST_INSTALL_PACKAGES` permission and `com.klect.klect.update_file_provider` authority.
  Physical-device permission, install, replacement, and restart behavior remains to be verified
  after this code is released in a version newer than v1.6.3 with the permanent signer.
### 2026-07-27 — social and communication upgrade (v1.6.0)
- Added the shared rich Pulse target contract across Postgres, Flutter and Next.js. Reposts and
  quotes now retain author/body/time, ordered 1–4 media, entity attachments and explicit
  unavailable tombstones instead of empty cards. Following includes the viewer's own reposts,
  composite cursors are stable, selection is remembered and Profile exposes Posts/Replies/Media.
- Added the shared paged comment-tree RPC and Reddit-style mobile closeup presentation: rails,
  reply context, two-level indentation, deeper-thread continuation, tombstones, compact actions
  and a pinned keyboard-safe draft composer.
- Reworked Android chat composition and replies, idempotent server sends, inbox filtering, clearer
  group identity, square crop/rotate group avatars and account-synced appearance preferences.
  Advanced group policy/invite UI remains explicitly tracked instead of being claimed complete.
- Applied four additive production migrations; deployed `push-fanout` v2 and
  `turn-credentials` v1. Transactional call state and diagnostics are present, but calls remain
  disabled until the external Firebase/TURN/native prerequisites pass.
- Added reproducible mobile/web CI and tagged Android release automation. PR #4 merged; GitHub
  release `v1.6.0` and Vercel production deployment
  `dpl_AUW4gtCweYmEuLD2B99bevYbdYt8` are live and verified.

### 2026-07-28 — v1.6.1 group completion + permanent Android signing
- Exposed the already-live group backend in mobile: permission scopes for editing, adding and
  sending; join approval and request review; invite rotation/revocation/join; notification levels;
  member search; shared-photo grid; pending-member separation; and owner-only group deletion.
- Applied and smoke-tested two production migrations. Stored `everyone` group policy now genuinely
  controls edit/add RPCs, owner-only join approval/delete RPCs are guarded, and create/edit share an
  80-character title limit. Supabase advisors remain at 0 ERROR.
- Shipped `v1.6.1+11` through PR #5. Local analysis, 118 Flutter tests, web typecheck/9 tests/build,
  both GitHub CI runs, a clean Android build and public updater endpoint verification passed.
- Found that historical release automation used a newly generated debug certificate on every
  runner. The installed v1.6.0 certificate was therefore unrecoverable. Created one permanent
  release key, stored it in GitHub Secrets with a DPAPI-protected D-drive backup, replaced the
  v1.6.1 release asset, and merged the stable-signing workflow in PR #6.
- Uninstalled v1.6.0 once, installed the permanent-key v1.6.1 APK over USB on Android 15, launched
  it successfully and verified the full Surf semantics tree. Future stable releases can update
  this install normally.

### 2026-07-28 — v1.6.2 Pulse and follow-feedback repair
- Corrected the release mismatch: v1.6.1 was a group-control/signing release and did not contain
  the newly requested Pulse presentation, follow-underline or call-availability changes.
- Rebuilt Pulse around a compact X-style header, full-width feed tabs and a visible composer entry.
  Rich repost/quote targets now show original author, text or entity details and complete media in
  Pulse and Profile Posts instead of appearing empty.
- Removed the follow panel's inherited yellow text decoration and added regression coverage.
- Confirmed the production call flag is disabled because this account has no KLECT Firebase project
  or configured TURN service. Hidden the controls that could only fail; no fake call success is
  claimed. Real calls remain a separately gated v1.7 integration.
- Merged PR #8, passed both GitHub CI runs, built and USB-installed stable-signed `v1.6.2+12`, and
  tagged `v1.6.2` for the public updater release.

### 2026-07-28 — v1.6.3 Pulse engagement and unified profile activity
- Replaced incomplete Pulse/profile queries with shared paged v2 contracts. Plain reposts now carry
  the immutable original author, body, complete media and nested Surf target; quotes remain separate
  authored posts with their original embedded. Quote counts are trigger-maintained independently
  from plain repost counts.
- Split Like/Repost icon mutation from count navigation. Mobile sheets and a responsive web dialog
  now expose viewer-safe Likes and Reposts account rows plus real quote cards, with independent
  totals, stable opaque cursors, duplicate prevention and mutation-driven reconciliation.
- Reorganized profiles into public Surf/Pulse identities and owner-only Activity. Pulse contains
  Posts/Replies/Media with source filters; Replies use the actual comments system with parent and
  destination context; private Likes/Saves split into Surf/Pulse; owner delete/undo/open/copy
  controls use guarded server mutations.
- Applied and smoke-tested migration `social_activity_profile`, regenerated web database types from
  production, merged PR #10, deployed Vercel production, and published permanent-key
  `v1.6.3+13`. All automated gates are green. Physical installation remains pending only because
  the previously attached Android phone disconnected before `adb install -r`.

---

### 2026-07-30 — FCM device push wired and verified end to end

Push notifications moved from "built but inert" to **live and verified**. Nothing about the
delivery contract changed; the missing pieces were the Firebase project and the trigger.

- **Discovered an existing Firebase project `klect-b776a`** on the connected account
  (`2023cse29.gpv@gmail.com`), created earlier the same day and completely empty — no apps
  registered. Reused it rather than creating a duplicate. The unrelated `disha-501012` project on
  the same account was left alone.
- Registered Android app `1:412736900783:android:98a901f20c45ca83d6ce5a` for `com.klect.klect`,
  attached the permanent release cert SHA-256 `460d934b…f11b334f`, and wrote the generated
  `google-services.json` into `mobile/android/app/`. Added the `com.google.gms.google-services`
  Gradle plugin to `settings.gradle.kts` + `app/build.gradle.kts`.
- **Gitignored `google-services.json` and `GoogleService-Info.plist`.** The bundled API key is
  package-scoped by Google rather than a true secret, but it is environment-specific — each
  dev/CI environment should fetch its own via `firebase_get_sdk_config`.
- Mobile client: added `firebase_core` + `firebase_messaging`, new
  `core/notifications/push_notifications.dart` (`PushNotifications`), and `KlectApi`
  `registerPushToken`/`unregisterPushToken` wrappers over the RPCs that already existed from
  `reliable_call_state`. Registration fires from `RootShell.initState` and on `onTokenRefresh`;
  `AuthController.signOut` unregisters so a signed-out phone stops receiving the prior account's
  push. `Firebase.initializeApp` failure is caught, so a config-less build degrades to "no push"
  instead of crashing.
- Set `FCM_SERVICE_ACCOUNT` and `PUSH_WEBHOOK_SECRET` on `new_klect`. Passing the multi-line
  service-account JSON inline fails with `Invalid secret pair: PRIVATE`; `--env-file` works.
- **Built the Database Webhook as two migrations instead of dashboard clicks**, so it is
  version-controlled like the rest of the schema: `enable_pg_net_and_vault_secret` turns on
  `pg_net`, and `notifications_push_fanout_webhook` adds `public.notify_push_fanout()` plus an
  `after insert` trigger on `public.notifications`. The shared secret is read at call time from
  **Vault** (`push_webhook_secret`) rather than written into the trigger body, which would have
  left it in plaintext in migration history permanently. A missing secret makes the trigger skip
  silently — a notification is never lost because push is misconfigured.
- **Verified, not assumed:** 401 without the secret header; `{"sent":0,"pruned":1}` against a
  deliberately invalid token, which can only happen if the RSA key imported and the Google OAuth2
  exchange succeeded; and a real notification insert recorded `200 {"sent":0,"reason":"no-devices"}`
  in `net._http_response`, proving the trigger→`pg_net`→function path. Mobile `flutter analyze`
  is clean, 126/126 tests pass, and `flutter build apk` succeeds.
- Two gotchas worth remembering: **`execute_sql` via the Supabase MCP rolls back writes**, so a
  test row inserted that way silently does not exist (use `apply_migration`); and
  `firebase_messaging` requires **Android SDK Platform 34** installed alongside 36.
- Deleted the local `firebase-service-account.json` and the temporary webhook-secret file after
  the secrets were stored server-side. Neither is recoverable from this repo by design.

**Real-device delivery proven the same session.** Built a stable-signed `1.6.4+14` release APK
(98.5 MB, cert `460d934b…f11b334f`, `com.klect.klect`, min 24 / target 36) and installed it in
place over `1.6.3+13` on the attached RMX3771 with app data intact. A genuine 142-char FCM token
registered into `push_tokens`; a real notification insert produced `200 {"sent":1,"pruned":0}` in
`net._http_response`; and the phone rendered it as `tag=FCM-Notification:…`, `channel=social`,
title "Silas Okonkwo", body "started following you". The FCM-prefixed tag comes from the Firebase
SDK, so this is real push and not the stage-1 local-notification path. Both `social` (importance 4)
and `calls` (importance 5) channels are registered on the device.

**Test-method trap worth remembering:** the first attempt used `adb shell am force-stop`, which
puts the app in Android's *stopped state* — the OS then withholds FCM entirely until a manual
relaunch. FCM reported `sent:1` while the tray stayed empty, which reads as a broken integration
but is not; the queued message arrived on relaunch (hence two notifications appearing later). Use
`am kill` or simple backgrounding instead. Recorded in `OPERATIONS.md` §2.

**Version bookkeeping:** `pubspec.yaml`, `lib/core/app_version.dart` and the web version constant
are `1.6.4`. PR #12 is merged, GitHub release `v1.6.4` is public with the stable-signed APK, and
the matching web build is deployed to Vercel.

---

### 2026-08-01 — v1.6.5 Android blank-screen repair and device verification

- Reproduced the reported white screen on the connected RMX3771 while running `1.6.4+14`.
  Firebase initialized and the activity stayed alive, but Flutter logged `No GoRouter found in
  context` from `incoming_call_overlay.dart`: the overlay was mounted above the router by
  `MaterialApp.router.builder` and tried to find the router from the wrong context.
- PR #14 (`c827e926`) passes the existing `GoRouter` into `CallOverlayHost` and removes the invalid
  context lookup. Mobile/web versions moved together to `1.6.5` (`versionCode 15`). GitHub CI
  passed analyze, tests and release build.
- Public GitHub release `v1.6.5` is live with `klect.apk` (`sha256
  8c21cc14ec3b88ed1f08d3cdc91a1e3fe091c7cf7aa6aa9412114ecef3a6edb9`), package
  `com.klect.klect`, version `1.6.5+15`, and the permanent certificate
  `460d934b…f11b334f`.
- Downloaded that public asset and ran `adb install -r` over the installed `1.6.4` without
  uninstalling. The phone retained app data, launched `MainActivity`, showed the Surf screen, and
  no longer logged the GoRouter exception. This is now the correct in-place update path.
- Deployed the matching web source to Vercel production deployment
  `dpl_ERtdhrza9qz2ss7jSKXKFAYn45pV`, READY at `https://klect-web.vercel.app`; the download button
  continues to use the stable latest-release APK URL.

**Version bookkeeping:** `pubspec.yaml`, `lib/core/app_version.dart` and the web version constant
are now `1.6.5`. PR #14 is merged, GitHub release `v1.6.5` is public, the signed APK is verified
on the attached phone, and the matching web build is deployed to Vercel.

---

## Next actions

1. Run the two-account Pulse
   matrix: four-photo original → plain repost → quote → Likes/Reposts/Quotes account lists; profile
   Surf/Pulse/Activity filters; Surf/Pulse replies and deep links; private/blocked/unavailable
   targets; owner delete/undo; offline replay; large text and reduced motion.
2. Finish the remaining stretch UI: server-paginated inbox filters and per-chat wallpaper. Keep web
   group-management parity as a separate scoped release.
3. Add a small automated assertion that `kAppVersion` matches the `pubspec` version so release
   bookkeeping cannot drift again, and take on the optional Kiro proof tasks only when their added
   confidence justifies the time.
4. Configure Cloudflare TURN secrets and implement Android Core-Telecom/CallStyle, then run the
   required two-device Wi-Fi/carrier/background/terminated/locked/permission-denied/forced-relay
   matrix before enabling `reliable_calls` or tagging v1.7. (Firebase push, the third prerequisite,
   is done as of 2026-07-30.)
5. Walk through manual sections A–H of `CHECKLIST.md` (63 items — gestures, optimistic social
   mechanics, messaging/groups, moderation, two-account RLS and craft). Automated gates are green.
6. Triage the current production `npm audit --omit=dev` result (3 high, 0 critical; `next`,
   transitive `postcss` and `sharp`). The registry's proposed fix is an invalid Next.js downgrade,
   so do not apply `npm audit fix --force`; upgrade through a tested supported Next release.
