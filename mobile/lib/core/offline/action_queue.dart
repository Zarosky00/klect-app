import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../api/api_error.dart';
import '../api/klect_api.dart';
import '../models/models.dart';
import '../storage/key_value_store.dart';
import 'queued_action.dart';

/// A durable queue of social actions taken while offline.
///
/// Contract:
///  * the UI applies its optimistic delta and **keeps** it — the user's intent
///    stays on screen;
///  * the intent is written to disk immediately, so a cold start does not lose
///    it;
///  * on replay we read the current server state and only fire the RPC when it
///    differs, so a replay can never double-toggle or duplicate a row;
///  * a permanent failure (`42501`, suspended) drops the action instead of
///    retrying forever.
///
/// The retry cadence below is network policy, not motion — it deliberately
/// does not come from the design tokens.
class OfflineActionQueue extends ChangeNotifier {
  /// Creates a queue over an API and a durable store.
  OfflineActionQueue({
    required KlectApi api,
    required KeyValueStore store,
    Uuid uuid = const Uuid(),
  }) // ignore_for_file: prefer_initializing_formals
      : _api = api,
        _store = store,
        _uuid = uuid;

  /// Where the queue is persisted.
  static const String storageKey = 'klect.offline.queue.v1';

  /// How long to wait before the first replay attempt.
  static const Duration retryInterval = Duration(seconds: 15);

  /// The longest we ever wait between replay attempts.
  static const Duration maxRetryInterval = Duration(minutes: 5);

  /// Actions that keep failing with a transport error are eventually dropped
  /// so the queue cannot grow without bound.
  static const int maxAttempts = 12;

  final KlectApi _api;
  final KeyValueStore _store;
  final Uuid _uuid;

  final List<QueuedAction> _pending = <QueuedAction>[];
  Timer? _retryTimer;
  bool _flushing = false;
  bool _loaded = false;

  /// Everything still waiting to reach the server, oldest first.
  List<QueuedAction> get pending => List<QueuedAction>.unmodifiable(_pending);

  /// How many intents are queued. Chrome can surface this as "syncing…".
  int get length => _pending.length;

  /// True when there is nothing left to replay.
  bool get isEmpty => _pending.isEmpty;

  /// Restores the queue from disk. Safe to call more than once.
  Future<void> restore() async {
    if (_loaded) return;
    _loaded = true;
    final raw = _store.getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is Map) _pending.add(QueuedAction.fromJson(asMap(entry)));
        }
      }
    } on FormatException {
      await _store.remove(storageKey);
      return;
    }
    if (_pending.isNotEmpty) {
      notifyListeners();
      _scheduleRetry();
    }
  }

  /// Queues a like/save/repost intent.
  Future<void> enqueueToggle({
    required QueuedActionKind kind,
    required EntityType entityType,
    required String entityId,
    required bool desiredActive,
    String? note,
    String? quote,
  }) =>
      _enqueue(
        QueuedAction(
          id: _uuid.v4(),
          kind: kind,
          targetId: entityId,
          entityType: entityType,
          desiredActive: desiredActive,
          note: note,
          quote: quote,
          createdAt: DateTime.now(),
        ),
      );

  /// Queues a follow/unfollow intent.
  Future<void> enqueueFollow({
    required String userId,
    required bool desiredActive,
  }) =>
      _enqueue(
        QueuedAction(
          id: _uuid.v4(),
          kind: QueuedActionKind.follow,
          targetId: userId,
          desiredActive: desiredActive,
          createdAt: DateTime.now(),
        ),
      );

  /// Queues a view. `record_view` is deduped per viewer per day server-side,
  /// so replaying one late costs nothing.
  Future<void> enqueueView({
    required EntityType entityType,
    required String entityId,
  }) =>
      _enqueue(
        QueuedAction(
          id: _uuid.v4(),
          kind: QueuedActionKind.view,
          targetId: entityId,
          entityType: entityType,
          createdAt: DateTime.now(),
        ),
      );

  Future<void> _enqueue(QueuedAction action) async {
    // Last intent wins: 10 offline taps collapse to one queued row.
    _pending.removeWhere((a) => a.dedupeKey == action.dedupeKey);
    _pending.add(action);
    await _persist();
    notifyListeners();
    _scheduleRetry();
  }

  /// Attempts to drain the queue.
  ///
  /// Stops at the first transport failure — if we are still offline there is no
  /// point burning through the rest — and reschedules itself.
  Future<void> flush() async {
    if (_flushing || _pending.isEmpty) return;
    if (_api.currentUserId == null) return;
    _flushing = true;
    var stillOffline = false;
    try {
      for (final action in List<QueuedAction>.of(_pending)) {
        try {
          await _apply(action);
          _pending.removeWhere((a) => a.id == action.id);
        } on KlectError catch (error) {
          if (error.isRetryable) {
            final retried = action.retried();
            final index = _pending.indexWhere((a) => a.id == action.id);
            if (retried.attempts >= maxAttempts) {
              _pending.removeWhere((a) => a.id == action.id);
            } else if (index >= 0) {
              _pending[index] = retried;
            }
            stillOffline = true;
            break;
          }
          // Permanent: the content went away or we are blocked. Drop it —
          // retrying can only fail again.
          _pending.removeWhere((a) => a.id == action.id);
        }
      }
      await _persist();
      notifyListeners();
    } finally {
      _flushing = false;
    }
    if (_pending.isNotEmpty) {
      _scheduleRetry(backOff: stillOffline);
    }
  }

  Future<void> _apply(QueuedAction action) async {
    switch (action.kind) {
      case QueuedActionKind.like:
        final type = action.entityType ?? EntityType.item;
        if (await _api.hasLiked(type, action.targetId) !=
            action.desiredActive) {
          await _api.toggleLike(type, action.targetId);
        }
      case QueuedActionKind.save:
        final type = action.entityType ?? EntityType.item;
        if (await _api.hasSaved(type, action.targetId) !=
            action.desiredActive) {
          await _api.toggleSave(type, action.targetId, note: action.note);
        }
      case QueuedActionKind.repost:
        final type = action.entityType ?? EntityType.item;
        if (await _api.hasReposted(type, action.targetId) !=
            action.desiredActive) {
          await _api.toggleRepost(type, action.targetId, quote: action.quote);
        }
      case QueuedActionKind.follow:
        if (await _api.hasFollowed(action.targetId) != action.desiredActive) {
          await _api.toggleFollow(action.targetId);
        }
      case QueuedActionKind.view:
        await _api.recordView(
          action.entityType ?? EntityType.item,
          action.targetId,
        );
    }
  }

  void _scheduleRetry({bool backOff = false}) {
    _retryTimer?.cancel();
    if (_pending.isEmpty) return;
    final attempts = _pending
        .map((a) => a.attempts)
        .fold<int>(0, (max, value) => value > max ? value : max);
    final multiplier = backOff ? (1 << attempts.clamp(0, 5)) : 1;
    final delay = Duration(
      milliseconds: (retryInterval.inMilliseconds * multiplier)
          .clamp(retryInterval.inMilliseconds, maxRetryInterval.inMilliseconds),
    );
    _retryTimer = Timer(delay, () {
      unawaited(flush());
    });
  }

  Future<void> _persist() async {
    if (_pending.isEmpty) {
      await _store.remove(storageKey);
      return;
    }
    await _store.setString(
      storageKey,
      jsonEncode(<Map<String, dynamic>>[
        for (final action in _pending) action.toJson(),
      ]),
    );
  }

  /// Drops everything without replaying — used on sign-out so one account's
  /// intents never land on another's session.
  Future<void> clear() async {
    _pending.clear();
    _retryTimer?.cancel();
    await _store.remove(storageKey);
    notifyListeners();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}

/// The app-wide offline queue.
final offlineQueueProvider = Provider<OfflineActionQueue>(
  (ref) {
    final queue = OfflineActionQueue(
      api: ref.watch(klectApiProvider),
      store: ref.watch(keyValueStoreProvider),
    );
    unawaited(queue.restore());
    ref.onDispose(queue.dispose);
    return queue;
  },
  name: 'offlineQueue',
);

/// The queue as a [Listenable], for chrome that wants to show "syncing…".
///
/// [OfflineActionQueue] is a [ChangeNotifier], so wrap the affordance in a
/// `ListenableBuilder` rather than watching a value provider — the count
/// changes outside the Riverpod graph.
final offlineQueueListenableProvider = Provider<Listenable>(
  (ref) => ref.watch(offlineQueueProvider),
  name: 'offlineQueueListenable',
);
