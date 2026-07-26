import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../shell/root_shell.dart';
import 'notification_events.dart';

/// The viewer's notifications, kept live.
///
/// Repeats are deduped **server-side** by bumping `count` on the existing row
/// rather than inserting a second one, so an INSERT on the stream is always a
/// genuinely new notification and can simply be prepended. The realtime payload
/// carries no joined actor, so the actor profile is fetched once and merged in
/// — the row appears immediately and fills in a beat later, rather than the
/// whole list reloading.
class NotificationsController extends AsyncNotifier<List<NotificationModel>> {
  KlectApi get _api => ref.read(klectApiProvider);

  @override
  Future<List<NotificationModel>> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const <NotificationModel>[];

    final api = ref.watch(klectApiProvider);
    // The realtime channel lives at shell level (notificationEventsProvider)
    // so the badge and banner are live before this list is ever opened; here
    // we only fold its events into the loaded list. The id-dedupe in
    // [_onInsert] makes a replayed event harmless.
    ref.listen(notificationEventsProvider, (previous, next) {
      final incoming = next.value;
      if (incoming != null) _onInsert(incoming);
    });

    return api.fetchNotifications();
  }

  void _onInsert(NotificationModel incoming) {
    final current = state.value ?? const <NotificationModel>[];
    if (current.any((existing) => existing.id == incoming.id)) return;

    state = AsyncData<List<NotificationModel>>(
      <NotificationModel>[incoming, ...current],
    );
    ref.invalidate(unreadNotificationCountProvider);
    unawaited(_enrichActor(incoming));
  }

  Future<void> _enrichActor(NotificationModel notification) async {
    final actorId = notification.actorId;
    if (actorId == null) return;
    try {
      final actor = await _api.fetchProfile(actorId);
      if (actor == null) return;
      final current = state.value;
      if (current == null) return;
      state = AsyncData<List<NotificationModel>>(<NotificationModel>[
        for (final existing in current)
          if (existing.id == notification.id)
            NotificationModel(
              id: existing.id,
              type: existing.type,
              userId: existing.userId,
              actorId: existing.actorId,
              entityType: existing.entityType,
              entityId: existing.entityId,
              commentId: existing.commentId,
              messageId: existing.messageId,
              conversationId: existing.conversationId,
              body: existing.body,
              count: existing.count,
              readAt: existing.readAt,
              createdAt: existing.createdAt,
              actor: actor,
            )
          else
            existing,
      ]);
    } on KlectError {
      // A missing actor profile is not worth surfacing: the row still renders
      // with its initials fallback.
    }
  }

  /// Re-reads the list from the server.
  Future<void> refresh() async {
    state = await AsyncValue.guard(() => _api.fetchNotifications());
    ref.invalidate(unreadNotificationCountProvider);
  }

  /// Marks one notification read, optimistically.
  Future<void> markRead(String id) async {
    final current = state.value;
    if (current == null) return;
    var alreadyRead = true;
    for (final existing in current) {
      if (existing.id == id) {
        alreadyRead = !existing.isUnread;
        break;
      }
    }
    if (alreadyRead) return;

    state = AsyncData<List<NotificationModel>>(<NotificationModel>[
      for (final existing in current)
        if (existing.id == id) existing.markRead() else existing,
    ]);
    try {
      await _api.markNotificationsRead(ids: <String>[id]);
    } on KlectError {
      // The badge is reconciled from the server on the next read; leaving the
      // row visually read is the honest reflection of the user's intent.
    }
    ref.invalidate(unreadNotificationCountProvider);
  }

  /// Marks everything read.
  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData<List<NotificationModel>>(<NotificationModel>[
      for (final existing in current) existing.markRead(),
    ]);
    try {
      await _api.markNotificationsRead();
    } on KlectError {
      await refresh();
      return;
    }
    ref.invalidate(unreadNotificationCountProvider);
  }
}

/// The live notification list.
final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, List<NotificationModel>>(
  NotificationsController.new,
  name: 'notifications',
);
