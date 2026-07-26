import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../core/notifications/local_notifications.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import '../chat/chat_api.dart';
import '../profile/profile_queries.dart';
import 'notification_copy.dart';
import 'notification_preferences.dart';
import 'notifications_screen.dart' show notificationStyle;

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

/// Turns a realtime `notifications` INSERT into the right surface:
///
///  * type muted in preferences → nothing;
///  * app backgrounded-but-running → system tray (channels `social`/`calls`,
///    matching the push-fanout edge function);
///  * foreground on the originating screen (that conversation open, that
///    entity's closeup, or the Alerts list itself) → nothing, the screen is
///    already live;
///  * any other foreground screen → [KBanner] under the status bar.
class NotificationPresenter {
  /// Creates the presenter.
  NotificationPresenter(this._ref);

  final Ref _ref;
  String? _lastPresentedId;

  KlectApi get _api => _ref.read(klectApiProvider);

  /// Surfaces [incoming]. [context] anchors the banner overlay and theme.
  Future<void> present(BuildContext context, NotificationModel incoming) async {
    // Server-side dedupe bumps `count` on repeats (an UPDATE, not an INSERT),
    // so a repeated id here can only be a replay artifact — drop it.
    if (incoming.id == _lastPresentedId) return;
    _lastPresentedId = incoming.id;

    if (_ref.read(notificationPreferencesProvider).contains(incoming.type)) {
      return;
    }

    // The realtime row carries no joined actor; the name/avatar (and the
    // follow/match destination) need the profile.
    final model = await _enrichActor(incoming);
    final destination = notificationDestination(model);
    final title = notificationActorLabel(model);
    final preview = notificationPreview(model);
    final phrase = notificationPhrase(model);
    final message = preview == null ? phrase : '$phrase: $preview';

    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final backgrounded =
        lifecycle != null && lifecycle != AppLifecycleState.resumed;
    if (backgrounded) {
      await _ref.read(localNotificationsProvider).show(
            id: model.id.hashCode,
            title: title,
            body: message,
            isCall: model.type == NotificationType.call,
            payload: destination,
          );
      return;
    }

    if (_suppressed(destination)) return;

    // An entity thumb makes "liked your item" legible at a glance. Fetched
    // best-effort — a thumbless banner beats a late one.
    String? thumbUrl;
    String? thumbBlurhash;
    final entityType = model.entityType;
    final entityId = model.entityId;
    if (entityType != null &&
        entityId != null &&
        entityType != EntityType.comment) {
      try {
        final entityPreview = await _ref
            .read(chatApiProvider)
            .fetchEntityPreview(entityType, entityId);
        thumbUrl = _api.publicUrl(entityPreview?.coverPath);
        thumbBlurhash = entityPreview?.coverBlurhash;
      } on KlectError {
        // Banner still shows, just without the thumb.
      }
    }

    if (!context.mounted) return;
    // The user may have navigated onto the originating screen while we were
    // fetching; re-check before interrupting them.
    if (_suppressed(destination)) return;

    final style = notificationStyle(context.kc, model.type);
    KBanner.show(
      context,
      title: title,
      message: message,
      avatarUrl: avatarUrlOf(_api, model.actor?.avatarPath),
      avatarName: model.actor?.name,
      icon: style.icon,
      iconTint: style.tint,
      thumbUrl: thumbUrl,
      thumbBlurhash: thumbBlurhash,
      onTap: destination == null
          ? null
          : () => _ref.read(routerProvider).push(destination),
    );
  }

  /// True when the banner would announce the screen the user is looking at.
  bool _suppressed(String? destination) {
    final location = _currentPath();
    if (location == null) return false;
    // The Alerts list updates live; a banner over it is noise.
    if (location == Routes.notifications) return true;
    if (destination == null) return false;
    return location == destination || location.startsWith('$destination/');
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
    try {
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
    } on KlectError {
      return incoming;
    }
  }
}
