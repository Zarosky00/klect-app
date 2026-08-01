import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/klect_api.dart';
import '../../core/interactions/interaction_controller.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../core/notifications/local_notifications.dart';
import '../../core/notifications/push_notifications.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import '../chat/calls/call_controller.dart';
import '../chat/calls/incoming_call_controller.dart';
import '../chat/chat_api.dart';
import '../profile/profile_queries.dart';
import 'notification_copy.dart';
import 'notification_preferences.dart';

/// The tray-notification service, wired so a tap deep-links through the app
/// router.
final localNotificationsProvider = Provider<LocalNotifications>(
  (ref) => LocalNotifications(
    onSelect: (path) => ref.read(routerProvider).push(path),
  ),
  name: 'localNotifications',
);

/// Decides how one realtime notification is surfaced.
final notificationPresenterProvider = Provider<NotificationPresenter>(
  NotificationPresenter.new,
  name: 'notificationPresenter',
);

/// FCM device push registration — inert (no crash, no-op) until a
/// `google-services.json`/`GoogleService-Info.plist` is bundled and the
/// server-side secrets in `docs/OPERATIONS.md` §2 are configured.
final pushNotificationsProvider = Provider<PushNotifications>((ref) {
  final service = PushNotifications(ref.read(klectApiProvider));
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
}, name: 'pushNotifications');

// ── The pure decision ────────────────────────────────────────────────────────
//
// Everything the presenter decides is decided here, as one total function over
// values: the notification, the resolved content, the preference set, the
// current route, the call row status, whether an entry is already mounted and
// which ids have already been surfaced. No I/O, no `BuildContext`, no clock —
// so the whole of Requirements 3.8–3.11 and 5.5 is testable without a widget
// tree, and the presenter below is left holding nothing but the plumbing.

/// How many notification ids the session remembers (Requirement 3.10).
const int bannerRecentIdCapacity = 50;

/// Why a notification did not reach the screen.
enum BannerSuppression {
  /// This id has already been surfaced in this session (Requirement 3.10).
  duplicateId,

  /// The account switched this category off (Requirement 5.5).
  categoryDisabled,

  /// The user is already looking at what the banner would announce
  /// (Requirement 3.8).
  onDestinationRoute,

  /// The Alert Center is open and updates live (Requirement 3.9).
  onAlertCenter,

  /// The call is no longer ringing, so accept/decline would be a lie
  /// (Requirement 3.11).
  callNotRinging,

  /// An entry is already mounted; the newer notification is dropped rather
  /// than queued (Requirement 2.8).
  bannerMounted,
}

/// What the Banner_Presenter should do with one notification.
///
/// [PresentBanner] carries the composed [BannerContent] rather than a
/// `NotificationBannerData`: the glyph tint is read from the theme and the
/// thumbnail from storage, neither of which a pure decision may touch. The
/// presenter dresses the content once the decision says yes.
sealed class BannerDecision {
  const BannerDecision();

  /// Show [content].
  const factory BannerDecision.present(BannerContent content) = PresentBanner;

  /// Show nothing, for [reason].
  const factory BannerDecision.suppress(BannerSuppression reason) =
      SuppressBanner;

  /// The content to render, or null where the decision was to suppress.
  BannerContent? get content;

  /// Why nothing is rendered, or null where the decision was to present.
  BannerSuppression? get suppression;
}

/// A decision to render [content].
final class PresentBanner extends BannerDecision {
  /// Creates a present decision.
  const PresentBanner(this.content);

  @override
  final BannerContent content;

  @override
  BannerSuppression? get suppression => null;

  @override
  bool operator ==(Object other) =>
      other is PresentBanner && other.content == content;

  @override
  int get hashCode => content.hashCode;

  @override
  String toString() => 'BannerDecision.present(${content.category.wire})';
}

/// A decision to render nothing.
final class SuppressBanner extends BannerDecision {
  /// Creates a suppress decision.
  const SuppressBanner(this.reason);

  /// Why nothing is rendered.
  final BannerSuppression reason;

  @override
  BannerContent? get content => null;

  @override
  BannerSuppression? get suppression => reason;

  @override
  bool operator ==(Object other) =>
      other is SuppressBanner && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'BannerDecision.suppress(${reason.name})';
}

/// Decides whether [notification] reaches the screen.
///
/// Total and deterministic: the same arguments always yield the same decision,
/// and every argument is a plain value. The gates are ordered cheapest-first,
/// and the first one that fires wins, so exactly one [BannerSuppression] is
/// ever reported:
///
///  1. [BannerSuppression.duplicateId] — the id is inside the session's
///     [bannerRecentIdCapacity]-entry memory (Requirement 3.10);
///  2. [BannerSuppression.bannerMounted] — an entry is up (Requirement 2.8);
///  3. [BannerSuppression.categoryDisabled] — the switch is off (5.5);
///  4. [BannerSuppression.onAlertCenter] — the Alert Center is open (3.9);
///  5. [BannerSuppression.onDestinationRoute] — the destination is already on
///     screen, entity id parameters and path-segment children included (3.8);
///  6. [BannerSuppression.callNotRinging] — the call row moved on (3.11).
///
/// [callStatus] is only consulted for [NotificationType.call]; a null status
/// there means the row could not be confirmed as ringing, which suppresses.
BannerDecision decideBanner({
  required NotificationModel notification,
  required NotificationPreferenceSet preferences,
  required String? currentRoute,
  required CallStatus? callStatus,
  required bool bannerMounted,
  required Set<String> recentlyPresented,
  required BannerContent content,
}) {
  if (recentlyPresented.contains(notification.id)) {
    return const BannerDecision.suppress(BannerSuppression.duplicateId);
  }
  if (bannerMounted) {
    return const BannerDecision.suppress(BannerSuppression.bannerMounted);
  }
  if (!preferences.isEnabled(content.category)) {
    return const BannerDecision.suppress(BannerSuppression.categoryDisabled);
  }
  if (bannerRouteMatches(currentRoute, Routes.notifications)) {
    return const BannerDecision.suppress(BannerSuppression.onAlertCenter);
  }
  if (bannerRouteMatches(currentRoute, content.destination)) {
    return const BannerDecision.suppress(BannerSuppression.onDestinationRoute);
  }
  if (notification.type == NotificationType.call &&
      callStatus != CallStatus.ringing) {
    return const BannerDecision.suppress(BannerSuppression.callNotRinging);
  }
  return BannerDecision.present(content);
}

/// Whether [currentRoute] is [destination] or a screen pushed inside it.
///
/// Compares whole path segments, so `/messages/abc` matches `/messages/abc` and
/// `/messages/abc/info` but never `/messages/abcd` (Requirement 3.8). Query
/// strings and fragments are ignored, and a trailing slash is not a difference.
bool bannerRouteMatches(String? currentRoute, String? destination) {
  if (currentRoute == null || destination == null) return false;
  final current = _normaliseRoute(currentRoute);
  final target = _normaliseRoute(destination);
  if (current.isEmpty || target.isEmpty) return false;
  return current == target || current.startsWith('$target/');
}

String _normaliseRoute(String route) {
  final path = Uri.tryParse(route)?.path ?? route;
  if (path.length > 1 && path.endsWith('/')) {
    return path.substring(0, path.length - 1);
  }
  return path;
}

/// The session's bounded memory of the ids already surfaced.
///
/// Insertion-ordered and capped at [capacity]: remembering a 51st id forgets
/// the oldest, so the memory never grows and a long session cannot leak
/// (Requirement 3.10). Replaces the single-slot `_lastPresentedId` the
/// presenter used to carry, which only ever caught back-to-back replays.
class RecentNotificationIds {
  /// Creates an empty memory.
  RecentNotificationIds({this.capacity = bannerRecentIdCapacity});

  /// How many ids are retained.
  final int capacity;

  // Dart's default Set is a LinkedHashSet, so `first` is the oldest insertion.
  final Set<String> _ids = <String>{};

  /// The retained ids, oldest first.
  Set<String> get ids => UnmodifiableSetView<String>(_ids);

  /// How many ids are retained right now.
  int get length => _ids.length;

  /// Whether [id] is still remembered.
  bool contains(String id) => _ids.contains(id);

  /// Records [id], evicting the oldest entry beyond [capacity].
  ///
  /// Returns false when [id] was already remembered, which is exactly the
  /// duplicate the presenter drops.
  bool remember(String id) {
    if (!_ids.add(id)) return false;
    while (_ids.length > capacity) {
      _ids.remove(_ids.first);
    }
    return true;
  }

  /// Forgets everything. Test-only; a real session never resets.
  @visibleForTesting
  void clear() => _ids.clear();
}

/// The one budget every banner resolution runs inside (Requirements 1.3, 1.4,
/// 1.11).
///
/// One timer shared by every lookup a single notification needs — actor
/// profile, entity cover, call row — so the *whole* resolution is bounded at
/// [budget] rather than each lookup getting its own 2 seconds. A lookup that
/// loses the race, or fails, resolves to its fallback and surfaces no error:
/// a thumbless banner now beats a complete one later.
class BannerResolutionBudget {
  /// Arms the budget. [close] must be called once the resolution is done.
  BannerResolutionBudget({this.budget = Timeouts.thumbnail}) {
    _timer = Timer(budget, _expire);
  }

  /// How long the whole resolution may take.
  final Duration budget;

  final Completer<void> _expired = Completer<void>();
  late final Timer _timer;

  /// Whether the budget has run out.
  bool get isExpired => _expired.isCompleted;

  /// [work]'s result, or [fallback] if the budget runs out or [work] fails.
  Future<T> race<T>(Future<T> work, T fallback) => Future.any(<Future<T>>[
    work.then<T>((T value) => value, onError: (_, _) => fallback),
    _expired.future.then<T>((_) => fallback),
  ]);

  /// Releases the timer. Safe to call more than once.
  void close() {
    _timer.cancel();
    _expire();
  }

  void _expire() {
    if (!_expired.isCompleted) _expired.complete();
  }
}

/// Everything a banner needs that only I/O can answer.
typedef BannerResolution = ({
  /// The notification with its actor joined, where the profile resolved.
  NotificationModel notification,

  /// Absolute URL of the entity cover, or null.
  String? thumbUrl,

  /// The cover's blurhash, rendered until the cover decodes (Requirement 1.5).
  String? thumbBlurhash,

  /// The call row's status, for the ringing check (Requirement 3.11).
  CallStatus? callStatus,
});

/// Keys the one-shot effects a banner action can fire.
///
/// A follow-back is keyed by the actor; accept and decline share their call's
/// key, because answering and declining the same call are two names for the
/// same terminal decision — whichever lands first is the only one that may
/// land (Requirements 3.2, 3.3).
abstract final class BannerEffectKeys {
  /// The follow-back key for [actorId].
  static String follow(String actorId) => 'follow:$actorId';

  /// The shared accept/decline key for [callId].
  static String call(String callId) => 'call:$callId';
}

/// Runs each banner effect at most once.
///
/// The banner already disables its buttons while one is in flight, but the
/// guard is what makes "exactly one effect per action" hold across a re-render,
/// a second delivery of the same row and a second banner for the same actor or
/// call: a claimed key is a no-op, so no RPC is issued twice.
///
/// A failing effect releases its key and rethrows, so the banner can keep
/// itself up for a retry rather than confirming something that never happened.
class BannerEffectGuard {
  final Set<String> _claimed = <String>{};

  /// The keys claimed so far. Test-only.
  @visibleForTesting
  Set<String> get claimed => UnmodifiableSetView<String>(_claimed);

  /// Whether [key] has already been claimed.
  bool isClaimed(String key) => _claimed.contains(key);

  /// Runs [effect] if [key] is unclaimed, and does nothing at all if it is not.
  Future<void> runOnce(String key, Future<void> Function() effect) async {
    if (!_claimed.add(key)) return;
    try {
      await effect();
    } on Object {
      _claimed.remove(key);
      rethrow;
    }
  }
}

/// Turns a realtime `notifications` INSERT into the right surface:
///
///  * category switched off in the Preference_Store → nothing;
///  * app backgrounded-but-running → system tray (channels `social`/`calls`,
///    matching the push-fanout edge function);
///  * foreground on the originating screen (that conversation open, that
///    entity's closeup, or the Alerts list itself) → nothing, the screen is
///    already live;
///  * any other foreground screen → [KNotificationBanner] under the status bar.
///
/// The interesting part — *whether* to present — is [decideBanner], a pure
/// function. This class does the resolving that decision needs, inside one
/// [BannerResolutionBudget], and then renders. Action effects (follow back,
/// accept, decline) are attached here, one apiece and each behind
/// [BannerEffectGuard]; the decision only carries their specs on
/// [BannerContent.actions].
class NotificationPresenter {
  /// Creates the presenter.
  NotificationPresenter(this._ref);

  final Ref _ref;

  final RecentNotificationIds _recent = RecentNotificationIds();

  final BannerEffectGuard _effects = BannerEffectGuard();

  /// Ids whose resolution is in flight, so two realtime deliveries of the same
  /// row cannot both get past the memory check while awaiting I/O.
  final Set<String> _resolving = <String>{};

  KlectApi get _api => _ref.read(klectApiProvider);

  /// The ids this session has already surfaced, oldest first.
  Set<String> get recentlyPresented => _recent.ids;

  /// Surfaces [incoming]. [context] anchors the banner overlay and theme.
  Future<void> present(BuildContext context, NotificationModel incoming) async {
    // Server-side dedupe bumps `count` on repeats (an UPDATE, not an INSERT),
    // so a repeated id here can only be a replay artifact — drop it.
    if (_recent.contains(incoming.id)) return;
    if (!_resolving.add(incoming.id)) return;
    try {
      final preferences = _ref.read(resolvedNotificationPreferencesProvider);
      // Composed from the un-enriched row purely to learn the category and the
      // thumbnail reference; the real content is composed again below, once the
      // actor is joined, because a follow destination needs the username.
      final draft = bannerContentFor(incoming);

      // The cheapest gate, checked before any I/O: a muted category should cost
      // nothing at all (Requirement 5.5).
      if (!preferences.isEnabled(draft.category)) return;

      final resolved = await _resolve(incoming, draft);
      final model = resolved.notification;
      final content = bannerContentFor(model);

      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final backgrounded =
          lifecycle != null && lifecycle != AppLifecycleState.resumed;
      if (backgrounded) {
        _recent.remember(model.id);
        await _ref
            .read(localNotificationsProvider)
            .show(
              id: model.id.hashCode,
              title: content.title,
              body: content.message,
              isCall: model.type == NotificationType.call,
              payload: content.destination,
            );
        return;
      }

      if (!context.mounted) return;
      // The route, the mounted entry and the preference set are all re-read
      // here: the user may have navigated onto the originating screen, or
      // flipped the switch, while the resolution was in flight.
      final decision = decideBanner(
        notification: model,
        preferences: _ref.read(resolvedNotificationPreferencesProvider),
        currentRoute: _currentPath(),
        callStatus: resolved.callStatus,
        bannerMounted: KNotificationBanner.isMounted,
        recentlyPresented: _recent.ids,
        content: content,
      );
      if (decision is! PresentBanner) return;

      _recent.remember(model.id);
      final style = decision.content.category.style(context.kc);
      KNotificationBanner.show(
        context,
        NotificationBannerData(
          notificationId: model.id,
          title: decision.content.title,
          message: decision.content.message,
          glyph: style.glyph,
          glyphTint: style.tint,
          avatarUrl: avatarUrlOf(_api, model.actor?.avatarPath),
          avatarLabel: decision.content.actorLabel,
          thumbUrl: resolved.thumbUrl,
          thumbBlurhash: resolved.thumbBlurhash,
          actions: bannerActionsFor(model, decision.content),
          onTap: () => _open(decision.content.destination),
        ),
      );
    } finally {
      _resolving.remove(incoming.id);
    }
  }

  /// Resolves the actor, the entity cover and the call status concurrently,
  /// all inside one [BannerResolutionBudget].
  ///
  /// Returns after at most [Timeouts.thumbnail]: whatever has landed by then is
  /// used, and whatever has not falls back — the un-enriched row (so the avatar
  /// renders as initials, Requirement 1.11), no thumbnail (Requirement 1.4) and
  /// no call status (which suppresses a call banner rather than offering an
  /// accept that cannot be honoured).
  Future<BannerResolution> _resolve(
    NotificationModel incoming,
    BannerContent draft,
  ) async {
    final budget = BannerResolutionBudget();
    try {
      final (
        NotificationModel notification,
        ({String? blurhash, String? url}) thumb,
        CallStatus? callStatus,
      ) = await (
        budget.race(_enrichActor(incoming), incoming),
        budget.race(_fetchThumb(draft.thumb), _noThumb),
        budget.race(_fetchCallStatus(bannerCallId(incoming)), null),
      ).wait;
      return (
        notification: notification,
        thumbUrl: thumb.url,
        thumbBlurhash: thumb.blurhash,
        callStatus: callStatus,
      );
    } finally {
      budget.close();
    }
  }

  static const ({String? blurhash, String? url}) _noThumb = (
    url: null,
    blurhash: null,
  );

  /// The entity cover an "liked your item" banner is legible with.
  Future<({String? blurhash, String? url})> _fetchThumb(
    BannerThumbRef? thumb,
  ) async {
    if (thumb == null) return _noThumb;
    final preview = await _ref
        .read(chatApiProvider)
        .fetchEntityPreview(thumb.entityType, thumb.entityId);
    return (
      url: _api.publicUrl(preview?.coverPath),
      blurhash: preview?.coverBlurhash,
    );
  }

  /// The live status of the call a `call` notification points at.
  Future<CallStatus?> _fetchCallStatus(String? callId) async {
    if (callId == null) return null;
    final call = await _ref.read(chatApiProvider).fetchCall(callId);
    return call?.status;
  }

  // ── Action effects ─────────────────────────────────────────────────────────

  /// Dresses [content]'s action specs with their single effects
  /// (Requirements 3.2, 3.3).
  ///
  /// A spec whose effect has nothing to act on — a follow-back with no actor id,
  /// an accept with no call id — is dropped rather than rendered as a button
  /// that cannot do its job.
  @visibleForTesting
  List<NotificationBannerAction> bannerActionsFor(
    NotificationModel notification,
    BannerContent content,
  ) {
    final actions = <NotificationBannerAction>[];
    for (final spec in content.actions) {
      final effect = _effectFor(notification, content, spec);
      if (effect == null) continue;
      actions.add(
        NotificationBannerAction(
          label: spec.label,
          semanticLabel: spec.semanticLabel,
          confirmedLabel: spec.confirmedLabel,
          onActivate: effect,
        ),
      );
    }
    return actions;
  }

  Future<void> Function()? _effectFor(
    NotificationModel notification,
    BannerContent content,
    BannerActionSpec spec,
  ) {
    switch (spec.kind) {
      case BannerActionKind.followBack:
        final actorId = notification.actorId;
        if (actorId == null) return null;
        return () => _effects.runOnce(
          BannerEffectKeys.follow(actorId),
          () => _followBack(notification, actorId),
        );
      case BannerActionKind.acceptCall:
        final callId = content.callId;
        if (callId == null) return null;
        return () => _effects.runOnce(
          BannerEffectKeys.call(callId),
          () => _acceptCall(callId),
        );
      case BannerActionKind.declineCall:
        final callId = content.callId;
        if (callId == null) return null;
        return () => _effects.runOnce(
          BannerEffectKeys.call(callId),
          () => _declineCall(callId),
        );
    }
  }

  /// Follows the actor back — one follow, never an unfollow (Requirement 3.2).
  ///
  /// `toggle_follow` is a toggle, so the server is asked first: a viewer who
  /// already follows the actor is left alone rather than silently unfollowed.
  /// The write then goes through the same optimistic engine every other follow
  /// button uses, so the count, the feedback toast and the offline queue all
  /// behave exactly as they do on a profile.
  ///
  /// Throws where the follow was refused outright, which keeps the banner up
  /// for a retry instead of confirming a follow that never landed. A retryable
  /// failure is queued by the engine and counts as done.
  Future<void> _followBack(
    NotificationModel notification,
    String actorId,
  ) async {
    if (await _api.hasFollowed(actorId)) return;
    final follows = _ref.read(followProvider(actorId).notifier);
    await follows.toggle(
      targetLabel: notification.actor?.name,
      targetAvatarPath: notification.actor?.avatarPath,
    );
    if (!_ref.read(followProvider(actorId)).following) {
      throw StateError('follow_back_refused');
    }
  }

  /// Answers [callId] and opens the Call_Screen (Requirement 3.3).
  ///
  /// The engine is attached first where it has not seen the row yet — the
  /// notification can beat the realtime INSERT — so `accept` has a presented
  /// call to answer. The Call_Screen is opened either way: a call that died
  /// between ringing and the tap explains itself there.
  Future<void> _acceptCall(String callId) async {
    final calls = _ref.read(activeCallProvider.notifier);
    if (_ref.read(activeCallProvider).call?.id != callId) {
      await calls.attach(callId);
    }
    if (_ref.read(activeCallProvider).call?.id == callId) {
      await calls.accept();
    }
    _ref.read(incomingCallProvider.notifier).clear();
    _open(KlectLinks.callPath(callId));
  }

  /// Declines [callId] without navigating anywhere (Requirement 3.3).
  ///
  /// The engine owns the decline where it holds the call, so the media tracks
  /// are released with it; otherwise the `decline_call` RPC is issued on its
  /// own for the row the banner is about.
  Future<void> _declineCall(String callId) async {
    final calls = _ref.read(activeCallProvider.notifier);
    if (_ref.read(activeCallProvider).call?.id == callId) {
      await calls.decline();
    } else {
      await _api.updateCallStatus(callId, CallStatus.declined);
    }
    _ref.read(incomingCallProvider.notifier).clear();
  }

  /// Opens [destination], falling back to the Alert Center where the
  /// notification points nowhere the router can reach (Requirement 3.13).
  void _open(String? destination) {
    final router = _ref.read(routerProvider);
    if (destination == null || destination.isEmpty) {
      router.push(Routes.notifications);
      return;
    }
    try {
      router.push(destination);
    } on Object {
      router.push(Routes.notifications);
    }
  }

  String? _currentPath() {
    try {
      return _ref
          .read(routerProvider)
          .routerDelegate
          .currentConfiguration
          .uri
          .path;
    } on Object {
      return null;
    }
  }

  Future<NotificationModel> _enrichActor(NotificationModel incoming) async {
    final actorId = incoming.actorId;
    if (incoming.actor != null || actorId == null) return incoming;
    final actor = await _api.fetchProfile(actorId);
    if (actor == null) return incoming;
    return NotificationModel(
      id: incoming.id,
      type: incoming.type,
      userId: incoming.userId,
      actorId: incoming.actorId,
      entityType: incoming.entityType,
      entityId: incoming.entityId,
      commentId: incoming.commentId,
      messageId: incoming.messageId,
      conversationId: incoming.conversationId,
      body: incoming.body,
      count: incoming.count,
      readAt: incoming.readAt,
      createdAt: incoming.createdAt,
      actor: actor,
    );
  }
}
