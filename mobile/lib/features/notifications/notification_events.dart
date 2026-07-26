import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';

/// The **one** realtime channel of incoming notifications, owned at shell
/// level.
///
/// `RootShell` watches this, so it subscribes the moment the signed-in shell
/// exists — not on the first visit to the Alerts tab. Everything downstream
/// hangs off this single stream:
///
///  * the tab badge (`unreadNotificationCountProvider` is invalidated per
///    event),
///  * the in-app `KBanner` / backgrounded local notification (see
///    `notification_surfaces.dart`),
///  * the Alerts list itself (`NotificationsController` folds events in
///    instead of subscribing its own channel).
///
/// Server-side dedupe bumps `count` on repeats rather than inserting, so an
/// INSERT here is always a genuinely new notification.
final notificationEventsProvider = StreamProvider<NotificationModel>(
  (ref) {
    final controller = StreamController<NotificationModel>.broadcast();
    ref.onDispose(controller.close);

    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return controller.stream;

    final api = ref.watch(klectApiProvider);
    final channel = api.notificationsChannel(
      onInsert: (row) {
        final incoming = NotificationModel.fromJson(row);
        if (incoming.id.isEmpty || controller.isClosed) return;
        controller.add(incoming);
      },
    );
    channel.subscribe();
    ref.onDispose(() => unawaited(api.removeChannel(channel)));

    return controller.stream;
  },
  name: 'notificationEvents',
);
