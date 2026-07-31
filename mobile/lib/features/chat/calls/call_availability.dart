import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase.dart';
import '../chat_api.dart';

/// Whether calling is available to this session, read from the server.
///
/// The flag lives in `feature_flags.reliable_calls` and is exposed by the
/// `call_feature_enabled` RPC, so an operator can turn calling on without
/// shipping a build (Requirement 10.6). Three rules make it safe:
///
/// - **session-scoped, not per-screen.** One read drives every affordance and
///   every `start_call` attempt, so two surfaces can never disagree;
/// - **the last successful read wins.** A read that fails or takes longer than
///   [readTimeout] resolves to `false` and surfaces nothing to the user — a
///   flaky network must never present a call surface that cannot work
///   (Requirement 10.7);
/// - **fresh enough, not chatty.** Coming back to the foreground re-reads only
///   when the previous success is at least [staleAfter] old.
class CallAvailability extends Notifier<bool> {
  /// How long a single read may take before it is treated as disabled.
  static const Duration readTimeout = Duration(seconds: 10);

  /// How old a successful read must be before a foreground re-read happens.
  static const Duration staleAfter = Duration(minutes: 5);

  /// The clock staleness is measured against. Overridable in tests.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  DateTime? _lastSuccessAt;
  Future<void>? _inFlight;
  bool _disposed = false;

  /// When the most recent *successful* read landed, or null — never read
  /// successfully, or the last attempt failed.
  DateTime? get lastSuccessAt => _lastSuccessAt;

  @override
  bool build() {
    // A rebuild is a new session: the previous verdict says nothing about the
    // account that just signed in.
    _disposed = false;
    _lastSuccessAt = null;
    _inFlight = null;
    ref.onDispose(() => _disposed = true);
    final userId = ref.watch(currentUserIdProvider);
    // Signed out: there is nobody to call and no RPC to ask.
    if (userId == null) return false;
    unawaited(_read());
    return false;
  }

  /// Re-reads the flag when the previous success is at least [staleAfter] old.
  ///
  /// Called when the app returns to the foreground. A read that has never
  /// succeeded is always stale, so a failed session start heals on the next
  /// foreground rather than staying disabled for five minutes.
  Future<void> refreshIfStale() {
    if (_disposed) return Future<void>.value();
    if (ref.read(currentUserIdProvider) == null) return Future<void>.value();
    final last = _lastSuccessAt;
    if (last != null && clock().difference(last) < staleAfter) {
      return Future<void>.value();
    }
    return _read();
  }

  /// Joins the read already running rather than stacking a second one.
  Future<void> _read() => _inFlight ??= _perform();

  Future<void> _perform() async {
    try {
      final enabled = await ref
          .read(chatApiProvider)
          .callFeatureEnabled()
          .timeout(readTimeout);
      if (_disposed) return;
      _lastSuccessAt = clock();
      state = enabled;
    } on Object {
      // Requirement 10.7: fail closed, say nothing. Clearing the success stamp
      // is deliberate — "disabled until the next successful read" means the
      // next foreground must try again instead of trusting a stale success.
      if (_disposed) return;
      _lastSuccessAt = null;
      state = false;
    } finally {
      _inFlight = null;
    }
  }
}

/// Whether this session may place or receive calls.
///
/// Deliberately **not** `autoDispose`: the verdict outlives any one thread so
/// that opening a conversation does not re-read the flag, and so that every
/// call affordance in the app answers the same question the same way.
final callAvailabilityProvider = NotifierProvider<CallAvailability, bool>(
  CallAvailability.new,
  name: 'callAvailability',
);
