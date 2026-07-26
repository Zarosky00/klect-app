import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import 'pulse_entry_view.dart';

/// The Pulse stream's paging state.
@immutable
class PulseFeedState {
  /// Creates a stream state.
  const PulseFeedState({
    this.items = const <PulseItem>[],
    this.loading = false,
    this.loadingMore = false,
    this.refreshing = false,
    this.hasMore = true,
    this.error,
  });

  /// Normalised rows, newest first.
  final List<PulseItem> items;

  /// First page in flight with nothing on screen.
  final bool loading;

  /// A later page is in flight.
  final bool loadingMore;

  /// Pull-to-refresh over existing content.
  final bool refreshing;

  /// Whether the last page came back full.
  final bool hasMore;

  /// The last failure.
  final KlectError? error;

  /// Nothing to show and nothing on the way.
  bool get isEmpty => items.isEmpty && !loading;

  /// Copy with overrides.
  PulseFeedState copyWith({
    List<PulseItem>? items,
    bool? loading,
    bool? loadingMore,
    bool? refreshing,
    bool? hasMore,
    KlectError? error,
    bool clearError = false,
  }) =>
      PulseFeedState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        refreshing: refreshing ?? this.refreshing,
        hasMore: hasMore ?? this.hasMore,
        error: clearError ? null : (error ?? this.error),
      );
}

/// **Pulse** — the X-style stream, paged on the `created_at` cursor.
///
/// `pulse_feed(p_limit, p_before)` is a cursor feed, not an offset feed, so
/// pagination is immune to new posts arriving while you read: we simply ask
/// for everything older than the oldest row on screen.
class PulseFeedController extends Notifier<PulseFeedState> {
  /// Rows per page.
  static const int pageSize = 25;

  final Set<String> _seen = <String>{};
  bool _busy = false;

  @override
  PulseFeedState build() {
    unawaited(Future<void>.microtask(loadInitial));
    return const PulseFeedState(loading: true);
  }

  /// Loads the first page unless one is already there.
  Future<void> loadInitial() async {
    if (_busy || state.items.isNotEmpty) return;
    await _load(reset: true);
  }

  /// Reloads from the top.
  Future<void> refresh() => _load(reset: true);

  /// Appends everything older than the oldest row on screen.
  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.items.isEmpty) return;
    await _load(reset: false);
  }

  /// Retries whatever failed last.
  Future<void> retry() => _load(reset: state.items.isEmpty);

  Future<void> _load({required bool reset}) async {
    if (_busy) return;
    _busy = true;

    final hadItems = state.items.isNotEmpty;
    state = reset
        ? state.copyWith(
            loading: !hadItems,
            refreshing: hadItems,
            clearError: true,
          )
        : state.copyWith(loadingMore: true, clearError: true);

    final before = reset ? null : state.items.last.sortAt;

    try {
      final rows = await ref.read(klectApiProvider).pulseFeed(
            limit: pageSize,
            before: before,
          );

      if (reset) _seen.clear();
      final fresh = <PulseItem>[];
      for (final row in rows) {
        final item = PulseItem.fromEntry(row);
        if (_seen.add(item.key)) fresh.add(item);
      }

      // Seed the optimistic engine before a single pill is built, so nothing
      // ever flashes a zero it is about to replace.
      final store = ref.read(interactionSeedStoreProvider);
      for (final item in fresh) {
        store.put(item.entity, item.seed);
      }
      if (reset && hadItems) {
        // A refresh has to beat controllers that already exist.
        for (final item in fresh) {
          ref.read(interactionProvider(item.entity).notifier).hydrate(item.seed);
        }
      }

      state = PulseFeedState(
        items: reset ? fresh : <PulseItem>[...state.items, ...fresh],
        hasMore: rows.length >= pageSize,
      );
    } on KlectError catch (error) {
      state = state.copyWith(
        loading: false,
        loadingMore: false,
        refreshing: false,
        error: error,
      );
    } finally {
      _busy = false;
    }
  }
}

/// The Pulse stream.
final pulseFeedProvider =
    NotifierProvider<PulseFeedController, PulseFeedState>(
  PulseFeedController.new,
  name: 'pulseFeed',
);
