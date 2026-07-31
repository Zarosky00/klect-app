import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../router.dart';
import '../../notifications/notification_surfaces.dart';
import '../chat_api.dart';
import 'call_controller.dart';

/// One message emitted by a guarded notification action.
class CallNotificationMessage extends Notifier<String?> {
  @override
  String? build() => null;

  /// Publishes one message for the overlay host to surface.
  void publish(String message) => state = message;

  /// Clears a message after it has been shown once.
  void clear() => state = null;
}

/// Messages raised by notification actions, consumed once by CallOverlayHost.
final callNotificationMessageProvider =
    NotifierProvider<CallNotificationMessage, String?>(
      CallNotificationMessage.new,
      name: 'callNotificationMessage',
    );

/// Owns the high-priority incoming-call system notification and its guarded
/// Accept/Decline actions.
class CallNotifications with WidgetsBindingObserver {
  /// Creates the service.
  CallNotifications(this._ref);

  final Ref _ref;
  StreamSubscription<dynamic>? _actions;
  AppLifecycleState _lifecycle =
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  final Set<String> _shown = <String>{};

  /// Starts action handling and lifecycle tracking once.
  void ensureStarted() {
    if (_actions != null) return;
    WidgetsBinding.instance.addObserver(this);
    _actions = _ref.read(localNotificationsProvider).actions.listen((event) {
      unawaited(_handleAction(event.id, event.payload));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  /// Shows a full-screen-intent notification only while the app is not active.
  Future<void> presentIfBackgrounded(
    CallModel call, {
    String? callerName,
  }) async {
    ensureStarted();
    if (_lifecycle == AppLifecycleState.resumed || !_shown.add(call.id)) return;
    await _ref
        .read(localNotificationsProvider)
        .showIncomingCall(
          id: _notificationId(call.id),
          callId: call.id,
          callerName: callerName ?? 'Incoming call',
          isVideo: call.kind == CallKind.video,
        );
  }

  /// Cancels the system surface as soon as the row is no longer ringing.
  Future<void> cancelCall(String callId) async {
    _shown.remove(callId);
    await _ref.read(localNotificationsProvider).cancel(_notificationId(callId));
  }

  Future<void> _handleAction(String actionId, String? callId) async {
    if (callId == null || callId.isEmpty) return;
    await cancelCall(callId);

    try {
      final call = await _ref
          .read(chatApiProvider)
          .fetchCall(callId)
          .timeout(const Duration(seconds: 10));
      final held = _ref.read(activeCallProvider);
      if (call == null || call.status != CallStatus.ringing) {
        _message('That call is no longer ringing.');
        return;
      }
      if (held.isBusy && held.call?.id != callId) {
        _message('Finish your current call before answering another one.');
        return;
      }

      switch (actionId) {
        case 'call_accept':
          final controller = _ref.read(activeCallProvider.notifier);
          if (held.call?.id != callId) await controller.present(call);
          await controller.accept().timeout(const Duration(seconds: 10));
          await _ref.read(routerProvider).push('/call/$callId');
          return;
        case 'call_decline':
          await _ref
              .read(chatApiProvider)
              .declineCall(callId)
              .timeout(const Duration(seconds: 10));
          return;
        default:
          return;
      }
    } on TimeoutException {
      _message('The call action timed out. Try from the app.');
    } catch (_) {
      _message('The call action could not be completed.');
    }
  }

  void _message(String message) =>
      _ref.read(callNotificationMessageProvider.notifier).publish(message);

  /// Stops listeners when the provider is disposed.
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_actions?.cancel());
    _actions = null;
  }

  static int _notificationId(String callId) => callId.hashCode & 0x7fffffff;
}

/// Session service for incoming-call system notifications.
final callNotificationsProvider = Provider<CallNotifications>((ref) {
  final service = CallNotifications(ref);
  ref.onDispose(service.dispose);
  return service;
}, name: 'callNotifications');
