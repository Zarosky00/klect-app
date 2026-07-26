import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../pulse/data/pulse_entry_view.dart';

/// The profile Posts tab's paging state.
@immutable
class UserPostsState {
  /// Creates a state.
  const UserPostsState({
    this.items = const <PulseItem>[],
    this.loading = true,
    this.loadingMore = false,
    this.hasMore = false,
    this.error,
  });

  /// Normalised rows, newest first — the same shape a Pulse row renders.
  final List<PulseItem> items;

  /// First page in flight.
  final bool loading;

  /// A later page in flight.
  final bool loadingMore;

  /// Whether the server said another page exists.
  final bool hasMore;

  /// The last failure.
  final KlectError? error;

  /// Copy with overrides.
  UserPostsState copyWith({
    List<PulseItem>? items,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    KlectError? error,
    bool clearError = false,
  }) =>
      UserPostsState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// The profile Posts tab — `user_posts` (0021): one account's posts, quotes
/// and entity reposts as pulse envelopes, parsed by the exact same adapter
/// the stream uses ([PulseItem.fromEntry]).
///
/// Same extra-row has-more contract as `pulse_feed`: up to `p_limit + 1`
/// rows come back and only `p_limit` render. The RPC keysets on `p_before`
/// alone (its signature carries no `p_before_id`), so paging passes the
/// minimum `sort_at` on screen per its header contract.
class UserPostsController extends Notifier<UserPostsState> {
  /// Creates the controller for one account.
  UserPostsController(this.userId);

  /// Whose posts these are.
  final String userId;

  /// Rows per page.
  static const int pageSize = 25;

  final Set<String> _seen = <String>{};
  bool _disposed = false;
  bool _busy = false;

  @override
  UserPostsState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    unawaited(Future<void>.microtask(load));
    return const UserPostsState();
  }

  /// Loads the first page.
  Future<void> load() => _load(reset: true);

  /// Reloads from the top.
  Future<void> refresh() => _load(reset: true);

  /// Appends everything older than the oldest row on screen.
  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.items.isEmpty) return;
    await _load(reset: false);
  }

  DateTime? _oldestOnScreen() {
    DateTime? oldest;
    for (final item in state.items) {
      final at = item.sortAt;
      if (at == null) continue;
      if (oldest == null || at.isBefore(oldest)) oldest = at;
    }
    return oldest;
  }

  Future<void> _load({required bool reset}) async {
    if (_disposed || _busy) return;
    _busy = true;
    state = reset
        ? state.copyWith(loading: state.items.isEmpty, clearError: true)
        : state.copyWith(loadingMore: true, clearError: true);

    try {
      final rows = await ref.read(klectApiProvider).userPosts(
            userId,
            limit: pageSize,
            before: reset ? null : _oldestOnScreen(),
          );
      if (_disposed) return;

      // Extra-row contract: the (pageSize + 1)th row is the has-more signal.
      final hasMore = rows.length > pageSize;
      final pageRows = hasMore ? rows.sublist(0, pageSize) : rows;

      if (reset) _seen.clear();
      final fresh = <PulseItem>[];
      for (final row in pageRows) {
        final item = PulseItem.fromEntry(row);
        if (_seen.add(item.key)) fresh.add(item);
      }

      final store = ref.read(interactionSeedStoreProvider);
      for (final item in fresh) {
        store.put(item.entity, item.seed);
      }

      state = UserPostsState(
        items: reset ? fresh : <PulseItem>[...state.items, ...fresh],
        loading: false,
        hasMore: hasMore,
      );
    } on KlectError catch (error) {
      if (_disposed) return;
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        error: error,
      );
    } finally {
      _busy = false;
    }
  }
}

/// One account's Posts tab, keyed by user id.
final userPostsProvider = NotifierProvider.autoDispose
    .family<UserPostsController, UserPostsState, String>(
  UserPostsController.new,
  name: 'userPosts',
);
