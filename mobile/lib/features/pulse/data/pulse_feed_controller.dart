import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../core/offline/feed_page_cache.dart';
import '../../../core/storage/key_value_store.dart';
import '../../../core/supabase.dart';
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
    this.freshKey,
    this.fromCache = false,
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

  /// Key of a just-composed row, so the screen can slide it in.
  final String? freshKey;

  /// True when [items] were hydrated from the offline first-page cache. The
  /// next retry then reloads from the top instead of paging under stale rows.
  final bool fromCache;

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
    String? freshKey,
    bool clearFresh = false,
    bool? fromCache,
  }) => PulseFeedState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    refreshing: refreshing ?? this.refreshing,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    freshKey: clearFresh ? null : (freshKey ?? this.freshKey),
    fromCache: fromCache ?? this.fromCache,
  );
}

/// **Pulse** — the X-style stream, one controller per [PulseMode].
///
/// `pulse_feed(p_limit, p_before, p_mode, p_before_id)` is a cursor feed,
/// not an offset feed, so pagination is immune to new posts arriving while
/// you read. The 0021 contract:
///
///  * the RPC returns **up to `p_limit + 1` rows** — the extra row is the
///    has-more signal, not content, so only the first `p_limit` render;
///  * paging is a composite keyset: the oldest on-screen row's
///    `(sort_at, cursor_id)` goes back as `(p_before, p_before_id)`, which
///    is what stops a same-timestamp twin being skipped at a page boundary.
///
/// Both modes page on **min(sort_at) currently on screen**: Following is
/// chronological so that is simply the last row, and For-you is
/// score-ordered so the minimum must be taken across the whole page.
class PulseFeedController extends Notifier<PulseFeedState> {
  /// Creates the controller for one feed mode.
  PulseFeedController(this.mode);

  /// Which half of the stream this controller owns.
  final PulseMode mode;

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

  /// Retries whatever failed last. A stream hydrated from the offline cache
  /// retries from the top — its rows are a stale snapshot, not a live cursor.
  Future<void> retry() => _load(reset: state.items.isEmpty || state.fromCache);

  /// Puts a just-composed post at the top of the stream.
  ///
  /// `create_post` returns the full envelope, so nothing needs refetching:
  /// the row is seeded into the optimistic engine and marked fresh so the
  /// screen can slide it in.
  void prepend(PulseEntry entry) {
    final item = PulseItem.fromEntry(entry);
    if (!_seen.add(item.key)) return;
    ref.read(interactionSeedStoreProvider).put(item.entity, item.seed);
    state = state.copyWith(
      items: <PulseItem>[item, ...state.items],
      freshKey: item.key,
    );
  }

  /// The next `(p_before, p_before_id)`: the row with the minimum `sort_at`
  /// currently on screen and its `cursor_id`. For-you pages are
  /// score-ordered, so the last row is not necessarily the oldest.
  PulseItem? _oldestOnScreen() {
    PulseItem? oldest;
    for (final item in state.items) {
      final at = item.sortAt;
      if (at == null) continue;
      final oldestAt = oldest?.sortAt;
      if (oldestAt == null || at.isBefore(oldestAt)) oldest = item;
    }
    return oldest;
  }

  Future<void> _load({required bool reset}) async {
    if (_busy) return;
    _busy = true;

    final hadItems = state.items.isNotEmpty;
    state = reset
        ? state.copyWith(
            loading: !hadItems,
            refreshing: hadItems,
            clearError: true,
            clearFresh: true,
          )
        : state.copyWith(loadingMore: true, clearError: true, clearFresh: true);

    final cursor = reset ? null : _oldestOnScreen();

    try {
      final rows = await ref
          .read(klectApiProvider)
          .pulseFeed(
            limit: pageSize,
            before: cursor?.sortAt,
            beforeId: cursor?.cursorId,
            mode: mode,
          );

      // 0021 extra-row contract: up to pageSize + 1 rows come back; the
      // extra one only says "there is more" and must not render (it would
      // duplicate the top of the next page).
      final hasMore = rows.length > pageSize;
      final pageRows = hasMore ? rows.sublist(0, pageSize) : rows;

      if (reset) _seen.clear();
      final fresh = <PulseItem>[];
      for (final row in pageRows) {
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
          ref
              .read(interactionProvider(item.entity).notifier)
              .hydrate(item.seed);
        }
      }

      state = PulseFeedState(
        items: reset ? fresh : <PulseItem>[...state.items, ...fresh],
        hasMore: hasMore,
      );

      if (reset && fresh.isNotEmpty) {
        // Persist the first page so an offline cold start still has a Pulse.
        unawaited(
          ref.read(feedPageCacheProvider).write(
            _cacheKey,
            <Map<String, dynamic>>[for (final item in fresh) item.source.raw],
          ),
        );
      }
    } on KlectError catch (error) {
      if (state.items.isEmpty &&
          error.isRetryable &&
          _hydrateFromCache(error)) {
        return;
      }
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

  /// Offline cache key — per user and per mode.
  String get _cacheKey {
    final userId = ref.read(currentUserIdProvider) ?? 'anon';
    return 'pulse.${mode.wire}.$userId';
  }

  /// Replaces the empty error state with the cached first page, keeping the
  /// error so the footer says why. Returns false when nothing is cached.
  bool _hydrateFromCache(KlectError error) {
    final rows = ref.read(feedPageCacheProvider).read(_cacheKey);
    if (rows == null) return false;

    _seen.clear();
    final items = <PulseItem>[];
    for (final row in rows) {
      final item = PulseItem.fromEntry(PulseEntry.fromJson(row));
      if (_seen.add(item.key)) items.add(item);
    }
    if (items.isEmpty) return false;

    final store = ref.read(interactionSeedStoreProvider);
    for (final item in items) {
      store.put(item.entity, item.seed);
    }
    state = PulseFeedState(
      items: items,
      // The cache holds exactly one page; paging past it needs the network.
      hasMore: false,
      error: error,
      fromCache: true,
    );
    return true;
  }
}

/// The Pulse stream, one instance per tab.
final pulseFeedProvider =
    NotifierProvider.family<PulseFeedController, PulseFeedState, PulseMode>(
      PulseFeedController.new,
      name: 'pulseFeed',
    );

/// Which Pulse tab is on screen. Lives outside the screen so the composer can
/// prepend into the feed the user is actually looking at.
class PulseModeController extends Notifier<PulseMode> {
  static const String _storageKey = 'klect.pulse.mode';

  @override
  PulseMode build() {
    final saved = ref.read(keyValueStoreProvider).getString(_storageKey);
    return PulseMode.values.firstWhere(
      (mode) => mode.wire == saved,
      orElse: () => PulseMode.foryou,
    );
  }

  /// Switches tab.
  void select(PulseMode mode) {
    state = mode;
    unawaited(
      ref.read(keyValueStoreProvider).setString(_storageKey, mode.wire),
    );
  }
}

/// The active Pulse tab.
final pulseModeProvider = NotifierProvider<PulseModeController, PulseMode>(
  PulseModeController.new,
  name: 'pulseMode',
);
