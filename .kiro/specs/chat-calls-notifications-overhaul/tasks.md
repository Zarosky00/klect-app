# Implementation Plan: Chat, Calls and Notifications Overhaul

## Overview

The implementation language is **Dart / Flutter** for `mobile/`, **PL/pgSQL** for the single new
migration in `supabase/migrations/`, and **TypeScript (Deno)** for `supabase/functions/push-fanout/`.
The design names every file, table and RPC, so each task below is a delta to a named artefact rather
than a greenfield module.

Sequencing rules baked into the ordering:

1. **Tokens first.** The eight new `packages/tokens/tokens.json` entries are added and
   `node packages/tokens/build.mjs` is run in task 1.1, before any widget consumes them
   (Requirement 16.8). No task after 1.1 may introduce a colour, radius, duration, spacing, stroke or
   easing literal.
2. **SQL then the Dart mirror.** The single migration (tasks 2.1–2.3) lands before
   `NotificationCategory` (task 3.1) mirrors `public.notification_category()`, and before any client
   code calls `set_notification_preferences`, `hide_message_for_me`,
   `delete_message_for_everyone`, `record_call_diagnostic` or the widened `set_group_member_role`.
3. **Property tests follow their implementation immediately** so a broken invariant is caught in the
   same group rather than at the end.

Klect hard rules that constrain every task: per-category unread counts are derived from the
`read_at` column already carried on each loaded `notifications` row — never from a client-side
aggregate query or a new counter column; every write goes through an RPC or an RLS-protected table;
no client ever holds the service-role key (the `push-fanout` gates are the only service-role reads
and they stay inside the edge function).

### Property-based testing conventions

- Library: `glados` in `mobile/pubspec.yaml` `dev_dependencies`; property testing is never
  hand-rolled.
- Every property test runs with `ExploreConfig(numRuns: 100)` at minimum.
- Exactly one property maps to exactly one property-based test.
- Every property test carries the tag comment
  `// Feature: chat-calls-notifications-overhaul, Property {n}: {property text}`.
- Files live in `mobile/test/properties/`, one file per workstream, as named in the design's Testing
  Strategy.
- Determinism: `fakeAsync` drives every timeout, `FakeChatApi` scripts RPC outcomes and
  `FakePeerConnection` publishes connection states on command. Nothing touches the network or a real
  clock.

## Tasks

- [x] 1. Foundations: design tokens and test scaffolding
  - [x] 1.1 Add the new token entries and regenerate the Token_Set
    - Add to `packages/tokens/tokens.json`: `motion.dwell.banner` (5000),
      `motion.drag.bannerLimit` (96), `motion.drag.commitFraction` (0.4),
      `motion.drag.pageCommitFraction` (0.25), `motion.drag.flingVelocityMin` (400),
      `motion.drag.overscrollMax` (32), `motion.timeout.thumbnail` (2000),
      `layout.callPillHeight` (48)
    - Run `node packages/tokens/build.mjs` and commit the regenerated
      `mobile/lib/design/tokens.g.dart` plus the CSS output together; never hand-edit the outputs
    - _Requirements: 16.6, 16.8_

  - [ ]* 1.2 Write token compliance tests
    - `mobile/test/design_tokens_test.dart`: assert each of the eight new entries exists in the
      generated Dart token file with the expected value (16.8)
    - Source scan over every file this feature adds or changes asserting zero colour, radius,
      duration, spacing, stroke-width and easing-curve literals, excluding `tokens.g.dart` (16.1)
    - _Requirements: 16.1, 16.8_

  - [ ]* 1.3 Add the property-testing toolchain and shared generators
    - Add `glados` to `mobile/pubspec.yaml` `dev_dependencies`
    - Create `mobile/test/properties/generators.dart`: `NotificationModel` across all types including
      unknown wire values; bodies covering empty, whitespace-only, the 140-character boundary, emoji
      clusters and RTL; preference sets and malformed preference JSON; call event sequences (RPC
      results, realtime rows, peer-connection states, timer expiries); ICE server lists mixing
      complete, partial and empty relay entries; threads with deletion and hide patterns; member
      lists of size 2..256 with role distributions; drag traces as `(deltas, velocity)` pairs; text
      scale factors in `[1.0, 2.0]`
    - Extend `mobile/test/support/` with `FakeChatApi` (records RPC calls, returns scripted outcomes)
      and `FakePeerConnection` (publishes connection states on command)
    - _Requirements: 16.7_

- [x] 2. Database migration (single file, additive, nothing dropped)
  - [x] 2.1 Create the migration with the category taxonomy and the preference store
    - New `supabase/migrations/<timestamp>_notifications_calls_messages_overhaul.sql`
    - `alter type public.notification_type add value if not exists 'recommendation'`
    - `public.notification_category(p_type)` — `immutable security definer set search_path = ''`,
      total over the enum with `system` as the fallback, returning one of the 11 category strings
    - `alter table public.user_preferences add column if not exists notifications jsonb not null
      default '{}'::jsonb`
    - `public.set_notification_preferences(p_notifications jsonb)` — `public.require_auth()`,
      whole-payload validation against the 11 allowed keys and boolean values, raising
      `bad_notification_preferences` on any bad key or non-boolean, upsert on the caller's own row
      only, returning the authoritative set
    - Grants: `revoke all from anon`, `grant execute to authenticated` for both functions
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 2.2 Extend the migration with delete-for-me and the tombstone RPC
    - `public.message_hides (message_id, user_id, conversation_id, created_at)` with primary key
      `(message_id, user_id)` and the `(user_id, conversation_id)` index; RLS enabled with own-row
      select and insert policies; `revoke all from anon`
    - `public.hide_message_for_me(p_message)` — membership check, `on conflict do nothing` so a
      repeat succeeds without a duplicate record
    - `public.delete_message_for_everyone(p_message)` — author-only (`not_message_author`),
      `select ... for update`, sets `deleted_at`, clears `body` to `''` and `attachments` to `'[]'`,
      never writes `id`, `author_id`, `reply_to_id` or `created_at`, refreshes
      `conversations.last_message_preview` only when the message was the conversation's newest, and
      returns the row unchanged on a repeat
    - _Requirements: 11.1, 11.3, 11.8, 11.9, 11.10, 12.7, 12.8_

  - [x] 2.3 Extend the migration with the call and group RPC deltas
    - `decline_call(p_call, p_reason default 'declined')` — `end_reason` trimmed and capped at 120
      characters so a busy decline can say why
    - `end_call(p_call, p_reason, p_outcome, p_client_elapsed_seconds default null)` — stored
      duration stays server-computed from `calls.started_at`; the client value is merged into
      `calls.diagnostics` clamped to `[0, 86400]`
    - `record_call_diagnostic(p_call, p_key, p_value)` — participant-only, merges into
      `calls.diagnostics` rather than replacing it
    - `set_group_member_role(p_conversation, p_member, p_role)` widened: `p_role = 'owner'` requires
      caller role `owner`; `p_role in ('admin','member')` requires
      `is_conversation_admin(p_conversation)`; a target whose role is `owner` raises `not_owner`
    - _Requirements: 7.8, 7.16, 10.3, 10.4, 13.5, 13.6, 13.7_

  - [ ]* 2.4 Write the SQL verification script
    - `supabase/tests/notifications_calls_messages_overhaul_verify.sql`, every check inside a
      transaction that is rolled back, under JWT impersonation
    - `set_notification_preferences`: own-row only, anonymous refusal, cross-account isolation,
      whole-payload rejection on a bad key and on a non-boolean value (5.2, 5.3, 5.4)
    - `notification_category`: exactly one of the 11 strings for every `notification_type` label in
      the enum, `system` as the total fallback
    - `delete_message_for_everyone`: non-author refused with the row unchanged; a repeated delete
      returns an identical row; preview refreshed only when the message was the newest (11.9, 11.10)
    - `hide_message_for_me` + `message_hides` RLS: repeated calls yield one row; another account
      reads zero rows and cannot insert on someone else's behalf (12.7, 12.8)
    - `set_group_member_role`: an admin may promote and demote `admin`, a member is refused, a
      non-owner transfer is refused, the owner cannot be targeted (13.5, 13.7)
    - `decline_call(p_reason)` / `end_call(p_client_elapsed_seconds)`: stored duration stays
      server-computed, a repeated `end_call` returns the first outcome unchanged, the client elapsed
      value lands in `diagnostics` clamped to `[0, 86400]` (7.8, 7.11)
    - `record_call_diagnostic`: participant-only, merges rather than replaces
    - Advisor sweep assertion: 0 ERROR, any new WARN confined to the accepted
      `security_definer_function_executable` class
    - _Requirements: 5.2, 5.3, 5.4, 7.8, 7.11, 11.9, 11.10, 12.7, 12.8, 13.5, 13.7_

- [x] 3. Notification taxonomy and account-synced preferences
  - [x] 3.1 Create the Dart category taxonomy mirroring the SQL function
    - New `mobile/lib/features/notifications/notification_category.dart`: the 11-member
      `NotificationCategory` enum with `wire` labels, a total `of(NotificationType)` mapping where
      unmapped and unknown types land in `system`, `style(KlectColors)` returning the action glyph and
      tint with the Token_Set accent as the fallback, and `label` for rail chips and empty-state copy
    - Refactor `notificationStyle()` in `mobile/lib/features/notifications/notifications_screen.dart`
      to delegate here so the banner glyph, the row glyph and the rail chip cannot drift
    - _Requirements: 1.6, 4.1_

  - [ ]* 3.2 Write the taxonomy agreement test
    - `mobile/test/notification_category_test.dart`: assert `NotificationCategory.of` returns exactly
      one category for every `NotificationType` label the server reports, and that the Dart mapping
      equals the `public.notification_category()` mapping label for label
    - _Requirements: 5.1_

  - [x] 3.3 Rewrite notification preferences as an account-synced service
    - Rewrite `mobile/lib/features/notifications/notification_preferences.dart`:
      `NotificationPreferenceSet` (immutable, total over all 11 categories, absent key means enabled,
      `toJson` always writing all 11 boolean keys, tolerant `fromJson` ignoring unknown keys) and
      `NotificationPreferencesService extends AsyncNotifier<NotificationPreferenceSet>`
    - `build()` reads `user_preferences.notifications` for `auth.uid()`; a missing row or missing key
      resolves to enabled
    - `setEnabled` writes through the `set_notification_preferences` RPC, applies optimistically and
      restores the entire previous set on error or after 10 s with no message surfaced
    - Legacy migration: when `klect.notifications.muted.v1` exists and
      `klect.notifications.migrated.v1` does not, map each muted `NotificationType` to its category,
      write once as `enabled: false`, set the migrated flag, and never read the device-local key again;
      leave the legacy key in place
    - _Requirements: 5.1, 5.2, 5.7, 5.8, 5.11, 5.12, 5.13_

  - [ ]* 3.4 Write property test for preference set totality and round-trip
    - **Property 14: Preference sets are total and round-trip**
    - **Validates: Requirements 5.1, 5.8, 5.9**
    - `mobile/test/properties/notification_preferences_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 14: Preference sets are total and round-trip`

  - [ ]* 3.5 Write property test for whole-payload rejection
    - **Property 15: An invalid preference payload is rejected whole**
    - **Validates: Requirements 5.4**
    - `mobile/test/properties/notification_preferences_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; `bad_notification_preferences` is asserted, never surfaced
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 15: An invalid preference payload is rejected whole`

  - [ ]* 3.6 Write property test for preference write idempotence and rollback
    - **Property 17: Preference writes are idempotent and roll back completely**
    - **Validates: Requirements 5.10, 5.11**
    - `mobile/test/properties/notification_preferences_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; `fakeAsync` drives the 10 s timeout
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 17: Preference writes are idempotent and roll back completely`

  - [ ]* 3.7 Write property test for the legacy muted-set migration
    - **Property 18: The legacy muted set migrates exactly once**
    - **Validates: Requirements 5.12, 5.13**
    - `mobile/test/properties/notification_preferences_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 18: The legacy muted set migrates exactly once`

  - [x] 3.8 Switch the settings notification section to per-category copy
    - `mobile/lib/features/settings/settings_screen.dart`: replace the per-`NotificationType`
      `notificationTypeCopy` switches with the 11 per-category switches in Glossary order, rendered
      from the resolved `NotificationPreferenceSet` before any switch accepts input
    - _Requirements: 5.1, 5.7_

  - [ ]* 3.9 Write widget test for first-render preference state
    - `mobile/test/notification_preferences_widget_test.dart`: on a fresh device the 11 switches
      render in the Preference_Store state before any switch accepts input (5.7)
    - _Requirements: 5.7_

- [x] 4. Push fanout delivery gates
  - [x] 4.1 Add the category gate and the missing compose cases to push-fanout
    - `supabase/functions/push-fanout/index.ts`: before the FCM token exchange, resolve
      `notification_category(n.type)` and read `user_preferences.notifications` for `n.user_id`;
      return HTTP 200 with `reason: "category-disabled"` when the flag is `false` so a muted category
      never puts the webhook into a retry loop
    - Leave the existing `conversation_members.muted_until` gate in place and deliberately
      independent of the `messages` category flag
    - Add the `recommendation` case to `compose()` and keep the `default` branch
    - Call payloads keep `priority: HIGH` and `channel_id: "calls"` and gain
      `android.notification.click_action` plus a `call_id` data field
    - Service-role reads stay inside this function; nothing is exposed to clients
    - _Requirements: 5.6, 5.14, 9.6, 9.10_

  - [ ]* 4.2 Write property test for gate agreement
    - **Property 16: The client gate and the delivery gate agree**
    - **Validates: Requirements 5.6, 5.14, 9.10**
    - `mobile/test/properties/notification_preferences_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; both decisions are exercised as pure functions over
      (preference set, notification row, mute timestamp)
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 16: The client gate and the delivery gate agree`

- [x] 5. Editorial Noir notification banner
  - [x] 5.1 Rewrite KBanner as KNotificationBanner with a typed view model
    - `mobile/lib/ui/k_banner.dart`: `NotificationBannerData` and `NotificationBannerAction` replace
      the loose parameters; same `Overlay` strategy and static entry point
    - Layout in reading order: avatar (`Space.s10`) with badged category glyph, title/message column,
      optional square thumb (`Space.s10`), dismiss control; card centred, clamped to
      `Layout.readableMaxWidth`, falling back to available width minus `Space.s3` gutters, anchored at
      `MediaQuery.viewPaddingOf(context).top + Space.s2`
    - Remove the `-96.0` clamp and `-200` velocity literals in favour of `Motion.bannerDragLimit`,
      `Motion.flingVelocityMin` and `Motion.bannerDwellMs`
    - Enter `KDurations.medium`, leave `KDurations.fast`, `KMotion.reduced(context)` swapping both for
      a 90 ms opacity fade with no transform; `_leaving` gates input during exit
    - Drag follows the finger 1:1 clamped to `[-limit, 0]`, suspends the dwell timer, restarts it from
      full on a returning release, and commits on velocity or on 40 % of the card height measured from
      a `LayoutBuilder`/`RenderBox`
    - `show()` returns `false` and drops the newer notification while an entry is mounted or an exit
      animation is in flight
    - Count-bearing lines render through `context.kt.count` (tabular); dismiss and every action use
      `KPressable` with `enforceMinTapTarget: true`
    - _Requirements: 1.1, 1.2, 1.7, 1.9, 1.10, 2.1, 2.2, 2.5, 2.6, 2.7, 2.8, 2.9, 16.1, 16.3_

  - [ ]* 5.2 Write property test for banner geometry
    - **Property 3: Banner geometry is derived, never assumed**
    - **Validates: Requirements 1.9, 1.10**
    - `mobile/test/properties/notification_banner_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over available widths 240..1400 and arbitrary status-bar insets
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 3: Banner geometry is derived, never assumed`

  - [ ]* 5.3 Write property test for drag dismissal
    - **Property 4: Drag dismissal is a pure decision over displacement and velocity**
    - **Validates: Requirements 2.2, 2.3, 2.4, 2.7**
    - `mobile/test/properties/notification_banner_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over generated drag traces with reduced motion both on and off
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 4: Drag dismissal is a pure decision over displacement and velocity`

  - [ ]* 5.4 Write property test for single overlay entry
    - **Property 5: At most one banner overlay entry exists**
    - **Validates: Requirements 2.6, 2.8, 2.9**
    - `mobile/test/properties/notification_banner_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over interleavings of present, tap, drag, dwell-expiry and dismiss
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 5: At most one banner overlay entry exists`

  - [x] 5.5 Implement per-category banner composition
    - New `mobile/lib/features/notifications/notification_copy.dart` with
      `bannerContentFor(NotificationModel)`: message titles from the sender display name with the body
      truncated to 140 characters and the attachment kind label substituted for an empty body; follow
      phrase plus follow-back action; ringing-call accept and decline actions; recommendation cover
      thumb with the owner name; the shared glyph/actor/phrase shape for like, save, repost, comment,
      reply, mention, match and system; a generic shape for any unknown wire type; a placeholder actor
      label where no display name resolves
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.12, 1.8_

  - [ ]* 5.6 Write property test for banner composition
    - **Property 1: Banner composition is total and bounded**
    - **Validates: Requirements 1.2, 1.6, 1.8, 3.1, 3.4, 3.5, 3.6, 3.12**
    - `mobile/test/properties/notification_banner_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over all notification types including unknown wire values, absent
      actor names and absent entity references
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 1: Banner composition is total and bounded`

  - [x] 5.7 Implement the pure presenter decision and the resolution budget
    - `mobile/lib/features/notifications/notification_surfaces.dart`: add `BannerDecision` /
      `BannerSuppression` and the pure `decideBanner({notification, preferences, currentRoute,
      callStatus, bannerMounted, recentlyPresented, content})` with no I/O and no `BuildContext`
    - Replace the `_lastPresentedId` single slot with a 50-entry insertion-ordered ring
    - Suppress on disabled category, Alert Center route, destination-route match including entity id
      parameters and path-segment children, and a `call` notification whose row status is not `ringing`
      (checked via `ChatApi.fetchCall`)
    - Race thumbnail and avatar resolution against `Future.delayed(Motion.thumbTimeout)`; a lost race
      presents without the thumb and with an initials avatar and surfaces no error
    - Render the blurhash in the thumb area until the decoded thumbnail replaces it
    - An unresolvable destination removes the banner and navigates to `Routes.notifications`
    - _Requirements: 1.3, 1.4, 1.5, 1.11, 3.7, 3.8, 3.9, 3.10, 3.11, 3.13, 5.5_

  - [ ]* 5.8 Write property test for the suppression predicate
    - **Property 6: Suppression is decided by one predicate**
    - **Validates: Requirements 3.8, 3.9, 3.11, 5.5**
    - `mobile/test/properties/notification_banner_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over notification, route, call status and preference set
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 6: Suppression is decided by one predicate`

  - [ ]* 5.9 Write property test for bounded presentation idempotence
    - **Property 7: Presentation is idempotent within a bounded memory**
    - **Validates: Requirements 3.10**
    - `mobile/test/properties/notification_banner_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over generated id sequences longer than the 50-entry window
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 7: Presentation is idempotent within a bounded memory`

  - [ ]* 5.10 Write property test for the thumbnail budget
    - **Property 2: Presentation never waits longer than the thumbnail budget**
    - **Validates: Requirements 1.3, 1.4, 1.11**
    - `mobile/test/properties/notification_banner_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; `fakeAsync` drives the 2 s budget including never-resolving
      futures
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 2: Presentation never waits longer than the thumbnail budget`

  - [x] 5.11 Wire the banner actions to their single effects
    - `mobile/lib/features/notifications/notification_surfaces.dart` and
      `mobile/lib/ui/k_banner.dart`: follow-back issues one follow for the actor, swaps the action
      label to its confirmed state and removes the banner; accept answers the call id and opens the
      Call_Screen; decline declines the call id without navigating; a tap navigates to the
      notification's destination and removes the banner
    - _Requirements: 3.2, 3.3, 3.7_

  - [ ]* 5.12 Write property test for banner action effects
    - **Property 8: Banner actions have exactly one effect each**
    - **Validates: Requirements 3.2, 3.3, 3.7**
    - `mobile/test/properties/notification_banner_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; `FakeChatApi` records the RPCs issued
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 8: Banner actions have exactly one effect each`

  - [ ]* 5.13 Write widget tests for banner examples and edge cases
    - `mobile/test/k_banner_test.dart`: the enter animation and the 5 s dwell sequence (2.1, 2.5), the
      blurhash-then-decoded-image swap (1.5), and the unresolvable-destination fallback to the Alert
      Center (3.13)
    - _Requirements: 1.5, 2.1, 2.5, 3.13_

- [x] 6. Checkpoint - notifications foundation
  - Ensure all tests pass, ask the user if questions arise.

- [x] 7. Alert Center category filtering
  - [x] 7.1 Implement the filter rail and the session-scoped selection
    - `mobile/lib/features/notifications/notifications_screen.dart`: a horizontal `KChip` rail of
      `All` plus the 11 categories in Glossary order, pinned above the grouped list, scrolling
      horizontally when the chips exceed the available width, each chip `Layout.tapTargetMin` tall,
      with the selected chip scrolled fully into view
    - `notificationFilterProvider` as a plain session-scoped `Notifier` held by the shell (not
      `autoDispose`) so reopening restores the selection and a fresh session starts at `All`
    - The filter indicator animates to the activated chip within `KDurations.deliberate`, including
      when the activated chip is already selected
    - _Requirements: 4.1, 4.8, 4.9_

  - [x] 7.2 Implement the pure filter and count transforms
    - New `mobile/lib/features/notifications/notification_filters.dart`:
      `filterNotifications(rows, selection, preferences)` as an order-preserving pure transform over
      already-loaded rows, removing preference-suppressed rows under every selection so a
      single-category list is always a subsequence of `All` — no refetch
    - `unreadCountsByCategory(rows)` derived from each loaded row's `read_at` only; never a
      client-side aggregate query and never a new counter column
    - Realtime arrivals off `notificationEventsProvider` prepend to the backing list; the rendered
      list changes only when the new row matches the selection while its chip count increments
      regardless; counts render `1..99` as tabular digits and `99+` above 99, absent at zero
    - _Requirements: 4.2, 4.3, 4.4, 4.5, 4.7, 4.11, 1.7_

  - [ ]* 7.3 Write property test for category filtering
    - **Property 9: Category filtering is an order-preserving, idempotent subsequence**
    - **Validates: Requirements 4.2, 4.3, 4.4, 4.5**
    - `mobile/test/properties/notification_category_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 9: Category filtering is an order-preserving, idempotent subsequence`

  - [ ]* 7.4 Write property test for derived unread counts
    - **Property 10: Per-category unread counts are derived from row state**
    - **Validates: Requirements 4.7, 4.11, 1.7**
    - `mobile/test/properties/notification_category_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 10: Per-category unread counts are derived from row state`

  - [ ]* 7.5 Write property test for selection persistence across sessions
    - **Property 12: Filter selection survives the session and resets across sessions**
    - **Validates: Requirements 4.9**
    - `mobile/test/properties/notification_category_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 12: Filter selection survives the session and resets across sessions`

  - [x] 7.6 Implement the empty and error states
    - `mobile/lib/features/notifications/notifications_screen.dart`: `KEmptyState` with a
      display-serif headline of at most 40 characters, one sentence of at most 160 characters and
      exactly one "Show all" action returning the selection to `All`, with the filter rail still
      rendered
    - On load failure keep the previously rendered list and the selected chip and render `KErrorState`
      with exactly one retry action
    - _Requirements: 4.6, 4.10_

  - [ ]* 7.7 Write property test for the empty state
    - **Property 11: Every empty selection yields a bounded, recoverable empty state**
    - **Validates: Requirements 4.6**
    - `mobile/test/properties/notification_category_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 11: Every empty selection yields a bounded, recoverable empty state`

  - [ ]* 7.8 Write property test for load-failure preservation
    - **Property 13: A load failure preserves the rendered list and the selection**
    - **Validates: Requirements 4.10**
    - `mobile/test/properties/notification_category_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 13: A load failure preserves the rendered list and the selection`

  - [x] 7.9 Add the filter live-region announcer
    - `mobile/lib/features/notifications/notifications_screen.dart`: a `Semantics(liveRegion: true)`
      announcer publishing "{category}, {n} notifications" exactly once per settled selection change,
      within 1 second of the rendered list settling
    - _Requirements: 16.9_

  - [ ]* 7.10 Write widget tests for the rail layout and indicator
    - `mobile/test/notifications_screen_test.dart`: the 12-chip rail layout with horizontal scrolling
      and tap targets (4.1), and the filter indicator animation including re-selection of the
      already-selected chip (4.8)
    - _Requirements: 4.1, 4.8_

- [x] 8. Call ICE resolution and feature availability
  - [x] 8.1 Make ICE resolution degrade instead of throwing
    - `mobile/lib/features/chat/calls/call_config.dart`: replace the `StateError` throw in
      `KlectCallIce.resolve()` with an `IceResolution { configuration, relayAvailable, failure }`
    - Order every STUN entry before every relay entry and truncate the list to 8 entries by discarding
      the tail of that order
    - Cap the whole resolution at `KlectCallTimings.iceConfigTimeout` (5 s); on failure or timeout
      build a STUN-only configuration, set `relayAvailable: false`, and issue no further
      `turn-credentials` request for that call id
    - Replace the mutable static `hasTurn` with the per-resolution `relayAvailable` flag carried into
      `ActiveCallState` so sequential calls cannot inherit each other's verdict
    - Record the verdict once per call id through the `record_call_diagnostic` RPC and surface the
      non-blocking carrier-network warning in the Call_Screen
    - _Requirements: 10.1, 10.3, 10.4, 10.5_

  - [ ]* 8.2 Write property test for ICE configuration
    - **Property 33: ICE configuration is ordered, capped and degrades instead of failing**
    - **Validates: Requirements 10.1, 10.3, 10.4, 10.5**
    - `mobile/test/properties/call_ice_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over generated ICE lists mixing complete, partial and empty relay entries, plus error and
      late-response cases driven by `fakeAsync`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 33: ICE configuration is ordered, capped and degrades instead of failing`

  - [x] 8.3 Implement the session-scoped call availability provider
    - New `mobile/lib/features/chat/calls/call_availability.dart` with
      `CallAvailability extends Notifier<bool>` and `refreshIfStale()`
    - Read `call_feature_enabled` on session start; re-read on foreground only when the previous
      successful read is at least 5 minutes old; the last successful read wins
    - An error or a 10 s timeout resolves to `false` with no error surfaced; while disabled no
      `start_call` RPC is issued, an arriving `calls` row and a call deep link are held at `idle`, and
      no call affordance is presented
    - _Requirements: 10.6, 10.7, 10.8_

  - [ ]* 8.4 Write property test for call availability
    - **Property 34: Call availability is the most recent successful read and fails closed**
    - **Validates: Requirements 10.6, 10.7**
    - `mobile/test/properties/call_ice_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over foreground-event and RPC-outcome sequences under `fakeAsync`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 34: Call availability is the most recent successful read and fails closed`

- [x] 9. Call lifecycle state machine
  - [x] 9.1 Add the guarded phase machine
    - `mobile/lib/features/chat/calls/call_controller.dart`: declare `allowedTransitions` exactly as
      the design's transition set, route every state write through
      `bool _transition(CallPhase next, {String? endReason})`, and reject every outgoing edge from
      `ended` so it is absorbing per call id; `dismiss()` constructs a new `ActiveCallState` rather
      than transitioning out of `ended`
    - Enter `dialing` within 1 s of a successful `start_call` and publish the local session description
      through `send_call_signal`; enter `incoming` for a `ringing` row addressed to the account only
      when no live call is held; enter `active` on a connected peer connection with elapsed duration
      starting at zero at that transition
    - Add the `relayAvailable`, `chromeVisible` and `remoteFrameStaleSince` fields to
      `ActiveCallState`
    - _Requirements: 7.1, 7.2, 7.3, 7.9, 7.10_

  - [ ]* 9.2 Write property test for phase transitions
    - **Property 22: Call phase transitions are legal and ended is absorbing**
    - **Validates: Requirements 7.9, 7.10, 7.1, 7.2, 7.3**
    - `mobile/test/properties/call_lifecycle_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over generated call event sequences with `FakeChatApi` and
      `FakePeerConnection`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 22: Call phase transitions are legal and ended is absorbing`

  - [x] 9.3 Implement every termination path and its timeout
    - `mobile/lib/features/chat/calls/call_controller.dart`: arm the 45 s ring timeout from
      `call.createdAt` rather than the local arm time, for `incoming` as well as `dialing`, ending with
      a missed reason; add the 30 s connect timeout ending with `p_outcome = 'failed'` and zero
      duration; wrap `answer_call` in a 15 s timeout ending with a failed reason, released tracks and a
      surfaced error; end with a declined reason within 1 s of a decline regardless of the RPC outcome
    - Pass `p_client_elapsed_seconds` (whole seconds, clamped to `[0, 86400]`, zero when the call never
      became `active`) through `ChatApi.updateCallStatus`; the stored duration stays server-computed
    - Guard with `_closing` plus `ended` absorption so at most one `end_call` is issued per call id,
      and release every local audio and video track on every termination path
    - _Requirements: 7.4, 7.5, 7.7, 7.8, 7.11, 7.14, 7.15_

  - [ ]* 9.4 Write property test for termination paths
    - **Property 23: Every termination path ends once, releases media and reports a clamped duration**
    - **Validates: Requirements 7.4, 7.5, 7.7, 7.8, 7.11, 7.14, 7.15**
    - `mobile/test/properties/call_lifecycle_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; `fakeAsync` drives the 45 s / 30 s / 25 s / 15 s budgets
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 23: Every termination path ends once, releases media and reports a clamped duration`

  - [x] 9.5 Bound the reconnection window
    - `mobile/lib/features/chat/calls/call_controller.dart`: replace the `_restartedIce` bool with an
      `_iceRestarts` counter capped at 3, each attempt spaced at least
      `KlectCallTimings.reconnectGrace` (4 s) apart, all inside one 25 s `reconnecting` budget;
      explicitly retain the local and remote media tracks for the whole window; leave `reconnecting`
      only by returning to `active` or by ending after 25 s
    - _Requirements: 7.6_

  - [ ]* 9.6 Write property test for bounded reconnection
    - **Property 24: Reconnection is bounded and non-destructive**
    - **Validates: Requirements 7.6**
    - `mobile/test/properties/call_lifecycle_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over disconnect and recovery timelines
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 24: Reconnection is bounded and non-destructive`

  - [x] 9.7 Protect a held call from other calls and from navigation
    - `mobile/lib/features/chat/calls/call_controller.dart`: `IncomingCallController._offer` calls
      `decline_call(newCallId, reason: 'busy')` instead of returning silently, leaving the held call's
      phase and media tracks untouched
    - `attach(callId)` returns immediately for the held call id in any non-idle phase, issuing no
      further `start_call` or `answer_call`
    - `mobile/lib/features/chat/calls/call_screen.dart`: `onPopInvoked` stops calling `hangUp()`, so
      the system back gesture retains the phase and its tracks, issues no `end_call`, and lets the
      Call_Pill appear within 1 s; only the explicit end control ends a call
    - _Requirements: 7.12, 7.13, 7.16, 9.13_

  - [ ]* 9.8 Write property test for held-call protection
    - **Property 25: A held call is never disturbed by another call or by navigation**
    - **Validates: Requirements 7.12, 7.13, 7.16, 9.13**
    - `mobile/test/properties/call_lifecycle_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 25: A held call is never disturbed by another call or by navigation`

  - [ ]* 9.9 Write unit tests for the call happy paths
    - `mobile/test/call_controller_test.dart`: `place()` reaching `dialing` and publishing the local
      description (7.1), and `accept()` reaching `connecting` then `active` with elapsed duration
      starting at zero (7.3)
    - _Requirements: 7.1, 7.3_

- [x] 10. Checkpoint - call engine
  - Ensure all tests pass, ask the user if questions arise.

- [x] 11. Call entry points in a chat thread
  - [x] 11.1 Consolidate stable error identifiers into one total mapping
    - Rename `mobile/lib/features/chat/group_errors.dart` to
      `mobile/lib/features/chat/error_copy.dart` and make it one total mapping from stable snake_case
      identifiers to human copy with a generic fallback
    - Calls: `calls_unavailable`, `calls_not_allowed`, `not_allowed`, `blocked`, `busy`,
      `participant_busy`, `conversation_busy`, `not_dm_member`, `call_not_found`, `call_not_ringing`,
      `call_expired`, `caller_cannot_answer`, `not_call_participant`
    - Groups: `not_admin`, `not_owner`, `not_allowed`, `group_policy_denied`, `not_group`,
      `not_member`, `title_required`, `group_needs_members`, `request_not_found`
    - Messages: `not_message_author`, `message_not_found`, `not_member`
    - Preferences: `auth_required`, `bad_notification_preferences`
    - _Requirements: 6.7, 13.11_

  - [ ]* 11.2 Write property test for error identifier mapping
    - **Property 46: Group error identifiers map totally to human copy**
    - **Validates: Requirements 13.11**
    - `mobile/test/properties/group_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over the named identifiers plus arbitrary unknown identifiers
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 46: Group error identifiers map totally to human copy`

  - [x] 11.3 Make call affordance visibility and enablement one predicate
    - `mobile/lib/features/chat/conversation_screen.dart`: drop the private `autoDispose`
      `FutureProvider` and watch `callAvailabilityProvider`; `canCall` becomes
      `!isGroup && callsEnabled && !activeCall.isBusy && !_startInFlight`
    - Render the voice and video actions only for a `dm` conversation with a resolved-enabled gate;
      while a call is held or a request is outstanding render them disabled with that state exposed to
      assistive technology rather than removing them; each action carries a text alternative naming its
      call kind and a `Layout.tapTargetMin` hit target; activation in any non-enabled or disabled state
      issues no `start_call` RPC
    - _Requirements: 6.1, 6.2, 6.3, 6.8, 6.10, 10.8_

  - [ ]* 11.4 Write property test for affordance visibility and enablement
    - **Property 19: Call affordance visibility and enablement are one predicate**
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.8, 6.10, 10.8**
    - `mobile/test/properties/call_lifecycle_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over conversation kind, gate state, held phase and outstanding
      request state
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 19: Call affordance visibility and enablement are one predicate`

  - [x] 11.5 Gate call creation behind permission requests
    - `mobile/lib/features/chat/conversation_screen.dart`: `_startCall` requests microphone permission
      for a voice call, and each of microphone and camera permission not already granted for a video
      call, before any `start_call` RPC is issued
    - On denial surface a message naming the denied permission and the call kind it blocks with exactly
      one action opening the app's system settings, issue no `start_call`, keep the thread as the
      current route and retain the composer contents
    - _Requirements: 6.4, 6.5, 6.9_

  - [ ]* 11.6 Write property test for permission gating
    - **Property 20: Permissions are requested before, and gate, call creation**
    - **Validates: Requirements 6.4, 6.5, 6.9**
    - `mobile/test/properties/call_lifecycle_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over call kinds and every combination of already-granted
      permissions
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 20: Permissions are requested before, and gate, call creation`

  - [x] 11.7 Make call creation failure recoverable and non-navigating
    - `mobile/lib/features/chat/conversation_screen.dart`: wrap `start_call` in a 15 s timeout; on
      success push exactly one Call_Screen for the returned call id; on any failure push none, surface
      exactly one message mapped through `error_copy.dart` (with the generic fallback for an
      unrecognised identifier), and return both call actions to their enabled state; disable both
      actions while a permission or `start_call` request is outstanding so at most one `start_call` is
      in flight per thread
    - _Requirements: 6.6, 6.7, 6.11_

  - [ ]* 11.8 Write property test for call creation outcomes
    - **Property 21: Call creation failure never navigates and always recovers**
    - **Validates: Requirements 6.6, 6.7, 6.11**
    - `mobile/test/properties/call_lifecycle_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over success, each stable identifier, an unrecognised identifier
      and a 15 s timeout under `fakeAsync`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 21: Call creation failure never navigates and always recovers`

- [x] 12. Call surfaces: screen controls, duration, pill and background ringing
  - [x] 12.1 Implement the duration helpers
    - New `mobile/lib/features/chat/calls/call_duration.dart` with
      `formatCallDuration(Duration)` producing `m:ss` below one hour and `h:mm:ss` at or above one
      hour, and `parseCallDuration(String)` as its inverse; rendered through the tabular count style
    - _Requirements: 8.10, 8.12, 9.2_

  - [ ]* 12.2 Write property test for duration formatting and monotonicity
    - **Property 30: Duration formatting round-trips and never goes backwards**
    - **Validates: Requirements 8.10, 8.11, 8.12, 9.2**
    - `mobile/test/properties/call_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over 0..86,399 seconds and over tick/phase-change sequences
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 30: Duration formatting round-trips and never goes backwards`

  - [x] 12.3 Implement the in-call control set and its rollback
    - `mobile/lib/features/chat/calls/call_screen.dart`: mute, speaker, camera-enable, camera-flip,
      minimize and end controls for the phases and call kinds that support them, each with a
      `Layout.tapTargetMin` hit target and an assistive-technology label naming the control, its
      enabled or disabled state and its current on or off state
    - Mute and camera-enable toggle the local track enabled flag within 300 ms and reflect the result in
      glyph fill, visible label and assistive label; speaker switches output within 300 ms and retains
      the selection across every phase change until `ended`; camera-flip switches facing within 1 s and
      mirrors the local preview only while front-facing; camera-flip is disabled and performs no facing
      change while the local video track is disabled, with that disabled state exposed
    - Camera controls are absent from both the widget tree and the assistive-technology focus order for
      audio calls
    - A control that fails or does not complete within 1 s retains the last successfully applied state,
      surfaces exactly one message and leaves the phase unchanged
    - _Requirements: 8.1, 8.2, 8.3, 8.7, 8.8, 8.9, 8.13, 8.16, 8.17_

  - [ ]* 12.4 Write property test for control involutions
    - **Property 26: In-call controls are involutions and their state is fully reflected**
    - **Validates: Requirements 8.2, 8.3, 8.7, 8.9, 8.13**
    - `mobile/test/properties/call_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 26: In-call controls are involutions and their state is fully reflected`

  - [ ]* 12.5 Write property test for control failure rollback
    - **Property 27: Control failures roll back without touching the call**
    - **Validates: Requirements 8.17**
    - `mobile/test/properties/call_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; `fakeAsync` drives the 1 s apply budget
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 27: Control failures roll back without touching the call`

  - [ ]* 12.6 Write property test for the rendered control set
    - **Property 28: Call surfaces present exactly the controls the call kind and phase support**
    - **Validates: Requirements 8.1, 8.14, 8.16, 8.18**
    - `mobile/test/properties/call_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over every (call kind, live phase) pair
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 28: Call surfaces present exactly the controls the call kind and phase support`

  - [x] 12.7 Implement the video surface, chrome toggling and the phase announcer
    - `mobile/lib/features/chat/calls/call_screen.dart`: render the remote track full-bleed and retain
      the most recently received frame for the whole `reconnecting` period; fall back to the Token_Set
      sunken surface with the peer name and an unavailable status when no remote video track exists or
      no frame has arrived for 3 consecutive seconds
    - Render the local preview as a draggable inset clamped so every edge stays inside the safe area by
      at least the Token_Set inset spacing, hidden entirely while the local video track is disabled
    - Audio calls render the peer avatar, display name and call status in place of remote video
    - A background tap during an active video call toggles the control cluster, peer name and duration
      within `KDurations.deliberate`, keeping hidden chrome both non-activatable and excluded from the
      focus order; a phase change restores chrome within the same envelope
    - A `Semantics(liveRegion: true)` announcer names the resulting phase within 1 s of each change and
      at most once per change, using the Token_Set warning colour for `reconnecting`
    - _Requirements: 8.4, 8.5, 8.6, 8.14, 8.15, 8.18_

  - [ ]* 12.8 Write property test for the remote video fallback
    - **Property 29: Remote video falls back deterministically**
    - **Validates: Requirements 8.4, 8.5**
    - `mobile/test/properties/call_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over remote-frame arrival timelines, drag targets and safe-area
      insets
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 29: Remote video falls back deterministically`

  - [x] 12.9 Implement the call pill and its overlay host
    - New `mobile/lib/features/chat/widgets/call_pill.dart`: a `ConsumerWidget` rendering the peer
      display name truncated to 24 characters, the phase label and the ticking duration
      (`mm:ss` below 60 minutes, `h:mm:ss` from 60 minutes), refreshed at least once per second,
      anchored `Layout.bottomBarHeight` above the bottom edge at `Layout.callPillHeight` without
      covering the bottom navigation bar
    - Rename `IncomingCallOverlay` to `CallOverlayHost` in `mobile/lib/app.dart` and render the pill
      whenever the engine is busy and the current route is not `/call/:id`
    - A tap pushes `/call/{id}` within 300 ms preserving the elapsed duration continuously; minimizing
      pops the Call_Screen within 300 ms, keeps the remote audio track enabled and keeps the microphone
      in the mute state it held at that moment; within 1 s of `ended` the pill is absent and reserves no
      layout space
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

  - [ ]* 12.10 Write property test for the call pill
    - **Property 31: The call pill mirrors engine state exactly**
    - **Validates: Requirements 9.3, 9.4, 9.5**
    - `mobile/test/properties/call_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 31: The call pill mirrors engine state exactly`

  - [x] 12.11 Implement the call-style system notification and its guarded actions
    - New `mobile/lib/features/chat/calls/call_notifications.dart` wrapping `LocalNotifications` with a
      CallStyle full-screen-intent notification on the Android `calls` channel at high priority,
      carrying exactly two `AndroidNotificationAction`s (`call_accept`, `call_decline`) keyed by call id
    - Action handling re-reads the call status first: it refuses when the status is no longer `ringing`
      or when another call is live, always cancels the notification, invokes neither RPC on refusal, and
      surfaces exactly one message
    - Cancel on any status change within 2 s, and on RPC failure or a 10 s timeout cancel the
      notification, leave the call at its server-reported status with no local override, and surface one
      message
    - _Requirements: 9.6, 9.7, 9.8, 9.9, 9.11, 9.12, 9.13_

  - [ ]* 12.12 Write property test for notification action guards
    - **Property 32: Call notification actions are guarded by server status**
    - **Validates: Requirements 9.7, 9.8, 9.9, 9.11, 9.12**
    - `mobile/test/properties/call_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over call row status, held phase and RPC outcome under `fakeAsync`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 32: Call notification actions are guarded by server status`

  - [ ]* 12.13 Write widget tests for call surface examples
    - `mobile/test/call_screen_test.dart`: the audio-call layout rendering avatar, name and status in
      place of remote video (8.6), and minimize geometry placing the pill directly above the bottom
      navigation bar without covering it (9.1)
    - _Requirements: 8.6, 9.1_

- [x] 13. Checkpoint - call surfaces
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. Message deletion: tombstone and delete-for-me
  - [x] 14.1 Open the read path and add the deletion RPC wrappers
    - `mobile/lib/features/chat/chat_api.dart`: remove the `deleted_at is null` filter from the
      `_messageSelect` region, `fetchMessages` and `fetchMessage` so a tombstone survives restart and
      pagination; keep the filter in `searchMessages`
    - Mirror the same read-path change in `mobile/lib/core/klect_api.dart` `fetchMessages`
    - Add `deleteMessageForEveryone(messageId)` over the `delete_message_for_everyone` RPC,
      `hideMessageForMe(messageId)` over `hide_message_for_me`, and
      `fetchHiddenMessageIds(conversationId)` reading the viewer's own `message_hides` rows through RLS
    - Add the derived `ChatMessage.isTombstone` and `hiddenForMe` getters in
      `mobile/lib/core/models/messaging.dart`; no new columns
    - _Requirements: 11.1, 11.13, 12.5, 12.7_

  - [ ]* 14.2 Write property test for the stored tombstone shape
    - **Property 35: Deleting for everyone preserves identity and clears content**
    - **Validates: Requirements 11.1, 11.3, 11.7, 11.9, 11.13**
    - `mobile/test/properties/message_deletion_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over messages and repeated deletions
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 35: Deleting for everyone preserves identity and clears content`

  - [x] 14.3 Replace deleted messages in place in the thread controller
    - `mobile/lib/features/chat/thread_controller.dart`: `_onMessageUpdate` stops calling
      `_removeMessage` when `deleted_at` appears and replaces the message in place, preserving thread
      order and the original timestamp
    - Rename `delete(messageId)` to `deleteForEveryone(messageId)`: apply an optimistic tombstone, and
      on failure or a 10 s timeout restore the original body and attachment set exactly, leave the
      stored state unchanged, and surface one retry-carrying error
    - _Requirements: 11.6, 11.12_

  - [ ]* 14.4 Write property test for in-place propagation
    - **Property 37: A committed delete propagates in place**
    - **Validates: Requirements 11.6, 11.8**
    - `mobile/test/properties/message_deletion_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over threads and deleted-message positions
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 37: A committed delete propagates in place`

  - [ ]* 14.5 Write property test for confirmation and failure reversal
    - **Property 38: Destructive message actions are confirmed and reversible on failure**
    - **Validates: Requirements 11.11, 11.12, 12.2, 12.4**
    - `mobile/test/properties/message_deletion_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; `fakeAsync` drives the 10 s delete timeout
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 38: Destructive message actions are confirmed and reversible on failure`

  - [x] 14.6 Implement delete-for-me state and hidden-page filling
    - `mobile/lib/features/chat/thread_controller.dart`: `hideForMe(messageId)` removes the message from
      the rendered thread within 500 ms and rolls back on failure while retaining not-hidden stored
      state; `_hidden` is loaded with the first page and re-applied to every subsequent page and every
      realtime insert so a hidden message stays hidden across restart, re-sign-in, repeated pagination,
      edits and reactions
    - A message the viewer has hidden stays hidden rather than rendering a tombstone when the author
      later deletes it for everyone
    - `_fillVisiblePage()` pages older history up to 10 consecutive times per user-initiated load,
      stopping at the first visible message or at exhausted history; an empty visible thread renders the
      empty-thread state with the composer still enabled
    - _Requirements: 12.3, 12.4, 12.5, 12.6, 12.9, 12.10_

  - [ ]* 14.7 Write property test for delete-for-me isolation and precedence
    - **Property 39: Delete-for-me is isolated, idempotent and takes precedence**
    - **Validates: Requirements 12.1, 12.3, 12.6, 12.7**
    - `mobile/test/properties/message_deletion_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over two accounts and both orderings of hide and delete-for-everyone
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 39: Delete-for-me is isolated, idempotent and takes precedence`

  - [ ]* 14.8 Write property test for hidden-state durability
    - **Property 40: Hidden state survives every subsequent event**
    - **Validates: Requirements 12.5**
    - `mobile/test/properties/message_deletion_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over restart, sign-out/sign-in, repeated pagination, edit and
      reaction sequences
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 40: Hidden state survives every subsequent event`

  - [ ]* 14.9 Write property test for bounded hidden-page filling
    - **Property 41: Hidden pages are skipped, bounded and terminating**
    - **Validates: Requirements 12.9**
    - `mobile/test/properties/message_deletion_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over arbitrary hidden-message patterns
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 41: Hidden pages are skipped, bounded and terminating`

  - [x] 14.10 Render the tombstone and the unavailable reply target
    - `mobile/lib/features/chat/widgets/message_bubble.dart`: a `_Tombstone` branch when
      `message.deletedAt != null` rendering a non-interactive row with a label of at most 40 characters
      and the original timestamp, no reactions, no attachment thumbnails or placeholders, no media open,
      no swipe-to-reply, and no navigation on tap, double tap or long press
    - A message whose reply target is deleted renders an unavailable label of at most 40 characters
      carrying no part of the deleted body, with the jump-to-original action disabled and that disabled
      state exposed to assistive technology
    - _Requirements: 11.2, 11.4, 11.5, 11.7_

  - [ ]* 14.11 Write property test for tombstone inertness
    - **Property 36: A tombstone renders inert and reveals nothing**
    - **Validates: Requirements 11.2, 11.4, 11.5**
    - `mobile/test/properties/message_deletion_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over deleted messages, viewers including the author, and tap,
      double tap and long press
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 36: A tombstone renders inert and reveals nothing`

  - [x] 14.12 Add both delete scopes to the message action sheet
    - `mobile/lib/features/chat/widgets/message_actions_sheet.dart`: `Delete for me` is present for
      every message state including another author's message, an already-tombstoned message and a
      pending or failed send; a tombstone's only action is delete-for-me
    - Both delete actions gate behind `KConfirmDialog` with scope-naming copy, and no delete request of
      either scope is issued before its confirmation is accepted
    - _Requirements: 11.11, 12.1, 12.2_

  - [x] 14.13 Render the deleted inbox preview
    - `mobile/lib/features/chat/inbox_controller.dart` and
      `mobile/lib/features/chat/widgets/conversation_tile.dart`: render the server-refreshed deleted
      preview label of at most 40 characters and leave the conversation's ordering timestamp untouched,
      reflecting the change within 3 s while realtime is connected
    - _Requirements: 11.8_

  - [ ]* 14.14 Write unit test for the fully hidden short thread
    - `mobile/test/message_deletion_test.dart`: a thread whose every message is hidden and which has no
      older history renders the empty-thread state with the composer still enabled (12.10)
    - _Requirements: 12.10_

- [x] 15. Group identity, permissions and enforcement
  - [x] 15.1 Implement group membership rendering and the widened role affordances
    - `mobile/lib/features/chat/group_info_screen.dart`: add the loading-indicator path so the screen
      renders content or a spinner immediately on open; render the avatar, title, description, the member
      count as an integer, and exactly one role badge from `{owner, admin, member}` per member for member
      lists of 2 to 256
    - Offer promotion of a `member` to `admin` and demotion of an `admin` to `member` to admins as well
      as the owner, never targeting the account whose role is `owner`
    - Keep ownership transfer, join-approval toggling, group deletion behind a confirmation step, and
      the three `edit_info` / `add_members` / `send_messages` scope settings owner-only; add-member
      capacity is 256 minus the active member count
    - Every change goes through the existing `set_group_policy`, `update_group_info`,
      `clear_group_avatar`, `set_group_join_approval` and `set_group_member_role` RPCs
    - _Requirements: 13.1, 13.2, 13.4, 13.5, 13.6, 13.11_

  - [ ]* 15.2 Write property test for role affordance authority
    - **Property 43: Group role affordances match the widened authority rules**
    - **Validates: Requirements 13.5, 13.6**
    - `mobile/test/properties/group_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over viewer role and target member role
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 43: Group role affordances match the widened authority rules`

  - [ ]* 15.3 Write property test for membership rendering
    - **Property 48: Group membership rendering is exact**
    - **Validates: Requirements 13.2, 13.4, 13.15**
    - `mobile/test/properties/group_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over member lists of size 2..256 with generated role distributions
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 48: Group membership rendering is exact`

  - [x] 15.4 Make unsatisfied affordances absent rather than invisible
    - `mobile/lib/features/chat/group_info_screen.dart`: every affordance the viewer's role does not
      satisfy is omitted from the widget tree so no hidden affordance is hit-testable; assert
      `GroupPermissionScope.allows` is monotone in role rank
    - _Requirements: 13.8, 13.10_

  - [ ]* 15.5 Write property test for scope monotonicity and affordance absence
    - **Property 42: Group permission scopes are monotone and hidden affordances are absent**
    - **Validates: Requirements 13.8, 13.10**
    - `mobile/test/properties/group_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over every scope and role combination
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 42: Group permission scopes are monotone and hidden affordances are absent`

  - [x] 15.6 Validate group identity input on trimmed values
    - `mobile/lib/features/chat/group_info_screen.dart`: accept a title of 1 to 60 characters after
      trimming, block a whitespace-only submission with a validation message naming the title
      requirement, keep the stored title unchanged, and accept a description of 0 to 500 characters
      after trimming
    - _Requirements: 13.3, 13.16_

  - [ ]* 15.7 Write property test for identity validation
    - **Property 44: Group identity input is validated on trimmed values**
    - **Validates: Requirements 13.3, 13.16**
    - `mobile/test/properties/group_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over generated titles including whitespace-only, boundary-length,
      emoji-cluster and RTL strings
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 44: Group identity input is validated on trimmed values`

  - [x] 15.8 Reconcile on success and roll back on failure
    - `mobile/lib/features/chat/group_info_screen.dart`: on success refetch the conversation record and
      member list within 2 s so every rendered value equals the refetched value; on failure, an
      unrecognised error identifier or a 10 s timeout restore the pre-change rendered values exactly,
      surface a not-saved message mapped through `error_copy.dart`, and keep the affordance enabled for
      retry
    - _Requirements: 13.12, 13.13_

  - [ ]* 15.9 Write property test for group state reconciliation
    - **Property 45: Group state reconciles on success and rolls back on failure**
    - **Validates: Requirements 13.12, 13.13**
    - `mobile/test/properties/group_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)`; `fakeAsync` drives the 10 s budget
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 45: Group state reconciles on success and rolls back on failure`

  - [x] 15.10 Enforce the send scope in the composer
    - `mobile/lib/features/chat/conversation_screen.dart`: when
      `groupPolicy.sendMessages.allows(viewerRole)` is false replace `ChatComposer` with a read-only
      notice naming the governing scope value, with the message send, attachment and voice-note entry
      points all absent from the widget tree
    - _Requirements: 13.9_

  - [ ]* 15.11 Write property test for the composer lockout
    - **Property 47: The group composer reflects the send scope**
    - **Validates: Requirements 13.9**
    - `mobile/test/properties/group_controls_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over member role and `send_messages` scope
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 47: The group composer reflects the send scope`

  - [x] 15.12 Wire the group report action and identity system messages
    - `mobile/lib/features/chat/group_info_screen.dart`: a report action for a group conversation
      submitting through the `submit_report` RPC
    - Render each system message describing an avatar, title or description change once at its creation
      position in thread order
    - _Requirements: 13.14, 13.15_

  - [ ]* 15.13 Write widget tests for group navigation and reporting
    - `mobile/test/group_info_test.dart`: tapping a group thread header opens the Group_Info_Screen
      rendering content or a loading indicator (13.1), and the report action submits through
      `submit_report` (13.14)
    - _Requirements: 13.1, 13.14_

- [x] 16. Swipeable sibling tab navigation
  - [x] 16.1 Implement the tab pager core, physics and indicator
    - New `mobile/lib/ui/k_tab_pager.dart`: `KTabPager({tabs, selectedIndex, onSelected, builder,
      routeParam})` rendering exactly one member across the full viewport width at rest for 2 to 6
      members, accepting no paging drag below two members
    - Commit on cumulative displacement of at least `Motion.pageCommitFraction` of the viewport width or
      release velocity of at least `Motion.flingVelocityMin`, settling within `KDurations.deliberate`;
      otherwise settle back on the originating member leaving the selection and every member's scroll
      offset unchanged
    - Indicator position is a pure function of `PageController.page` so it tracks the drag fraction
      linearly between the originating and adjacent label positions, and only the settle sets selection
    - A custom `ScrollPhysics` clamps overscroll travel to `Motion.pagerOverscrollMax` and never wraps;
      the selected index stays within `[0, length - 1]` at all times including mid-drag and mid-animation
    - Under reduced motion the page change is a 90 ms opacity fade with no slide transform and the
      indicator moves within 90 ms, with drag tracking and the commit threshold unchanged
    - _Requirements: 14.1, 14.2, 14.3, 14.5, 14.10, 14.11, 14.12_

  - [ ]* 16.2 Write property test for selection, page and indicator agreement
    - **Property 49: Pager selection, page and indicator always agree**
    - **Validates: Requirements 14.1, 14.5, 14.6**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over tap and drag sequences including taps during a running settle
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 49: Pager selection, page and indicator always agree`

  - [ ]* 16.3 Write property test for the paging commit threshold
    - **Property 50: Paging commits on a pure threshold decision**
    - **Validates: Requirements 14.2, 14.4, 14.10, 14.11**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over generated drag traces with reduced motion both on and off
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 50: Paging commits on a pure threshold decision`

  - [ ]* 16.4 Write property test for indicator tracking
    - **Property 51: The indicator tracks the drag fraction linearly**
    - **Validates: Requirements 14.3**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over in-progress drag fractions in `[0, 1]`
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 51: The indicator tracks the drag fraction linearly`

  - [ ]* 16.5 Write property test for edge drags
    - **Property 52: Edge drags neither move nor wrap**
    - **Validates: Requirements 14.12**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over drag distances beyond the first and last member
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 52: Edge drags neither move nor wrap`

  - [x] 16.6 Preserve per-member scroll offset and loaded pages
    - `mobile/lib/ui/k_tab_pager.dart`: `AutomaticKeepAlive` plus a `PageStorageKey` per page so each
      member's scroll offset is restored to within 1 logical pixel and its already-loaded pages are
      restored without refetching, for the lifetime of the enclosing route
    - _Requirements: 14.7_

  - [ ]* 16.7 Write property test for pager state preservation
    - **Property 53: Pager state is preserved across visits**
    - **Validates: Requirements 14.7**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over member-visit sequences and scroll offsets
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 53: Pager state is preserved across visits`

  - [x] 16.8 Implement visibility filtering and route-parameter restoration
    - `mobile/lib/ui/k_tab_pager.dart`: filter hidden members before paging, preserving relative order,
      and select the first remaining member when the previously selected member is excluded
    - A `routeParam` naming a member of the pageable set opens on it with no page or indicator animation;
      an empty, absent or unknown value opens on the first member with no error surfaced
    - _Requirements: 14.8, 14.9, 14.13_

  - [ ]* 16.9 Write property test for visibility filtering
    - **Property 54: Visibility filtering preserves order and repairs selection**
    - **Validates: Requirements 14.8**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over generated visibility masks
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 54: Visibility filtering preserves order and repairs selection`

  - [ ]* 16.10 Write property test for route parameter handling
    - **Property 55: Tab route parameters round-trip and degrade silently**
    - **Validates: Requirements 14.9, 14.13**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over valid, empty, absent and unknown parameter values
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 55: Tab route parameters round-trip and degrade silently`

  - [x] 16.11 Implement the horizontal drag guard and publish claims
    - `mobile/lib/ui/k_tab_pager.dart`: `KHorizontalDragGuard extends InheritedNotifier<HorizontalDragClaims>`;
      while any claim is held the pager uses `NeverScrollableScrollPhysics` and accepts horizontal drags
      again within 120 ms of the last claim being released
    - Publish claims from `mobile/lib/features/closeup/closeup_screen.dart`,
      `mobile/lib/features/item/item_screen.dart` and
      `mobile/lib/features/chat/widgets/swipe_actions.dart` so a pointer sequence beginning inside a
      media pager, a swipe-to-reply drag or a conversation-tile swipe is yielded whole and leaves the
      selected index unchanged for any drag distance
    - A sequence whose vertical displacement exceeds its horizontal displacement when total displacement
      first exceeds 18 logical pixels goes to the enclosing vertical scrollable through the standard
      gesture arena
    - _Requirements: 15.2, 15.3, 15.4, 15.8, 15.9, 15.10_

  - [ ]* 16.12 Write property test for single-consumer pointer arbitration
    - **Property 56: At most one consumer responds to a pointer sequence**
    - **Validates: Requirements 15.2, 15.3, 15.4, 15.8, 15.9, 15.10**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over pointer sequences across threads and feeds inside a pager
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 56: At most one consumer responds to a pointer sequence`

  - [x] 16.13 Adopt the pager on the sibling tab surfaces
    - `mobile/lib/features/pulse/pulse_screen.dart` (For you / Following),
      `mobile/lib/features/profile/profile_screen.dart` (`_TabBarDelegate` keeps rendering the rail while
      the pager takes over the body), `mobile/lib/features/chat/messages_screen.dart` (inbox filters) and
      the Surf filter rail
    - Tapping a non-selected label animates both the page and the indicator within
      `KDurations.deliberate` for any number of members between the selected and tapped member
    - Leave `mobile/lib/app/root_shell.dart` and the five root bottom-bar destinations untouched, and
      leave the existing `KGestureRegion` tap/double-tap/long-press arbitration on cards unmodified
    - _Requirements: 14.4, 14.6, 15.1_

  - [ ]* 16.14 Write property test for gesture-contract parity
    - **Property 57: Card gestures classify identically inside and outside a pager**
    - **Validates: Requirements 15.1, 15.6, 15.7, 15.11**
    - `mobile/test/properties/tab_pager_properties_test.dart`, glados `ExploreConfig(numRuns: 100)`
      over single taps, second taps within 300 ms and 18 logical pixels, and 500 ms presses with at most
      and more than 18 logical pixels of movement
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 57: Card gestures classify identically inside and outside a pager`

- [x] 17. Accessibility and token compliance sweep
  - [x] 17.1 Bring the seven new surfaces to the accessibility floor
    - Audit and fix `mobile/lib/ui/k_banner.dart`, the Alert Center filter rail in
      `mobile/lib/features/notifications/notifications_screen.dart`,
      `mobile/lib/features/chat/calls/call_screen.dart`,
      `mobile/lib/features/chat/widgets/call_pill.dart`, the tombstone in
      `mobile/lib/features/chat/widgets/message_bubble.dart`,
      `mobile/lib/features/chat/group_info_screen.dart` and `mobile/lib/ui/k_tab_pager.dart`
    - Contrast: at least 4.5:1 for text below 24 logical pixels regular or 19 logical pixels bold and at
      least 3:1 for larger text, icon glyphs and selection indicators, in both themes and in the rest,
      selected, pressed and error states, excluding disabled targets
    - Targets and labels: every interactive target at least 44 by 44 logical pixels including hit slop,
      and every label-less target exposing a text alternative naming its action and its enabled or
      disabled state
    - Non-colour state: every selected/unselected, on/off and enabled/disabled pair differs in glyph
      fill, glyph shape or visible text label in addition to any colour difference
    - Text scaling: no label overflow and no element overlap from scale factor 1.0 through 2.0
    - Every animation this feature adds takes a Token_Set duration in `[90, 480]` ms and a Token_Set
      curve, replaced by a 90 ms opacity fade under reduced motion
    - _Requirements: 16.2, 16.3, 16.5, 16.6, 16.10_

  - [ ]* 17.2 Write property test for the contrast floor
    - **Property 58: Every new surface meets the contrast floor**
    - **Validates: Requirements 16.2**
    - `mobile/test/properties/accessibility_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over foreground/surface token pairs, both themes and the four states
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 58: Every new surface meets the contrast floor`

  - [ ]* 17.3 Write property test for targets, labels and text scaling
    - **Property 59: Targets, labels and layout survive text scaling**
    - **Validates: Requirements 16.3, 16.10**
    - `mobile/test/properties/accessibility_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over text scale factors in `[1.0, 2.0]` and generated label lengths
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 59: Targets, labels and layout survive text scaling`

  - [ ]* 17.4 Write property test for non-colour state legibility
    - **Property 60: State is legible without colour**
    - **Validates: Requirements 16.5**
    - `mobile/test/properties/accessibility_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over distinguishable state pairs on the banner, call screen, call
      pill and tab pager
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 60: State is legible without colour`

  - [ ]* 17.5 Write property test for the animation envelope
    - **Property 61: Added animations stay inside the token envelope**
    - **Validates: Requirements 16.6**
    - `mobile/test/properties/accessibility_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over every animation this feature adds, with reduced motion on and
      off
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 61: Added animations stay inside the token envelope`

  - [ ]* 17.6 Write property test for live-region announcements
    - **Property 62: Live regions announce once per change**
    - **Validates: Requirements 8.15, 16.4, 16.9**
    - `mobile/test/properties/accessibility_properties_test.dart`, glados
      `ExploreConfig(numRuns: 100)` over call phase change sequences and Alert Center selection change
      sequences
    - Tag: `// Feature: chat-calls-notifications-overhaul, Property 62: Live regions announce once per change`

- [x] 18. Final checkpoint - full suite green
  - Run `flutter analyze --no-pub` and resolve every info, warning and error; run one non-watching
    `flutter test` and `bash scripts/verify.sh` with no test added or changed by this feature skipped
  - Ensure all tests pass, ask the user if questions arise.
  - _Requirements: 16.7_

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP. They are the property,
  unit, widget and SQL-verification tests; skipping them ships the behaviour without its proof.
- Task 1.1 must land before any other task, because every subsequent widget task reads
  `motion.*` and `layout.callPillHeight` from the regenerated Token_Set rather than from a literal
  (Requirement 16.8).
- Tasks 2.1 through 2.3 all write the same migration file and are therefore scheduled in separate
  waves; they are three sections of one file, not three migrations.
- Per-category unread counts stay derived from the `read_at` column on loaded rows. No trigger and no
  counter column is added anywhere in this plan.
- Every write in this plan goes through an RPC or an RLS-protected table. The only service-role reads
  are inside `push-fanout`, which no client can reach.
- Call-protocol timings (45 s ring, 30 s connect, 25 s reconnect, 15 s answer/start, 5 s ICE) stay in
  `KlectCallTimings`; they are network protocol, not motion, and are deliberately outside the 480 ms
  animation cap.
- Turning on the `reliable_calls` flag and configuring the Cloudflare TURN secrets are operator
  actions and are deliberately outside this coding plan. Tasks 8.1 and 8.3 make the client correct in
  both the configured and unconfigured states.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.3", "2.1"] },
    { "id": 1, "tasks": ["1.2", "2.2"] },
    { "id": 2, "tasks": ["2.3", "3.1"] },
    { "id": 3, "tasks": ["2.4", "3.2", "3.3", "4.1", "5.1", "8.1", "9.1", "11.1", "16.1"] },
    { "id": 4, "tasks": ["3.4", "3.8", "5.2", "5.5", "7.2", "8.2", "8.3", "9.2", "9.3", "11.2", "12.1", "14.1", "15.1", "16.2"] },
    { "id": 5, "tasks": ["3.5", "3.9", "5.3", "5.7", "7.1", "8.4", "9.4", "9.5", "11.3", "12.2", "12.3", "14.2", "14.3", "15.2", "15.4", "16.3", "16.6"] },
    { "id": 6, "tasks": ["3.6", "5.4", "7.3", "7.6", "9.6", "9.7", "11.5", "12.4", "12.9", "14.4", "14.6", "14.10", "14.12", "14.13", "15.3", "15.6", "16.4", "16.8"] },
    { "id": 7, "tasks": ["3.7", "5.6", "5.11", "7.4", "7.9", "9.8", "11.7", "12.5", "12.7", "12.11", "14.5", "15.5", "15.8", "16.5", "16.11"] },
    { "id": 8, "tasks": ["4.2", "5.8", "7.5", "7.10", "11.4", "12.6", "14.7", "15.10", "15.12", "16.7", "16.13"] },
    { "id": 9, "tasks": ["5.9", "7.7", "9.9", "11.6", "12.8", "12.13", "14.8", "14.14", "15.9", "15.13", "16.9"] },
    { "id": 10, "tasks": ["5.10", "7.8", "11.8", "12.10", "14.9", "15.11", "16.10"] },
    { "id": 11, "tasks": ["5.12", "5.13", "12.12", "14.11", "16.12"] },
    { "id": 12, "tasks": ["16.14", "17.1"] },
    { "id": 13, "tasks": ["17.2"] },
    { "id": 14, "tasks": ["17.3"] },
    { "id": 15, "tasks": ["17.4"] },
    { "id": 16, "tasks": ["17.5"] },
    { "id": 17, "tasks": ["17.6"] }
  ]
}
```
