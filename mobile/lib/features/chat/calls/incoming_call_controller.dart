import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/api/api_error.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../chat_api.dart';
import 'call_controller.dart';

/// Watches for calls ringing *at* the viewer.
///
/// RLS on `calls` already limits the stream to conversations the viewer is a
/// member of, so the only extra test is "somebody else started it". A cold
/// start also sweeps the table once, because Realtime can only deliver what
/// arrives after the subscription — a call that started while the app was
/// backgrounded would otherwise be invisible.
class IncomingCallController extends Notifier<CallModel?> {
  RealtimeChannel? _channel;
  bool _disposed = false;

  ChatApi get _api => ref.read(chatApiProvider);

  @override
  CallModel? build() {
    // Cleared on every rebuild: the previous run's `onDispose` has already
    // fired, and a stale `true` here would silence every incoming call.
    _disposed = false;
    final userId = ref.watch(currentUserIdProvider);
    ref.onDispose(_teardown);
    if (userId == null) return null;

    _channel = _api.callsChannel(onInsert: _onInsert, onUpdate: _onUpdate)
      ..subscribe();
    unawaited(_sweep());
    return null;
  }

  void _teardown() {
    _disposed = true;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_api.removeChannel(channel));
  }

  Future<void> _sweep() async {
    try {
      final ringing = await _api.fetchRingingCalls();
      if (_disposed || ringing.isEmpty) return;
      _offer(ringing.first);
    } on KlectError {
      // Nothing ringing that we can see.
    }
  }

  void _onInsert(Map<String, dynamic> row) {
    final call = CallModel.fromJson(row);
    if (call.status != CallStatus.ringing) return;
    if (call.createdBy == ref.read(currentUserIdProvider)) return;
    _offer(call);
  }

  void _onUpdate(Map<String, dynamic> row) {
    final call = CallModel.fromJson(row);
    if (state?.id != call.id) return;
    if (!call.status.isLive) state = null;
  }

  void _offer(CallModel call) {
    if (_disposed) return;
    // A call already on screen wins; we never stack two ring UIs.
    if (ref.read(activeCallProvider).isBusy) return;
    if (state != null) return;
    state = call;
    unawaited(ref.read(activeCallProvider.notifier).present(call));
  }

  /// Clears the banner once the user has accepted, declined, or the call died.
  void clear() => state = null;
}

/// The call ringing at the viewer right now, or null.
final incomingCallProvider =
    NotifierProvider<IncomingCallController, CallModel?>(
  IncomingCallController.new,
  name: 'incomingCall',
);
