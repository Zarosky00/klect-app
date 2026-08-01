import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/models/models.dart';
import '../../../router.dart';
import '../chat_api.dart';
import 'call_availability.dart';
import 'call_controller.dart';
import 'call_notification_message.dart';
import 'incoming_call_controller.dart';

/// Versioned bridge between Core-Telecom/CallStyle and authoritative call RPCs.
class AndroidCallBridge with WidgetsBindingObserver {
  /// Creates the bridge.
  AndroidCallBridge(this._ref);

  static const MethodChannel _channel = MethodChannel('com.klect.klect/calls');
  final Ref _ref;
  final Set<String> _handled = <String>{};
  bool _started = false;

  /// True only for the native Android implementation.
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Starts native action recovery once per process.
  void ensureStarted() {
    if (!supported || _started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'callAction') await _ingest(call.arguments);
    });
    unawaited(_drain());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_drain());
  }

  /// Registers the call with Telecom and posts its required CallStyle surface.
  Future<void> present(
    CallModel call, {
    required bool incoming,
    String? peerName,
  }) async {
    ensureStarted();
    if (!supported) return;
    await _channel.invokeMethod<void>('presentCall', <String, Object?>{
      'callId': call.id,
      'conversationId': call.conversationId,
      'peerName': peerName ?? 'KLECT call',
      'kind': call.kind.wire,
      'incoming': incoming,
      'expiresAt': call.expiresAt?.toUtc().toIso8601String(),
    });
  }

  /// Keeps the platform call and notification in step with Flutter media.
  Future<void> setState(String callId, String state) async {
    ensureStarted();
    if (!supported) return;
    await _channel.invokeMethod<void>('setCallState', <String, Object?>{
      'callId': callId,
      'state': state,
    });
  }

  Future<void> _drain() async {
    if (!supported) return;
    final queued = await _channel.invokeListMethod<Object?>('drainActions');
    for (final action in queued ?? const <Object?>[]) {
      await _ingest(action);
    }
  }

  Future<void> _ingest(Object? raw) async {
    if (raw is! Map) return;
    final action = raw['action']?.toString();
    final callId = raw['callId']?.toString();
    final eventId = raw['eventId']?.toString();
    if (action == null || callId == null || callId.isEmpty) return;
    final key = eventId?.isNotEmpty == true ? eventId! : '$action:$callId';
    if (!_handled.add(key)) return;

    try {
      final call = await _ref.read(chatApiProvider).fetchCall(callId);
      switch (action) {
        case 'answer':
          await _answer(callId, call);
        case 'decline':
          if (call?.status == CallStatus.ringing) {
            await _ref.read(chatApiProvider).declineCall(callId);
          }
          await setState(callId, 'ended');
        case 'hangup':
          final active = _ref.read(activeCallProvider);
          if (active.call?.id == callId && active.isBusy) {
            await _ref.read(activeCallProvider.notifier).hangUp();
          } else if (call?.status.isLive ?? false) {
            await _ref
                .read(chatApiProvider)
                .updateCallStatus(callId, CallStatus.ended);
          }
          await setState(callId, 'ended');
        case 'busy':
          if (call?.status == CallStatus.ringing) {
            await _ref
                .read(chatApiProvider)
                .declineCall(callId, reason: 'busy');
          }
          await setState(callId, 'ended');
        case 'stale':
          await setState(callId, 'ended');
      }
      if (eventId?.isNotEmpty == true) {
        await _channel.invokeMethod<void>('ackAction', <String, Object?>{
          'eventId': eventId,
        });
      }
    } catch (_) {
      _handled.remove(key);
      _ref
          .read(callNotificationMessageProvider.notifier)
          .publish('That call action could not be completed.');
    }
  }

  Future<void> _answer(String callId, CallModel? call) async {
    if (call == null || call.status != CallStatus.ringing) {
      await setState(callId, 'ended');
      _ref
          .read(callNotificationMessageProvider.notifier)
          .publish('That call is no longer ringing.');
      return;
    }
    await _ref.read(callAvailabilityProvider.notifier).refreshIfStale();
    if (!_ref.read(callAvailabilityProvider)) {
      await setState(callId, 'ended');
      return;
    }
    final active = _ref.read(activeCallProvider);
    if (active.isBusy && active.call?.id != callId) {
      await _ref.read(chatApiProvider).declineCall(callId, reason: 'busy');
      await setState(callId, 'ended');
      return;
    }

    final microphone = await Permission.microphone.request();
    final camera = call.kind == CallKind.video
        ? await Permission.camera.request()
        : PermissionStatus.granted;
    if (!microphone.isGranted || !camera.isGranted) {
      await _ref
          .read(chatApiProvider)
          .declineCall(callId, reason: 'permission_denied');
      await setState(callId, 'ended');
      _ref
          .read(callNotificationMessageProvider.notifier)
          .publish('Microphone and camera permission are needed for calls.');
      return;
    }

    final controller = _ref.read(activeCallProvider.notifier);
    if (active.call?.id != callId) await controller.present(call);
    await controller.accept();
    _ref.read(incomingCallProvider.notifier).clear();
    await setState(callId, 'connecting');
    unawaited(_ref.read(routerProvider).push('/call/$callId'));
  }

  /// Releases platform listeners with the provider.
  void dispose() {
    if (!_started) return;
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    _started = false;
  }
}

/// Session-wide Core-Telecom bridge.
final androidCallBridgeProvider = Provider<AndroidCallBridge>((ref) {
  final bridge = AndroidCallBridge(ref)..ensureStarted();
  ref.onDispose(bridge.dispose);
  return bridge;
}, name: 'androidCallBridge');
