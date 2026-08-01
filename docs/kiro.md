# KIRO — Spec execution log: `chat-calls-notifications-overhaul`

> Spec: `.kiro/specs/chat-calls-notifications-overhaul/`
> Last updated: 2026-08-01

## Status

| | Count |
|---|---:|
| Required implementation tasks done | **49 of 49** |
| Required implementation tasks open | **0** |
| Optional `*` proof/test tasks done | **0 of 73** |

The required product work is complete. The 73 unchecked `*` items are optional property, widget,
and SQL proof tasks; `tasks.md` explicitly permits skipping them for the faster MVP.

## Completed

- Notification taxonomy, account-synced preferences, push filtering, Editorial Noir banners, and
  Alert Center category filtering with counts, retained error content, and live announcements.
- Call availability, permissions, lifecycle timeouts, bounded ICE reconnects, busy-call protection,
  in-call controls, video/chrome behavior, persistent call pill, and guarded Android call actions.
- Message deletion for everyone and for me, stable tombstones, unavailable reply targets, hidden-page
  filling, confirmations, rollback, and deleted inbox previews.
- Group role affordances, 256-member capacity, trimmed 60/500-character identity validation,
  bounded reconciliation, send-scope lockout, reporting, and identity system messages.
- Shared swipeable tab pager with threshold physics, linear indicator tracking, reduced motion,
  per-page state preservation, visibility/deep-link restoration, nested drag claims, and adoption on
  Messages, Pulse, Surf, and Profile.
- Accessibility/token sweep across the seven new surfaces.

## Verification

- `flutter analyze`: **No issues found**.
- `flutter test --no-pub`: **281 tests passed** in the v1.6.6 stabilization candidate.
- Focused notification/call/group/deletion/pager run: **145 tests passed**.
- `flutter build web --release`: **passed**; Wasm dry run also passed.
- Live Supabase `new_klect`: all 3 completion migrations applied and contract-checked
  (`notifications_calls_messages_overhaul`, `group_spec_consistency`, `message_hides_fk_index`).
- Supabase advisors: **0 ERROR**; the new schema has no uncovered foreign-key index or anonymous RPC
  access. New indexes only report the expected unused-index INFO until production traffic uses them.
- `scripts/verify.sh mobile` could not start because WSL Bash is not registered on this Windows host
  (`REGDB_E_CLASSNOTREG`). Its mobile commands were run directly in PowerShell and passed.
- PR #12 merged to `main`; merged-main CI and the tagged Android release workflow passed.
- GitHub release `v1.6.4` contains the stable-signed `klect.apk`, and Vercel production deployment
  `dpl_AEVhNVxfXGioXKXqYgYa17Ej3vMj` is READY at `https://klect-web.vercel.app`. The public web
  download button resolves through the stable latest-release URL to the verified v1.6.4 APK.
- PR #14 fixed the Android startup white screen by passing the router into the call overlay instead
  of looking it up above `MaterialApp.router`. Release `v1.6.5` (`versionCode 15`) passed CI, was
  verified with the permanent signing certificate, installed in place over v1.6.4 on the attached
  RMX3771, and rendered the Surf screen successfully. Vercel production was redeployed with the
  matching web version.
- The v1.6.6 stabilization work keeps Surf/Pulse chrome outside horizontal pages, coordinates
  Profile scrolling, removes shell-bar overlap, protects reply text from large keyboards, keeps
  gated DM call actions visible, and normalizes foreground FCM through the existing banner
  presenter. Analysis, 281 tests, the arm64 APK build and all web gates pass.
- PR #15 merged and tag `v1.6.6` published the permanent-signed `klect.apk`. The RMX3771 upgraded
  from v1.6.5 in place, preserved its original install timestamp, launched without a white screen
  and rendered fixed Surf/Pulse chrome. Vercel production deployment
  `dpl_Hs3W8DvZcB7LWpS3D5pf8BbeZhyK` is READY with the stable latest-APK link. OEM keyboard/tray and
  two-phone call validation remain pending.
- The v1.7.0 candidate adds live finger-tracking rail state, minimal foreground notices, one
  keyboard-inset owner, peer-first DM chrome and hydrated viewer-relative call events. Android now
  owns Core-Telecom registration, CallStyle surfaces, the phone-call foreground service and durable
  system actions; Flutter reconciles every native action against authoritative Supabase state.
- Production migration `android_reliable_calling_v170` is applied and `push-fanout` v5 is ACTIVE.
  A rolled-back authenticated test proved transactional one-call/one-notification delivery. Global
  calling remains disabled, the QA allowlist remains empty, and both Cloudflare TURN secret names
  are absent, so real-call validation remains pending.
- Candidate gates pass: Flutter analysis and the complete **291-test** suite including version
  lockstep and forced-relay configuration, Deno
  payload tests/typecheck, Android Kotlin/native-payload tests and merged manifest, and web
  typecheck/15 tests/31-route build. Two attached phones and forced-relay evidence remain required.
- A compile-time QA build switch (`KLECT_FORCE_TURN_RELAY=true`) now forces WebRTC relay-only
  candidate selection; it is covered by ICE configuration tests and stays absent from normal
  production builds.
- PR #17 merged to `main` as `f61be20`; GitHub release/tag `v1.7.0` publishes the permanent-signed
  `klect.apk`, and Vercel production deployment `dpl_JB9huV83RS46iUC9bLjDfRLucyxh` is READY at
  `https://klect-web.vercel.app`. The stable download URL is
  `https://github.com/Zarosky00/klect-app/releases/latest/download/klect.apk`.

## Remaining outside the required implementation

- Optional `*` tasks: 73 property/widget/SQL proof tasks, beginning with task 1.3 (`glados` and shared
  generators). These improve proof depth but are not required by the task runner's MVP path.
- Operator setup already called out by the spec: enable `reliable_calls` and configure Cloudflare TURN
  secrets when production infrastructure is ready. For v1.7.0, enter the secrets securely, test
  only the two-account QA allowlist, and keep the global flag off unless every mandatory physical
  Android case passes.
