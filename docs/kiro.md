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
- `flutter test --no-pub`: **268 tests passed**.
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

## Remaining outside the required implementation

- Optional `*` tasks: 73 property/widget/SQL proof tasks, beginning with task 1.3 (`glados` and shared
  generators). These improve proof depth but are not required by the task runner's MVP path.
- Operator setup already called out by the spec: enable `reliable_calls` and configure Cloudflare TURN
  secrets when production infrastructure is ready.
