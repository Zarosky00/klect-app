# Requirements Document

## Introduction

This feature closes seven gaps across the KLECT Flutter mobile client: the in-app notification
banner reads generic rather than "Editorial Noir", the Alert Center merges every notification
category into one undifferentiated list, one-to-one calling is fully implemented but hidden behind
a disabled server flag with no entry point in a chat thread, a deleted message vanishes silently
for the other participant, group identity and permission controls exist but are hard to reach and
unenforced in the composer, and no sibling tab surface can be reached by a horizontal swipe.

**Scope decisions locked with the requester:**

- **Mobile only.** The Next.js web client is out of scope for this spec.
- **Calling is one-to-one only.** Multi-party calling and "add another person to an ongoing call"
  are explicitly deferred to a later spec. The existing mesh WebRTC media path and Supabase
  signalling are finished and enabled rather than replaced by an SFU.
- **Notification preferences become account-synced** through a new RPC plus a `user_preferences`
  column, so a muted category suppresses both in-app presentation and device push delivery.
- **Message deletion gains a visible tombstone for every participant, plus a separate
  delete-for-me** action that hides a message for the deleting account alone.
- **Horizontal swipe applies to sibling sub-tabs only.** The five root bottom-bar destinations
  (Surf, Pulse, Create, Alerts, You) remain tap-only.
- **Group admins may manage the admin role**, not just the owner. The shipped
  `set_group_member_role` RPC is owner-only, so this widening needs a migration; ownership transfer
  stays owner-only.

**What already exists and is therefore treated as a starting point, not as work:** the WebRTC
call engine (`mobile/lib/features/chat/calls/`), the `start_call` / `answer_call` / `decline_call` /
`end_call` / `send_call_signal` RPC set, the `turn-credentials` edge function, the
`group_policy` JSONB contract with `set_group_policy` / `update_group_info` / `clear_group_avatar` /
`set_group_join_approval` / `set_group_member_role`, the `KBanner` overlay, and the device-local
muted-type set in `notification_preferences.dart`.

## Glossary

- **Alert_Center**: the mobile Alerts screen (`notifications_screen.dart`) that lists the signed-in
  account's `notifications` rows.
- **Banner_Presenter**: the mobile component that decides how one realtime notification is surfaced
  (`NotificationPresenter` in `notification_surfaces.dart`).
- **Notification_Banner**: the in-app heads-up overlay shown by `KBanner` under the status bar.
- **Notification_Category**: one member of the set `{likes, saves, reposts, comments_and_replies,
  mentions, follows, messages, calls, recommendations, matches, system}`, each mapping to one or
  more `notification_type` enum values.
- **Notification_Preferences_Service**: the mobile service that reads and writes the account's
  per-category notification settings.
- **Preference_Store**: the `public.user_preferences` row for the signed-in account, extended by
  this feature with a `notifications` JSONB column.
- **Push_Fanout**: the `push-fanout` Supabase edge function that delivers a `notifications` row to
  registered devices through FCM.
- **Call_Engine**: the mobile call state machine and WebRTC transport (`ActiveCallController` in
  `call_controller.dart`).
- **Call_Screen**: the full-screen mobile call surface (`call_screen.dart`).
- **Call_Pill**: the persistent floating return-to-call control shown while a call is active and the
  Call_Screen is not on top of the navigator.
- **Call_Phase**: one member of `{idle, dialing, incoming, connecting, active, reconnecting, ended}`.
- **Call_Notification**: the Android high-priority call-style system notification used when an
  incoming call arrives while the app is backgrounded or the device is locked.
- **Chat_Thread**: the mobile conversation screen (`conversation_screen.dart`).
- **Message_Store**: the mobile thread data layer (`ChatApi` plus `ThreadController`).
- **Tombstone**: the non-interactive placeholder rendered in place of a message deleted for every
  participant.
- **Group_Info_Screen**: the mobile group management screen (`group_info_screen.dart`).
- **Group_Permission_Scope**: one member of `{owner, admins, everyone}` as stored in
  `conversations.group_policy`.
- **Member_Role**: one member of `{owner, admin, member}` as stored in `conversation_members.role`.
- **Tab_Pager**: the mobile component that pages horizontally between sibling tabs and drives the
  tab indicator.
- **Sibling_Tab_Set**: an ordered list of tabs presented under one header, specifically the Pulse
  modes (`For you`, `Following`), the profile modes (`Surf`, `Pulse`, `Activity`), the inbox filters,
  and the Surf filter rail.
- **Token_Set**: the generated design tokens (`mobile/lib/design/tokens.g.dart`) compiled from
  `packages/tokens/tokens.json`.
- **Gesture_Contract**: single tap opens the Closeup, double tap opens the immersive viewer, long
  press opens the radial quick-action peek.
- **Reduced_Motion**: the platform accessibility setting exposed as
  `MediaQuery.disableAnimations`.

## Requirements

### Requirement 1: Editorial Noir notification banner

**User Story:** As a signed-in collector, I want an in-app notification banner that looks like it
belongs to KLECT, so that an interruption feels considered rather than cheap.

#### Acceptance Criteria

1. THE Notification_Banner SHALL read every colour, radius, spacing, stroke, blur, elevation and
   duration value from the Token_Set, and SHALL carry no literal colour, radius, spacing, stroke,
   blur, elevation or duration value of its own (invariant).
2. THE Notification_Banner SHALL render an actor avatar sized from the Token_Set, a category glyph
   badged on that avatar, a title line of exactly one line truncated with an ellipsis beyond one
   line, a message line of at most two lines, and an optional square entity thumbnail sized from the
   Token_Set, laid out in that order along the reading direction.
3. WHERE the notification carries an entity reference whose `entity_type` is not `comment`, THE
   Banner_Presenter SHALL request that entity's cover thumbnail and blurhash and SHALL present the
   Notification_Banner as soon as that request resolves or the thumbnail request timeout of 2 seconds
   elapses, whichever occurs first.
4. IF the entity thumbnail request fails or does not resolve within the thumbnail request timeout of
   2 seconds, THEN THE Notification_Banner SHALL present without a thumbnail, SHALL lay out the
   remaining elements across the full card width, and SHALL surface no error indication.
5. WHILE a requested cover thumbnail is not yet decoded and that entity's blurhash is available, THE
   Notification_Banner SHALL render that blurhash in the thumbnail area and SHALL replace it with the
   decoded thumbnail once decoding completes.
6. THE Notification_Banner SHALL tint the category glyph with the action colour assigned to that
   Notification_Category in the Token_Set, and WHERE the presented Notification_Category has no
   assigned action colour, THE Notification_Banner SHALL tint the category glyph with the Token_Set
   default accent colour.
7. WHERE a rendered title line or message line contains a numeric count, THE Notification_Banner
   SHALL render that count's digits with tabular figures, so that digit glyph width does not change
   as the count changes.
8. WHERE the message line content exceeds two lines at the rendered card width, THE
   Notification_Banner SHALL truncate the message line at the end of the second line with a single
   trailing ellipsis.
9. THE Notification_Banner SHALL constrain rendered card width to the Token_Set readable maximum
   width of 680 logical pixels, SHALL fall back to the available width minus the Token_Set gutter
   insets where that available width is below 680 logical pixels, SHALL centre the rendered card
   horizontally, and SHALL anchor the card's top edge below the status-bar safe-area inset.
10. THE Notification_Banner SHALL give the banner card and every interactive element inside it a
    minimum 44 by 44 logical-pixel hit target.
11. IF the actor avatar image cannot be loaded within the thumbnail request timeout of 2 seconds,
    THEN THE Notification_Banner SHALL render a placeholder avatar carrying the first character of
    the actor label and SHALL present the banner.

### Requirement 2: Notification banner motion

**User Story:** As a signed-in collector, I want the banner to arrive and leave with motion that
matches the rest of the app, so that the interruption reads as premium.

#### Acceptance Criteria

1. WHEN the Banner_Presenter presents a notification, THE Notification_Banner SHALL enter by
   translating downward from fully off the top edge of the safe area to its rest position while
   opacity moves from 0 to 1, over a Token_Set duration of at least 160 and at most 480
   milliseconds.
2. WHILE a finger drags the Notification_Banner vertically upward, THE Notification_Banner SHALL
   follow the finger at a 1:1 ratio up to the Token_Set drag limit, SHALL clamp translation beyond
   that limit so that upward travel never exceeds the Token_Set drag limit and downward travel never
   exceeds 0 logical pixels below the rest position, and SHALL suspend the banner dwell period for
   the duration of the drag.
3. WHEN an upward drag is released with an upward velocity of at least 400 logical pixels per second
   or with an upward translation of at least 40 percent of the rendered banner height, THE
   Notification_Banner SHALL leave and remove the overlay entry.
4. IF an upward drag is released with an upward velocity below 400 logical pixels per second and an
   upward translation below 40 percent of the rendered banner height, THEN THE Notification_Banner
   SHALL return to its rest position within 320 milliseconds and SHALL restart the banner dwell
   period from full.
5. WHEN the banner dwell period of 5 seconds, measured from completion of the enter animation and
   with no tap and no drag on the Notification_Banner during that period, elapses, THE
   Notification_Banner SHALL leave and remove the overlay entry.
6. WHEN the Notification_Banner begins to leave for any reason, THE Notification_Banner SHALL
   translate upward off the top edge of the safe area while opacity moves from 1 to 0 over a
   Token_Set duration of at most 240 milliseconds, SHALL ignore tap and drag input for the remainder
   of that animation, and SHALL remove the overlay entry once that animation completes.
7. WHILE Reduced_Motion is enabled, THE Notification_Banner SHALL apply no slide and no scale
   transform, SHALL enter with an opacity fade from 0 to 1 of 90 milliseconds, SHALL leave with an
   opacity fade from 1 to 0 of 90 milliseconds, and SHALL retain the tap behaviour, the drag
   dismissal behaviour of criteria 2 through 4 and the 5 second dwell period.
8. WHILE a Notification_Banner overlay entry is mounted, including during its enter and leave
   animations, THE Banner_Presenter SHALL present no further Notification_Banner, SHALL discard the
   newer notification without queueing it for later presentation, and SHALL leave the newer
   notification to the Alert_Center.
9. FOR ALL sequences of present and dismiss calls, THE Banner_Presenter SHALL leave at most one
   Notification_Banner overlay entry mounted at any instant (invariant).

### Requirement 3: Per-category banner composition

**User Story:** As a signed-in collector, I want each kind of notification to read differently at a
glance, so that a message, a follower, a call and a recommendation are never confusable.

#### Acceptance Criteria

1. WHEN a `message` notification is presented, THE Notification_Banner SHALL show the sender display
   name as a single-line title truncated with an ellipsis beyond one line, and SHALL show the first
   140 characters of the message body as the message line, using the attachment kind label as the
   message line where the message body is empty.
2. WHEN a `follow` notification is presented, THE Notification_Banner SHALL show the follower display
   name as a single-line title, a follow phrase as the message line, and a follow-back action that,
   on activation, follows the actor, replaces the action label with a followed state, and removes the
   banner.
3. WHEN a `call` notification is presented and the corresponding call row status is `ringing`, THE
   Notification_Banner SHALL show an accept action that answers that call id and opens the
   Call_Screen, and a decline action that declines that call id without opening the Call_Screen, and
   SHALL remove the banner on activation of either action.
4. WHEN a `recommendation` notification is presented, THE Notification_Banner SHALL show the
   recommended entity's cover thumbnail and the owner's display name as a single-line title.
5. WHEN a `like`, `save`, `repost`, `comment`, `reply`, `mention`, `match` or `system` notification
   is presented, THE Notification_Banner SHALL show the category glyph, the single-line actor label
   and the phrase assigned to that Notification_Category.
6. WHERE a presented notification carries a type outside the set named in criteria 1 through 5, THE
   Notification_Banner SHALL present a generic banner carrying the default glyph, the actor label and
   the first 140 characters of the notification body.
7. WHEN a presented Notification_Banner is tapped, THE Banner_Presenter SHALL navigate to that
   notification's destination route and remove the banner.
8. WHILE the current route matches a notification's destination route including that route's entity
   id parameters, THE Banner_Presenter SHALL suppress presentation of that notification.
9. WHILE the Alert_Center is the current route, THE Banner_Presenter SHALL suppress presentation of
   every notification.
10. IF the same notification id is presented twice, THEN THE Banner_Presenter SHALL present that
    notification once and discard the repeat, matching against the notification ids of at most the 50
    most recently presented notifications in the current app session (idempotence).
11. IF a `call` notification is presented and the corresponding call row status is any value other
    than `ringing`, THEN THE Banner_Presenter SHALL suppress presentation of that notification.
12. IF a presented notification carries no resolvable actor display name, THEN THE
    Notification_Banner SHALL render a placeholder actor label and SHALL present the banner.
13. IF a tapped notification's destination route cannot be resolved, THEN THE Banner_Presenter SHALL
    remove the banner and SHALL navigate to the Alert_Center.

### Requirement 4: Notification category filtering in the Alert Center

**User Story:** As a signed-in collector, I want to filter the Alerts list by category, so that
calls, messages, follows and recommendations stop drowning each other out.

#### Acceptance Criteria

1. THE Alert_Center SHALL present a filter rail listing `All` first followed by the eleven
   Notification_Category chips in the Glossary order, SHALL scroll the rail horizontally when the
   chips exceed the available width, SHALL give each chip a minimum 44 by 44 logical-pixel hit
   target, and SHALL scroll the selected chip fully into view.
2. WHEN a Notification_Category filter is selected, THE Alert_Center SHALL render, within 300
   milliseconds, only the loaded notifications whose Notification_Category matches the selection and
   which the Preference_Store does not suppress, in the same newest-first order used under `All`.
3. WHEN the `All` filter is selected, THE Alert_Center SHALL render every loaded notification the
   Preference_Store does not suppress, newest first.
4. FOR ALL notification lists, the list rendered under any single-category filter SHALL be a
   subsequence of the list rendered under `All`, preserving relative order (metamorphic property).
5. FOR ALL notification lists, applying one filter selection twice SHALL produce the same rendered
   list as applying that selection once (idempotence).
6. WHERE a filter selection yields no notifications, THE Alert_Center SHALL keep the filter rail
   visible and SHALL render in place of the list an empty state carrying a display-serif headline of
   at most 40 characters, one sentence of at most 160 characters, and exactly one action that
   returns the selection to `All`.
7. THE Alert_Center SHALL show an unread count per Notification_Category on that category's filter
   chip, derived from the unread state carried on the notification rows rather than from a
   client-side aggregate query, rendering counts of 1 through 99 as digits in tabular figures,
   counts above 99 as `99+`, and no count when the category has no unread notification.
8. WHEN a filter chip is activated, THE Alert_Center SHALL animate the filter indicator to that chip
   with a Token_Set duration of at most 480 milliseconds, including when the activated chip is
   already selected.
9. WHEN the Alert_Center is reopened within the same app session, THE Alert_Center SHALL restore the
   previously selected filter, and on the first open of a new app session THE Alert_Center SHALL
   select `All`.
10. IF loading notifications for the selected filter fails, THEN THE Alert_Center SHALL retain the
    previously rendered list, SHALL keep the selected chip selected, and SHALL surface an error
    indication carrying a retry action.
11. WHEN a notification arrives in realtime whose Notification_Category does not match the selected
    filter, THE Alert_Center SHALL leave the rendered list unchanged and SHALL increment the unread
    count on that notification's category chip.

### Requirement 5: Account-synced notification delivery preferences

**User Story:** As a signed-in collector, I want the categories I switch off to stop arriving on my
device at all, so that muting means muting on every device I sign in from.

#### Acceptance Criteria

1. THE Preference_Store SHALL persist exactly one boolean enabled flag per Notification_Category for
   the signed-in account, covering all 11 Notification_Category values (`likes`, `saves`, `reposts`,
   `comments_and_replies`, `mentions`, `follows`, `messages`, `calls`, `recommendations`, `matches`,
   `system`).
2. THE Notification_Preferences_Service SHALL write preference changes through a Supabase RPC that
   re-checks `auth.uid()` server-side and SHALL apply the change only to the
   `user_preferences.notifications` row whose owner equals that `auth.uid()`.
3. IF the preference RPC is invoked for an account other than the one resolved from `auth.uid()`, or
   is invoked with no authenticated session, THEN THE Notification_Preferences_Service SHALL reject
   the write, SHALL leave the Preference_Store unchanged, and SHALL return an error indicating the
   caller is not authorised.
4. IF a preference write payload contains a value that is not one of the 11 Notification_Category
   values, or an enabled value that is not a boolean, THEN THE Notification_Preferences_Service SHALL
   reject the entire write, SHALL leave every Notification_Category flag in the Preference_Store
   unchanged, and SHALL return an error indicating the payload is invalid.
5. WHEN a Notification_Category is switched off, THE Banner_Presenter SHALL suppress presentation of
   every notification in that Notification_Category received after the Preference_Store write
   commits, and SHALL continue presenting notifications in every Notification_Category still enabled.
6. WHEN a Notification_Category is switched off, THE Push_Fanout SHALL skip device delivery for every
   `notifications` row in that Notification_Category created after the Preference_Store write
   commits, and SHALL still deliver rows in every Notification_Category still enabled.
7. WHEN the signed-in account signs in on an additional device, THE Notification_Preferences_Service
   SHALL read the Preference_Store and render each of the 11 switches in the state held in the
   Preference_Store before any preference switch accepts input on that device.
8. WHERE a Notification_Category key is absent from the `user_preferences.notifications` JSONB, or
   the JSONB itself is absent for the account, THE Notification_Preferences_Service SHALL treat every
   absent Notification_Category as enabled.
9. FOR ALL preference sets, decoding the encoded form of a preference set SHALL produce a preference
   set equal to the original for all 11 Notification_Category values (round-trip property).
10. FOR ALL Notification_Category values and all boolean values, applying the same enabled value
    twice SHALL leave the Preference_Store equal to the state after one application (idempotence).
11. IF the preference RPC returns an error or does not return within 10 seconds, THEN THE
    Notification_Preferences_Service SHALL restore the previous preference set for all 11
    Notification_Category values without presenting a message, so that the rendered switch state
    always matches the Preference_Store.
12. WHEN a device holding a legacy device-local muted set signs in, THE
    Notification_Preferences_Service SHALL migrate that muted set into the Preference_Store exactly
    once per account, mapping each locally muted Notification_Category to an enabled flag of false
    and leaving every other Notification_Category enabled.
13. WHEN the legacy muted set migration has committed to the Preference_Store, THE
    Notification_Preferences_Service SHALL read preference state only from the Preference_Store and
    SHALL ignore the device-local muted set on all subsequent sign-ins.
14. WHILE a conversation's `conversation_members.muted_until` holds a timestamp later than the
    current server time, THE Push_Fanout SHALL suppress device delivery for every `notifications` row
    belonging to that conversation, independently of the `messages` Notification_Category enabled
    flag.

### Requirement 6: Call entry points in a chat thread

**User Story:** As a signed-in collector, I want voice and video call buttons in a direct-message
thread, so that starting a call does not require leaving the conversation.

#### Acceptance Criteria

1. WHILE a Chat_Thread whose conversation kind is `dm` is open and the `call_feature_enabled` RPC
   has resolved as enabled, THE Chat_Thread SHALL show a voice call action and a video call action in
   the thread header, each carrying a text alternative naming its call kind and a minimum 44 by 44
   logical-pixel hit target.
2. WHILE an open Chat_Thread's conversation kind is any value other than `dm`, THE Chat_Thread SHALL
   hide the voice call action and the video call action.
3. WHILE the `call_feature_enabled` RPC result for the current session is disabled, unresolved or
   failed, THE Chat_Thread SHALL hide the voice call action and the video call action.
4. WHEN the voice call action is activated and microphone permission is not already granted, THE
   Chat_Thread SHALL request microphone permission before issuing the `start_call` RPC.
5. IF a permission required for the activated call kind is denied, THEN THE Chat_Thread SHALL surface
   a message naming the denied permission and the call kind it blocks, SHALL offer one action that
   opens the device system settings for the app, SHALL issue no `start_call` RPC, and SHALL keep the
   Chat_Thread as the current route with composer contents retained.
6. WHEN every permission required for the activated call kind is granted, THE Call_Engine SHALL
   create the call through the `start_call` RPC with the activated call kind and THE Chat_Thread
   SHALL push the Call_Screen for the returned call id once that RPC returns success.
7. IF the `start_call` RPC returns the stable error identifier `calls_unavailable`, `not_allowed`,
   `blocked` or `busy`, THEN THE Chat_Thread SHALL surface the human-readable message mapped to that
   identifier, SHALL push no Call_Screen, and SHALL keep the Chat_Thread as the current route.
8. WHILE a call involving the signed-in account is in Call_Phase `dialing`, `incoming`, `connecting`,
   `active` or `reconnecting`, THE Chat_Thread SHALL render the voice call action and the video call
   action in a disabled state exposed to assistive technology and SHALL issue no `start_call` RPC for
   an activation of either action.
9. WHEN the video call action is activated, THE Chat_Thread SHALL request each of microphone
   permission and camera permission that is not already granted before issuing the `start_call` RPC.
10. WHILE a permission request or a `start_call` request issued from the Chat_Thread is outstanding,
    THE Chat_Thread SHALL disable the voice call action and the video call action, so that at most one
    `start_call` RPC is outstanding per Chat_Thread.
11. IF the `start_call` RPC returns no response within the call-creation timeout of 15 seconds, or
    fails with an error outside the set named in criterion 7, THEN THE Chat_Thread SHALL surface a
    message indicating the call could not be started, SHALL push no Call_Screen, and SHALL return the
    voice call action and the video call action to their enabled state.

### Requirement 7: One-to-one call lifecycle

**User Story:** As a signed-in collector, I want ringing, accepting, declining and ending a call to
work reliably, so that a call is a real feature rather than a screen.

#### Acceptance Criteria

1. WHEN the `start_call` RPC returns success, THE Call_Engine SHALL enter Call_Phase `dialing` within
   1 second and SHALL publish the local session description for the returned call id through the
   `send_call_signal` RPC.
2. WHEN a `calls` row addressed to the signed-in account arrives with status `ringing` and the
   Call_Engine holds no call in Call_Phase `dialing`, `incoming`, `connecting`, `active` or
   `reconnecting`, THE Call_Engine SHALL enter Call_Phase `incoming` for that call id.
3. WHEN an incoming call is accepted, THE Call_Engine SHALL call the `answer_call` RPC, SHALL enter
   Call_Phase `connecting`, and SHALL enter Call_Phase `active` once the peer connection reports a
   connected state, starting elapsed duration at zero seconds at that transition.
4. WHEN an incoming call is declined, THE Call_Engine SHALL call the `decline_call` RPC, SHALL enter
   Call_Phase `ended` with a declined reason within 1 second of the activation regardless of the RPC
   outcome, and SHALL release the local audio and video tracks.
5. IF a call remains in Call_Phase `dialing` or `incoming` for the ring timeout of 45 seconds
   measured from the `calls` row creation timestamp, THEN THE Call_Engine SHALL enter Call_Phase
   `ended` with a missed reason, SHALL release the local audio and video tracks, and THE Alert_Center
   SHALL list a missed-call notification for that call id.
6. IF the peer connection reports a disconnected state while Call_Phase is `active`, THEN THE
   Call_Engine SHALL enter Call_Phase `reconnecting`, SHALL retain the local and remote media tracks,
   and SHALL attempt an ICE restart after the reconnect grace period of 4 seconds, attempting at most
   3 ICE restarts spaced at least 4 seconds apart within one `reconnecting` period.
7. IF Call_Phase `reconnecting` persists for the reconnect timeout of 25 seconds measured from the
   transition into `reconnecting`, THEN THE Call_Engine SHALL call the `end_call` RPC with the
   elapsed duration accumulated up to that point and SHALL enter Call_Phase `ended` with a failed
   reason.
8. WHEN either participant ends a call, THE Call_Engine SHALL call the `end_call` RPC with the
   elapsed duration as a whole-second value between 0 and 86,400 counted from the transition into
   Call_Phase `active`, reporting zero seconds where Call_Phase never became `active`, and SHALL
   enter Call_Phase `ended` within 1 second of the activation regardless of the RPC outcome,
   releasing the local audio and video tracks.
9. THE Call_Engine SHALL transition between Call_Phase values only along the transition set
   `idle→dialing`, `idle→incoming`, `dialing→connecting`, `dialing→ended`, `incoming→connecting`,
   `incoming→ended`, `connecting→active`, `connecting→ended`, `active→reconnecting`,
   `active→ended`, `reconnecting→active`, `reconnecting→ended` (invariant).
10. WHILE Call_Phase is `ended`, THE Call_Engine SHALL reject every transition to another Call_Phase
    for the same call id (absorbing terminal state).
11. FOR ALL call id values, calling `end_call` more than once SHALL leave the same stored call status
    and duration as the first successful `end_call` for that call id (idempotence).
12. WHEN the Call_Screen is opened by deep link for a call id the Call_Engine already holds, THE
    Call_Engine SHALL retain the existing Call_Phase, elapsed duration and media tracks and SHALL
    issue no further `start_call` or `answer_call` RPC for that call id.
13. WHEN the signed-in account leaves the Call_Screen by the system back gesture while Call_Phase is
    `dialing`, `connecting`, `active` or `reconnecting`, THE Call_Engine SHALL retain that Call_Phase
    and its media tracks, SHALL issue no `end_call` RPC, and THE Call_Pill SHALL become visible
    within 1 second.
14. IF the `answer_call` RPC fails or returns no response within the call-answer timeout of 15
    seconds, THEN THE Call_Engine SHALL enter Call_Phase `ended` with a failed reason, SHALL release
    the local audio and video tracks, and SHALL surface an error indication that the call could not
    be joined.
15. IF the peer connection does not report a connected state within the connect timeout of 30 seconds
    measured from the transition into Call_Phase `connecting`, THEN THE Call_Engine SHALL call the
    `end_call` RPC with an elapsed duration of zero seconds and SHALL enter Call_Phase `ended` with a
    failed reason.
16. IF a `calls` row addressed to the signed-in account arrives with status `ringing` while the
    Call_Engine holds a call in Call_Phase `dialing`, `incoming`, `connecting`, `active` or
    `reconnecting`, THEN THE Call_Engine SHALL call the `decline_call` RPC for the newly arrived call
    id with a busy reason, SHALL retain the held call's Call_Phase and media tracks, and THE
    Alert_Center SHALL list a missed-call notification for the newly arrived call id.

### Requirement 8: In-call controls

**User Story:** As a signed-in collector, I want mute, speaker, camera and duration controls that
behave the way a phone call behaves, so that I never have to guess mid-call.

#### Acceptance Criteria

1. WHILE Call_Phase is `dialing`, `incoming`, `connecting`, `active` or `reconnecting`, THE
   Call_Screen SHALL present the mute, speaker, camera-enable, camera-flip, minimize and end controls
   that apply to the call kind, each with a hit target of at least the Token_Set `tapTargetMin` value
   of 44 by 44 logical pixels, and each exposing to assistive technology a label naming the control,
   its enabled or disabled state, and its current on or off state.
2. WHEN the mute control is activated, THE Call_Engine SHALL toggle the local audio track enabled
   flag within 300 milliseconds and THE Call_Screen SHALL reflect the resulting state in glyph fill,
   visible label and assistive-technology label within 300 milliseconds of that toggle completing.
3. WHEN the speaker control is activated, THE Call_Engine SHALL switch the audio output between
   speakerphone and earpiece within 300 milliseconds, THE Call_Screen SHALL reflect the resulting
   state in glyph fill, visible label and assistive-technology label, and THE Call_Engine SHALL
   retain the selected output across every Call_Phase change until Call_Phase becomes `ended`.
4. WHILE Call_Phase is `active` or `reconnecting` and the call kind is `video`, THE Call_Screen SHALL
   render the remote video track full-bleed, SHALL retain the most recently received remote frame for
   the entire time Call_Phase is `reconnecting`, and SHALL render the local video track in a preview
   inset that is draggable within the remote video area and clamped so that every inset edge remains
   inside the safe area by at least the Token_Set inset spacing.
5. IF the remote video track is absent, or no remote video frame has been received for 3 consecutive
   seconds during a video call, THEN THE Call_Screen SHALL render the Token_Set sunken background
   surface in the remote video area and SHALL render the peer display name and a status line
   indicating that remote video is unavailable.
6. WHILE the call kind is `audio`, THE Call_Screen SHALL render the peer avatar, peer display name
   and call status in place of remote video.
7. WHEN the camera-enable control is activated, THE Call_Engine SHALL toggle the local video track
   enabled flag within 300 milliseconds and THE Call_Screen SHALL hide the local preview inset for
   the entire time the local video track is disabled.
8. WHILE the local video track is disabled, THE Call_Screen SHALL disable the camera-flip control,
   SHALL perform no camera facing change on activation of that control, and SHALL expose the disabled
   state to assistive technology.
9. WHEN the camera-flip control is activated, THE Call_Engine SHALL switch the active camera facing
   mode between front and rear within 1 second and THE Call_Screen SHALL mirror the local preview
   horizontally only while the front-facing camera is active.
10. WHILE Call_Phase is `active`, THE Call_Screen SHALL display elapsed call duration measured from
    the first entry into Call_Phase `active`, updated at least once per second, formatted as `m:ss`
    below one hour and `h:mm:ss` at or above one hour, using tabular figures.
11. THE Call_Engine SHALL report elapsed call duration as a monotonically non-decreasing whole-second
    value while Call_Phase is `active`, `reconnecting` or `ended`, and SHALL hold that value unchanged
    for the entire time Call_Phase is `ended` (invariant).
12. FOR ALL elapsed durations from 0 seconds to 86,399 seconds, parsing the formatted duration string
    SHALL produce the original duration truncated to whole seconds (round-trip property).
13. FOR ALL of mute, speaker and camera-enable, activating one control twice in succession, with each
    activation reported complete before the next activation, SHALL return the Call_Engine to the
    state held before the first activation (involution property).
14. WHEN the Call_Screen background is tapped while the call kind is `video` and Call_Phase is
    `active`, THE Call_Screen SHALL toggle visibility of the control cluster, peer display name and
    duration with a Token_Set duration of at most 480 milliseconds, and SHALL keep hidden chrome both
    non-activatable and excluded from the assistive-technology focus order.
15. WHILE Call_Phase is `reconnecting`, THE Call_Screen SHALL announce the reconnecting status
    through a live region within 1 second of entering that Call_Phase, at most once per entry into
    that Call_Phase, using the Token_Set warning colour.
16. WHILE the call kind is `audio`, THE Call_Screen SHALL render neither the camera-enable control
    nor the camera-flip control and SHALL exclude both from the assistive-technology focus order.
17. IF a local audio track toggle, local video track toggle, audio output switch or camera facing
    switch does not complete within 1 second or reports a failure, THEN THE Call_Screen SHALL retain
    the last successfully applied control state, SHALL surface a message indicating that the control
    could not be applied, and THE Call_Engine SHALL remain in its current Call_Phase.
18. WHEN Call_Phase changes while Call_Screen chrome is hidden, THE Call_Screen SHALL restore chrome
    visibility with a Token_Set duration of at most 480 milliseconds.

### Requirement 9: Minimized call and background ringing

**User Story:** As a signed-in collector, I want to keep browsing during a call and to be reachable
when the app is not in front of me, so that a call never traps or misses me.

#### Acceptance Criteria

1. WHEN the minimize control is activated, THE Call_Screen SHALL pop itself within 300 milliseconds
   and THE Call_Pill SHALL appear anchored directly above the bottom navigation bar without covering
   it.
2. WHILE a call is in Call_Phase `dialing`, `connecting`, `active` or `reconnecting` and the
   Call_Screen is not the current route, THE Call_Pill SHALL display the peer display name truncated
   to a maximum of 24 characters, the current Call_Phase label, and the elapsed duration in `mm:ss`
   format for durations under 60 minutes and `h:mm:ss` format from 60 minutes onward, refreshed at
   least once per second.
3. WHEN the Call_Pill is tapped, THE Call_Pill SHALL push the Call_Screen for the held call id within
   300 milliseconds and SHALL preserve the elapsed duration continuously across the transition.
4. WHILE a video call is minimized, THE Call_Engine SHALL keep the remote audio track enabled and
   SHALL keep the local microphone track in the mute state it held at the moment of minimizing.
5. WHEN Call_Phase becomes `ended`, THE Call_Pill SHALL disappear within 1 second and SHALL leave no
   reserved layout space above the bottom navigation bar.
6. WHILE the app is backgrounded or the device is locked and a call addressed to the signed-in
   account reaches status `ringing`, THE Call_Notification SHALL be delivered on the Android `calls`
   channel with high priority within 5 seconds of the status change and SHALL offer exactly two
   actions, accept and decline.
7. WHEN the accept action of a Call_Notification is activated, THE Call_Engine SHALL open the
   Call_Screen for that call id, SHALL call the `answer_call` RPC, and SHALL cancel that
   Call_Notification.
8. WHEN the decline action of a Call_Notification is activated, THE Call_Engine SHALL call the
   `decline_call` RPC without opening the Call_Screen and SHALL cancel that Call_Notification.
9. WHEN a call leaves status `ringing`, THE Call_Notification for that call id SHALL be cancelled
   within 2 seconds.
10. WHILE the `calls` Notification_Category is switched off in the Preference_Store, THE Push_Fanout
    SHALL skip Call_Notification delivery for the signed-in account.
11. IF the `answer_call` or `decline_call` RPC invoked from a Call_Notification action fails or does
    not return within 10 seconds, THEN THE Call_Engine SHALL cancel the Call_Notification, SHALL leave
    the call in its server-reported status without local override, and SHALL surface a message
    indicating the call action could not be completed.
12. IF a Call_Notification action is activated for a call id whose status is no longer `ringing`,
    THEN THE Call_Engine SHALL cancel that Call_Notification, SHALL invoke neither RPC, and SHALL
    surface a message indicating the call is no longer available.
13. IF a Call_Notification accept action is activated while another call is in Call_Phase `dialing`,
    `connecting`, `active` or `reconnecting`, THEN THE Call_Engine SHALL leave the existing call in
    place, SHALL issue no `answer_call` RPC, and SHALL surface a message indicating another call is in
    progress.

### Requirement 10: TURN relay and call feature enablement

**User Story:** As the operator, I want calls to connect across mobile carrier networks before the
feature is switched on, so that enabling calling does not ship a broken feature.

#### Acceptance Criteria

1. WHEN the Call_Engine prepares to create a peer connection for a call id, THE Call_Engine SHALL
   request ICE servers from the `turn-credentials` edge function using the signed-in account's
   session, and SHALL create that peer connection only once that request resolves or the
   ICE-configuration timeout of 5 seconds elapses, whichever occurs first.
2. THE `turn-credentials` edge function SHALL return each relay entry carrying a username, a
   credential and an expiry timestamp no earlier than 1 hour and no later than 24 hours after
   issuance, and SHALL return that response within 5 seconds of the request.
3. IF the `turn-credentials` edge function returns no relay entry carrying both a username and a
   credential, THEN THE Call_Engine SHALL continue call setup using the returned STUN entries only,
   SHALL present a non-blocking warning indication in the Call_Screen stating that the call may fail
   on carrier networks, and SHALL record the missing-relay condition against that call id for
   operator review.
4. IF the `turn-credentials` request fails or does not return within the ICE-configuration timeout of
   5 seconds, THEN THE Call_Engine SHALL create the peer connection with a STUN-only ICE
   configuration, SHALL present the warning indication named in criterion 3, SHALL record the
   credential-fetch failure against that call id for operator review, and SHALL issue no further
   `turn-credentials` request for that call id.
5. THE Call_Engine SHALL order the ICE server list with every STUN entry before every relay entry,
   and SHALL pass at most 8 ICE entries to the peer connection by discarding entries beyond the
   eighth in that order, so that a direct path is attempted before a relayed path where a direct path
   exists (invariant).
6. WHEN a signed-in session starts, THE mobile client SHALL read call availability from the
   `call_feature_enabled` RPC rather than from a compiled-in constant, SHALL re-read that RPC each
   time the app returns to the foreground at least 5 minutes after the previous successful read, and
   SHALL apply the most recent successful result to every call affordance and to every `start_call`
   attempt.
7. IF the `call_feature_enabled` RPC returns an error or does not return within 10 seconds, THEN THE
   mobile client SHALL treat call availability as disabled until the next successful read of that RPC
   and SHALL surface no error indication.
8. WHILE the most recent `call_feature_enabled` result is disabled, THE Call_Engine SHALL issue no
   `start_call` RPC, SHALL hold Call_Phase at `idle` for an arriving `calls` row or a call deep link,
   and THE Chat_Thread SHALL present no call affordance.

### Requirement 11: Deleted message tombstone

**User Story:** As a chat participant, I want to see that a message was deleted rather than have it
disappear, so that a conversation never silently rewrites itself.

#### Acceptance Criteria

1. WHEN a message author confirms deleting a message for everyone, THE Message_Store SHALL mark that
   message deleted, SHALL clear the message body to empty, SHALL clear that message's attachment
   references, and SHALL retain the message row with its original message id, author id, reply-target
   reference and created timestamp unchanged.
2. WHILE a message is marked deleted for everyone, THE Chat_Thread SHALL render, in place of the
   original bubble and for every participant including the author, a Tombstone carrying a
   deleted-message label of at most 40 characters and no part of the original message body.
3. THE Tombstone SHALL retain the deleted message's position in thread order and its original
   timestamp (invariant).
4. THE Tombstone SHALL offer no reply, react, edit, forward, copy or media-open action, SHALL expose
   no action-menu entry other than the delete-for-me action, and SHALL respond to tap, double tap and
   long press with no navigation and no media viewer.
5. WHEN a message referenced as a reply target is deleted for everyone, THE Chat_Thread SHALL render
   that quoted preview as an unavailable label of at most 40 characters carrying no part of the
   deleted body, and SHALL render the jump-to-original action in a disabled state exposed to
   assistive technology.
6. WHEN a message is deleted for everyone while another participant has the Chat_Thread open and the
   realtime stream is connected, THE Chat_Thread SHALL replace that bubble with a Tombstone within 3
   seconds of the delete committing, without a manual refresh and without changing that message's
   position in thread order.
7. WHERE a deleted message carried image attachments, THE Chat_Thread SHALL render no attachment
   thumbnails and no attachment placeholder for that message.
8. WHERE a deleted message was the conversation's most recent message, THE inbox preview for that
   conversation SHALL render a deleted-message label of at most 40 characters, SHALL retain that
   conversation's existing ordering timestamp, and SHALL reflect the change within 3 seconds of the
   delete committing while the realtime stream is connected.
9. FOR ALL messages, deleting a message for everyone more than once SHALL leave the same stored
   message state as deleting that message once (idempotence).
10. IF a delete-for-everyone request is received from an account that is not the message author, THEN
    THE Message_Store SHALL reject that request, SHALL leave the message body, attachment references
    and deleted marker unchanged, and SHALL return an error indicating the caller is not the message
    author.
11. WHEN the delete-for-everyone action is activated, THE Chat_Thread SHALL present a confirmation
    step stating that the message will be deleted for every participant, and SHALL issue no delete
    request until that confirmation is accepted.
12. IF a delete-for-everyone request fails or returns no response within the delete timeout of 10
    seconds, THEN THE Chat_Thread SHALL restore the original bubble with its body and attachment
    thumbnails, SHALL leave the stored message state unchanged, and SHALL surface an error indication
    carrying a retry action.
13. WHILE a message is marked deleted for everyone, THE Message_Store SHALL return that message to
    every participant on every subsequent thread fetch and older-history page request with its
    deleted marker set, an empty body and no attachment references, so that the Tombstone renders
    after an app restart and after a realtime reconnect.

### Requirement 12: Delete for me

**User Story:** As a chat participant, I want to remove a message from my own copy of a thread, so
that I can clear something without changing what the other participant sees.

#### Acceptance Criteria

1. WHEN a participant long-presses any message in a thread, THE Chat_Thread SHALL include a
   delete-for-me action in the resulting action set for every message state, including messages
   authored by another participant, messages already deleted for everyone, and messages whose send is
   still pending or failed.
2. WHEN delete-for-me is selected for a message, THE Chat_Thread SHALL present a confirmation prompt
   naming the delete-for-me scope, and SHALL apply no state change until the participant confirms.
3. WHEN delete-for-me is confirmed for a message, THE Chat_Thread SHALL remove that message from the
   signed-in account's rendered thread within 500 milliseconds of the confirmation without requiring
   a manual refresh, SHALL leave the message visible to every other participant, and SHALL leave every
   other participant's unread counts and thread previews unchanged.
4. IF the delete-for-me write to the Message_Store fails or no network is available, THEN THE
   Chat_Thread SHALL restore the message to the rendered thread, SHALL surface an error indication
   that the message could not be deleted, and SHALL retain the message as not-hidden in stored state.
5. THE Message_Store SHALL persist delete-for-me state per account so that a hidden message remains
   hidden after app restart, after sign-out and sign-in on the same account, after the thread is paged
   again, and after the message is edited or reacted to by any participant.
6. WHEN the message author deletes for everyone a message that the signed-in account has already
   deleted for itself, THE Chat_Thread SHALL keep that message hidden for the signed-in account
   rather than rendering a Tombstone.
7. FOR ALL messages and all accounts, applying delete-for-me two or more times to the same message
   SHALL leave the Message_Store in the same state as applying it once, SHALL produce no duplicate
   hidden-state records, and SHALL return success on each repeated attempt (idempotence).
8. THE Message_Store SHALL apply an account's delete-for-me state only to that account's reads, and
   SHALL reject any read or write of another account's delete-for-me state with an authorization
   error.
9. WHERE all messages in a fetched page of up to 50 messages are hidden by delete-for-me state, THE
   Chat_Thread SHALL continue fetching successive older pages, up to 10 consecutive pages per
   user-initiated load, until at least 1 visible message is rendered or no older history remains.
10. IF no visible message remains in a thread after all delete-for-me state is applied and no older
    history remains, THEN THE Chat_Thread SHALL render an empty-thread state with the message
    composer still enabled.

### Requirement 13: Group identity and permission controls

**User Story:** As a group owner, I want group identity and permission controls that are easy to
find and actually enforced, so that a group behaves like a managed space.

#### Acceptance Criteria

1. WHEN a group Chat_Thread header is tapped, THE Chat_Thread SHALL open the Group_Info_Screen within
   400 milliseconds and SHALL render the Group_Info_Screen content or a loading indicator until
   content is available.
2. THE Group_Info_Screen SHALL present the group avatar, the group title, the group description, the
   total member count as an integer, and a member list showing every member with exactly one
   Member_Role badge per member drawn from `{owner, admin, member}`, where a group holds 2 to 256
   members inclusive.
3. WHERE the viewer's Member_Role satisfies the `edit_info` Group_Permission_Scope, THE
   Group_Info_Screen SHALL offer avatar replacement, avatar removal, title editing accepting 1 to 60
   characters after trimming leading and trailing whitespace, and description editing accepting 0 to
   500 characters.
4. WHERE the viewer's Member_Role satisfies the `add_members` Group_Permission_Scope, THE
   Group_Info_Screen SHALL offer member addition up to the 256-member maximum and invite-link
   management.
5. WHERE the viewer's Member_Role is `admin` or `owner`, THE Group_Info_Screen SHALL offer promotion
   of a `member` to `admin` and demotion of an `admin` to `member`, and SHALL offer no role change
   targeting the account whose Member_Role is `owner`.
6. WHERE the viewer's Member_Role is `owner`, THE Group_Info_Screen SHALL offer ownership transfer to
   a member of the group other than the owner, join-approval toggling, group deletion behind a
   confirmation step, and the three Group_Permission_Scope settings for `edit_info`, `add_members` and
   `send_messages`, each selectable as exactly one of `owner`, `admins` or `everyone`.
7. THE Message_Store SHALL reject a role change requested by an account whose Member_Role is
   `member`, SHALL reject an ownership transfer requested by an account whose Member_Role is not
   `owner`, and SHALL leave stored group state unchanged when it rejects such a request.
8. WHERE the viewer's Member_Role does not satisfy a Group_Permission_Scope, THE Group_Info_Screen
   SHALL hide the affordances that scope governs so that no hidden affordance is tappable.
9. WHILE the viewer's Member_Role does not satisfy the `send_messages` Group_Permission_Scope, THE
   Chat_Thread SHALL replace the composer with a read-only notice naming the Group_Permission_Scope
   value that governs sending, and SHALL block the message send, attachment and voice-note entry
   points.
10. THE Group_Permission_Scope evaluation SHALL be monotone in Member_Role rank: a scope that permits
    `member` SHALL permit `admin` and `owner`, and a scope that permits `admin` SHALL permit `owner`
    (invariant).
11. THE Group_Info_Screen SHALL apply every group change through the existing `set_group_policy`,
    `update_group_info`, `clear_group_avatar`, `set_group_join_approval` and `set_group_member_role`
    RPCs and SHALL surface the mapped human-readable message for the stable error identifiers
    `not_admin`, `not_owner`, `not_allowed`, `group_policy_denied`, `not_group`, `not_member`,
    `title_required` and `group_needs_members`.
12. WHEN a group change RPC succeeds, THE Group_Info_Screen SHALL refetch the conversation record and
    member list within 2 seconds so that rendered state matches server state.
13. IF a group change RPC fails, returns an unrecognised error identifier, or does not respond within
    10 seconds, THEN THE Group_Info_Screen SHALL restore the pre-change rendered values, SHALL surface
    an error message indicating the change was not saved, and SHALL keep the affordance available for
    retry.
14. THE Group_Info_Screen SHALL offer a report action for a group conversation that submits through
    the `submit_report` RPC.
15. WHEN a group avatar, title or description changes, THE Chat_Thread SHALL render the system
    message describing that change in thread order at the position of its creation time.
16. IF a title edit submits an empty value after trimming leading and trailing whitespace, THEN THE
    Group_Info_Screen SHALL block submission, SHALL retain the previously stored title, and SHALL
    surface a validation message indicating a title is required.

### Requirement 14: Swipeable sibling tab navigation

**User Story:** As a signed-in collector, I want to swipe horizontally between sibling tabs, so that
moving between For you, Following and the profile sub-tabs costs one gesture.

#### Acceptance Criteria

1. THE Tab_Pager SHALL page horizontally between the 2 to 6 ordered members of a Sibling_Tab_Set,
   rendering exactly one member across the full pager viewport width at rest, and WHERE the pageable
   set contains fewer than two members, THE Tab_Pager SHALL accept no horizontal paging drag.
2. WHEN a horizontal drag on a Sibling_Tab_Set ends with cumulative horizontal displacement of at
   least 25 percent of the pager viewport width or with horizontal release velocity of at least 400
   logical pixels per second, THE Tab_Pager SHALL settle on the member adjacent in the drag direction
   within a Token_Set duration of at most 480 milliseconds and SHALL set the selected tab state to
   that member.
3. WHILE a horizontal drag is in progress, THE Tab_Pager SHALL place the tab indicator at the
   fraction of the distance between the originating and adjacent tab labels equal to the fraction of
   viewport width dragged, SHALL update that position on every frame the drag delta changes, and
   SHALL leave the selected tab state unchanged until the drag ends.
4. WHEN a tab label of a member other than the selected member is tapped, THE Tab_Pager SHALL animate
   both the page and the tab indicator to that member with a Token_Set duration of at least 160 and
   at most 480 milliseconds, for any number of members between the selected and tapped member.
5. THE Tab_Pager SHALL keep the selected index within the closed interval from zero to one less than
   the pageable set length at all times, including while a drag is in progress and while a tap-driven
   animation is running (invariant).
6. FOR ALL sequences of tab taps and completed swipes, THE Tab_Pager selected index, the rendered
   page and the tab indicator position SHALL agree once every settling and tap animation has
   completed (invariant).
7. THE Tab_Pager SHALL preserve each member's scroll offset to within 1 logical pixel and each
   member's loaded page state for the lifetime of the enclosing route, and SHALL restore both on
   return to that member without refetching already loaded pages.
8. WHERE a Sibling_Tab_Set member is not visible to the viewer, THE Tab_Pager SHALL exclude that
   member from the pageable set, SHALL keep the relative order of the remaining members unchanged,
   and SHALL select the first remaining member where the previously selected member is the excluded
   one.
9. WHERE a profile Sibling_Tab_Set is restored from a route parameter naming a member of the pageable
   set, THE Tab_Pager SHALL open on that member with no page or indicator animation.
10. WHILE Reduced_Motion is enabled, THE Tab_Pager SHALL apply no page slide transform, SHALL change
    pages with an opacity fade of 90 milliseconds, SHALL move the tab indicator to its settled
    position within 90 milliseconds, and SHALL retain the drag-tracking behaviour of criterion 3 and
    the commit behaviour of criterion 2 unchanged.
11. IF a horizontal drag on a Sibling_Tab_Set ends with cumulative horizontal displacement below 25
    percent of the pager viewport width and with horizontal release velocity below 400 logical pixels
    per second, THEN THE Tab_Pager SHALL settle back on the originating member within a Token_Set
    duration of at most 480 milliseconds, SHALL return the tab indicator to the originating label
    position, and SHALL leave the selected tab state and each member's scroll offset unchanged.
12. IF a horizontal drag would page past the first or the last member of the pageable set, THEN THE
    Tab_Pager SHALL leave the selected index unchanged, SHALL limit visible travel beyond that edge to
    at most 32 logical pixels, SHALL return to the rest position on release, and SHALL not wrap to the
    opposite end.
13. IF a route parameter names a tab that is empty or absent from the pageable set, THEN THE
    Tab_Pager SHALL open on the first member of the pageable set, SHALL set the selected tab state to
    that member, and SHALL surface no error indication to the viewer.

### Requirement 15: Gesture-contract preservation

**User Story:** As a signed-in collector, I want swipe navigation not to break the gestures the
product is built on, so that tapping a card still does exactly what it always did.

#### Acceptance Criteria

1. THE Tab_Pager SHALL leave the Gesture_Contract unchanged on every card it contains, such that a
   single tap opens the Closeup, a double tap opens the immersive viewer and a long press opens the
   radial quick-action peek with the same destination the card reaches when it is presented outside a
   Tab_Pager (invariant).
2. IF a pointer sequence begins inside a descendant widget that claims horizontal drags, THEN THE
   Tab_Pager SHALL yield the whole pointer sequence to that descendant and SHALL leave the selected
   tab index unchanged.
3. WHILE a full-screen photo viewer or a Closeup media pager is open, THE Tab_Pager SHALL leave the
   selected tab index unchanged for every horizontal drag of any distance.
4. WHILE a swipe-to-reply drag is in progress on a message bubble, THE Tab_Pager SHALL leave the
   selected tab index unchanged for every horizontal drag of any distance.
5. WHEN a single tap lands on a surf card, THE surf card SHALL begin the Closeup transition within
   100 milliseconds of pointer release, before the 300 millisecond double-tap window expires.
6. WHEN a second tap lands on the same surf card within 300 milliseconds of the first pointer release
   and within 18 logical pixels of the first contact point, THE surf card SHALL cancel the Closeup
   transition, SHALL leave no Closeup route on the navigation stack, and SHALL open the immersive
   viewer.
7. WHEN a press on a surf card is held for 500 milliseconds with pointer movement of at most 18
   logical pixels, THE surf card SHALL open the radial quick-action peek and SHALL leave the Closeup
   transition unstarted.
8. THE Chat_Thread SHALL let at most one of swipe-to-reply, a conversation-tile swipe action and a
   Tab_Pager page change respond to any single pointer sequence (invariant).
9. IF a pointer sequence's vertical displacement exceeds its horizontal displacement at the moment
   its total displacement first exceeds 18 logical pixels, THEN THE Tab_Pager SHALL yield that
   sequence to the enclosing vertical scrollable and SHALL leave the selected tab index unchanged.
10. WHEN a full-screen photo viewer closes, a Closeup media pager closes, or a swipe-to-reply drag
    ends, THE Tab_Pager SHALL accept horizontal drags again within 120 milliseconds.
11. IF a press on a surf card moves more than 18 logical pixels before 500 milliseconds elapse, THEN
    THE surf card SHALL leave the radial quick-action peek closed and the Closeup unopened, and THE
    Tab_Pager SHALL take that sequence as a drag subject to criteria 2, 3, 4 and 9.

### Requirement 16: Design token and accessibility compliance

**User Story:** As a maintainer, I want every new surface to obey the design system and the
accessibility floor, so that this feature does not erode the contract.

#### Acceptance Criteria

1. THE mobile client SHALL read every colour, radius, duration, spacing, stroke and easing value used
   by a file added or changed by this feature from the Token_Set, and every such file other than the
   generated Token_Set file itself SHALL contain zero colour literals, zero radius literals, zero
   duration literals, zero spacing literals, zero stroke-width literals and zero easing-curve
   literals (invariant).
2. THE Notification_Banner, Alert_Center filter rail, Call_Screen, Call_Pill, Tombstone,
   Group_Info_Screen and Tab_Pager SHALL each render text below 24 logical pixels regular weight or
   below 19 logical pixels bold weight at a contrast ratio of at least 4.5 to 1 against the surface
   composited behind it, and SHALL each render text at or above those sizes, icon glyphs and selection
   indicators at a contrast ratio of at least 3 to 1 against the surface composited behind them, in
   both the dark theme and the light theme, in the rest, selected, pressed and error states, excluding
   targets rendered in a disabled state.
3. THE Notification_Banner, Alert_Center filter rail, Call_Screen, Call_Pill and Tab_Pager SHALL give
   every interactive target a hit area of at least the Token_Set `tapTargetMin` value of 44 by 44
   logical pixels including hit slop, and SHALL expose for every interactive target carrying no
   visible text label a text alternative naming that target's action together with its enabled or
   disabled state.
4. WHEN Call_Phase changes, THE Call_Screen SHALL announce the resulting Call_Phase through a
   screen-reader live region within 1 second of that change and at most once per change.
5. THE Notification_Banner, Call_Screen, Call_Pill and Tab_Pager SHALL signal every selected,
   unselected, on, off, enabled and disabled state through at least one non-colour channel out of
   glyph fill, glyph shape and visible text label, in addition to any colour difference, so that the
   state remains distinguishable when the surface is rendered without colour (invariant).
6. WHERE an animation is added by this feature, THE animation SHALL take its duration and easing from
   the Token_Set and that duration SHALL be at least 90 milliseconds and at most 480 milliseconds,
   and WHILE Reduced_Motion is enabled THE animation SHALL be replaced by an opacity fade of 90
   milliseconds.
7. THE mobile client SHALL report zero issues at info, warning and error severity from `flutter
   analyze` and zero failing tests from a single non-watching run of the complete `flutter test`
   suite, with no test added or changed by this feature marked as skipped.
8. IF a surface added or changed by this feature requires a colour, radius, duration, spacing, stroke
   or easing value that the Token_Set does not carry, THEN that value SHALL be added to the Token_Set
   source and the Token_Set regenerated before the surface consumes it, and the surface SHALL consume
   the regenerated Token_Set entry rather than a literal.
9. WHEN a Notification_Category filter selection changes, THE Alert_Center SHALL announce the
   selected category and the number of notifications rendered for that selection through a
   screen-reader live region within 1 second of the rendered list settling and at most once per
   selection change.
10. WHILE the platform text scale factor is any value from 1.0 through 2.0, THE Notification_Banner,
    Alert_Center filter rail, Call_Screen, Call_Pill, Tombstone, Group_Info_Screen and Tab_Pager SHALL
    render every visible text label without overflow beyond its container, without overlap of an
    adjacent element, and with every interactive target retaining the 44 by 44 logical-pixel minimum
    of criterion 3.
