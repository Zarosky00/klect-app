# KLECT — Acceptance checklist

The brief's original four points, expanded into something a build can actually be judged against.
Tick a box only when you have *seen it work*, not when the code exists.

---

## A. The core loop — capture → curate → surf

- [ ] Camera capture **and** multi-select from library, in one sheet, with permission denial handled gracefully
- [ ] Client-side downscale + WebP re-encode before upload (never ship a 12 MP original over cellular)
- [ ] Blurhash + intrinsic width/height computed at upload → grid never reflows
- [ ] Upload is resumable and shows real per-file progress; app kill mid-upload doesn't orphan rows
- [ ] Create collection → subcollection → item in ≤ 3 taps from anywhere, with sensible defaults
- [ ] Reorder items/subcollections by drag, persisted to `position`
- [ ] Move an item between subcollections; both `item_count`s correct afterwards
- [ ] Cover auto-derives from the first photo, and can be overridden

## B. The signature gestures (see DESIGN_SYSTEM.md §4)

- [ ] **Single tap** opens Closeup with **zero** perceptible delay (no double-tap penalty)
- [ ] **Double tap** opens immersive fullscreen; pinch-zoom, pan, swipe between images
- [ ] **Long press** opens the quick-action peek
- [ ] Shared-element hero runs both directions and survives a fast back-swipe mid-animation
- [ ] Chrome auto-hides in immersive and returns on tap
- [ ] Every one of the three gestures works on collection, subcollection **and** item cards

## C. Zero-delay social mechanics

- [ ] Like / save / repost apply **optimistically** on finger-lift, then reconcile with the RPC result
- [ ] Rapid double-toggle (10 taps in 2s) ends in the correct state with the correct count
- [ ] Counts update **live** for other viewers via realtime on the entity row
- [ ] Offline: action queues, UI reflects intent, replays on reconnect, no duplicate rows
- [ ] Comment posts optimistically with a pending state; failure restores the draft, never loses text
- [ ] Threaded replies to depth 3; reply counts correct
- [ ] Follow/unfollow updates the target's follower count everywhere it's on screen
- [ ] A count never flickers to a stale server value after an optimistic update

## D. Surf & discovery

- [ ] Masonry grid holds 60fps (120 where available) while flinging through 500+ tiles
- [ ] Images are lazily decoded and evicted; memory stays flat on a long scroll
- [ ] Infinite pagination has no duplicates and no gaps across pages (stable `p_seed`)
- [ ] Two different accounts see visibly different orders
- [ ] Filters: all / following / items / collections
- [ ] Pull-to-refresh reseeds and returns to top
- [ ] Search returns people, collections, items and tags; empty query state is useful, not blank
- [ ] "Collectors like you" shows real shared tags and a match score

## E. Social graph, chat, calls

- [ ] Profile: banner, avatar, bio, counts, collection grid, follow button with optimistic state
- [ ] Follow / block / mute / report from the profile overflow
- [ ] Blocking is bidirectional and immediate: content, DMs and notifications all stop
- [ ] DM list with unread badges, last-message preview, correct ordering
- [ ] Send text, photo, and **shared entity** messages; shared collections render as rich cards
- [ ] Typing indicator + presence via realtime broadcast (not a table)
- [ ] Read receipts; `mark_conversation_read` zeroes the badge everywhere
- [ ] Audio and video call: ring, accept, decline, mute, camera flip, end, duration recorded
- [ ] Call state survives app backgrounding; a missed call writes a `call_event` message
- [ ] `allow_messages_from` (everyone/following/matches/nobody) is respected before a DM opens

## F. Safety, moderation, admin

- [ ] Report is reachable from **every** surface: item, subcollection, collection, post, comment, message, profile
- [ ] Reporting twice tells the user it's already reported instead of erroring
- [ ] Admin console gated on `user_roles`; a non-staff user hitting `/admin` sees nothing (and the server refuses anyway)
- [ ] Report queue sorted by priority, with content preview and the subject's report history
- [ ] Actions work end-to-end: hide, delete, restore, warn, suspend (with duration), ban
- [ ] Resolving one report auto-resolves the others about the same target
- [ ] Suspended user is blocked from every write RPC and sees a suspension screen
- [ ] Audit log records every staff action with actor, target and detail
- [ ] Metrics dashboard: users, content, engagement, moderation, 14-day signups

## G. Correctness & security

- [ ] RLS verified from a second account: private collections invisible, followers-only respected
- [ ] Anonymous browsing sees public content only — and can't read notifications, saves or DMs
- [ ] Counter columns are not client-writable (verified by privilege, not by trust)
- [ ] No service-role key in either client bundle
- [ ] Supabase security advisors: zero ERROR, and every WARN either fixed or explained in PROJECT_STATE
- [ ] Deleting a collection purges its polymorphic likes/saves/comments/views/tags

## H. Craft

- [ ] Dark **and** light theme complete; system-following plus a manual override
- [ ] Every text/background pair meets the contrast floor in both themes
- [ ] Reduced-motion honoured
- [ ] Keyboard navigation and visible focus ring on web
- [ ] Loading = skeletons matching final layout; never a centred spinner on a full page
- [ ] Every error state offers a retry; no dead ends
- [ ] Safe areas, notches, and the Android back gesture all correct
- [ ] Deep links: a collection/item URL opens the right screen on web and mobile

## I. Build gates

- [ ] `flutter analyze` — zero issues
- [ ] `flutter test` — all pass
- [ ] `flutter build web --release` — succeeds
- [ ] `tsc --noEmit` — zero errors
- [ ] `next lint` — zero errors
- [ ] `next build` — succeeds
- [ ] `PROJECT_STATE.md` updated to match reality
