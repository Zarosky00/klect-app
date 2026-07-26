import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../core/offline/feed_page_cache.dart';
import '../../../core/supabase.dart';

/// Everything the Surf grid needs to render one filter's infinite feed.
///
/// [cards] is append-only within a seed: `surf_feed` is deterministic for a
/// given `p_seed`, so paging by offset can never duplicate or skip a tile. The
/// controller still de-duplicates by [SurfCard.key] as a belt-and-braces guard
/// against a mid-scroll insert changing the ranking underneath us.
@immutable
class SurfFeedState {
  /// Creates a feed state.
  const SurfFeedState({
    required this.filter,
    this.cards = const <SurfCard>[],
    this.aspects = const <double>[],
    this.seed = '',
    this.loading = false,
    this.loadingMore = false,
    this.refreshing = false,
    this.hasMore = true,
    this.error,
    this.pageAnchor = 0,
    this.fromCache = false,
  });

  /// Which filter chip this feed belongs to.
  final SurfFilter filter;

  /// The tiles, in ranking order.
  final List<SurfCard> cards;

  /// `cards[i].tileAspect`, precomputed once so the masonry delegate never
  /// walks the model list during layout.
  final List<double> aspects;

  /// The stable `p_seed` currently paginating.
  final String seed;

  /// First page in flight and nothing on screen yet.
  final bool loading;

  /// A later page is in flight.
  final bool loadingMore;

  /// A pull-to-refresh is in flight over existing content.
  final bool refreshing;

  /// Whether the last page came back full, i.e. there is probably more.
  final bool hasMore;

  /// The last failure. Cards stay on screen when a *later* page fails.
  final KlectError? error;

  /// Index of the first card of the most recently appended page — the
  /// entrance animation staggers from here so tiles built during a fling do
  /// not animate.
  final int pageAnchor;

  /// True when [cards] were hydrated from the offline first-page cache. The
  /// next retry then reloads from the top instead of paging under stale rows.
  final bool fromCache;

  /// True when there is nothing to show and nothing on the way.
  bool get isEmpty => cards.isEmpty && !loading;

  /// Copy with overrides. [clearError] wins over [error].
  SurfFeedState copyWith({
    List<SurfCard>? cards,
    List<double>? aspects,
    String? seed,
    bool? loading,
    bool? loadingMore,
    bool? refreshing,
    bool? hasMore,
    KlectError? error,
    bool clearError = false,
    int? pageAnchor,
    bool? fromCache,
  }) => SurfFeedState(
    filter: filter,
    cards: cards ?? this.cards,
    aspects: aspects ?? this.aspects,
    seed: seed ?? this.seed,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    refreshing: refreshing ?? this.refreshing,
    hasMore: hasMore ?? this.hasMore,
    error: clearError ? null : (error ?? this.error),
    pageAnchor: pageAnchor ?? this.pageAnchor,
    fromCache: fromCache ?? this.fromCache,
  );
}

/// The Surf feed, one instance per [SurfFilter].
///
/// Keeping one controller per filter means switching chips is instant and
/// returns you to the page you had already paid for, instead of refetching.
class SurfFeedController extends Notifier<SurfFeedState> {
  /// Creates a controller for one filter.
  SurfFeedController(this.filter);

  /// The filter this feed serves.
  final SurfFilter filter;

  /// Rows per `surf_feed` call. Two phone columns of ~15 tiles.
  static const int pageSize = 30;

  final Set<String> _seen = <String>{};
  int _offset = 0;
  int _nonce = 0;
  bool _busy = false;

  @override
  SurfFeedState build() {
    // The provider is self-starting: a screen only has to `watch` it. The
    // first fetch is deferred to a microtask because `build()` may not emit.
    unawaited(Future<void>.microtask(loadInitial));
    return SurfFeedState(filter: filter, loading: true);
  }

  /// A per-user, per-day seed so two accounts never see the same order while
  /// one account's pagination stays stable across pages.
  ///
  /// Pull-to-refresh bumps a nonce, which is what makes a refresh *reshuffle*
  /// rather than return the same grid.
  String _buildSeed() {
    final userId = ref.read(currentUserIdProvider) ?? 'anon';
    final now = DateTime.now();
    final day = '${now.year}-${now.month}-${now.day}';
    return _nonce == 0 ? '$userId:$day' : '$userId:$day:$_nonce';
  }

  /// Offline cache key — per user and per filter, so accounts never see each
  /// other's cached grid.
  String get _cacheKey {
    final userId = ref.read(currentUserIdProvider) ?? 'anon';
    return 'surf.${filter.wire}.$userId';
  }

  /// Loads the first page, unless one is already loaded or in flight.
  Future<void> loadInitial() async {
    if (_busy || state.cards.isNotEmpty) return;
    await _load(reset: true);
  }

  /// Reseeds and reloads from the top.
  Future<void> refresh() async {
    _nonce++;
    await _load(reset: true);
  }

  /// Appends the next page. Cheap to call on every scroll frame — it returns
  /// immediately while a page is in flight or the feed is exhausted.
  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.cards.isEmpty) return;
    await _load(reset: false);
  }

  /// Retries whatever failed last. A grid hydrated from the offline cache
  /// retries from the top — its rows are a stale snapshot, not page one of a
  /// live seed.
  Future<void> retry() => state.cards.isEmpty || state.fromCache
      ? _load(reset: true)
      : _load(reset: false);

  Future<void> _load({required bool reset}) async {
    if (_busy) return;
    _busy = true;

    final hadCards = state.cards.isNotEmpty;
    if (reset) {
      _offset = 0;
      state = state.copyWith(
        loading: !hadCards,
        refreshing: hadCards,
        clearError: true,
      );
    } else {
      state = state.copyWith(loadingMore: true, clearError: true);
    }

    final seed = reset ? _buildSeed() : state.seed;

    try {
      final rows = await ref
          .read(klectApiProvider)
          .surfFeed(
            limit: pageSize,
            offset: _offset,
            seed: seed,
            filter: filter,
          );

      // Advance by what the server returned, not by what we kept, or dropping
      // a duplicate would silently skip a row on the next page.
      _offset += rows.length;

      if (reset) _seen.clear();
      final fresh = <SurfCard>[
        for (final card in rows)
          if (_seen.add(card.key)) card,
      ];

      ref.read(interactionSeedStoreProvider).putCards(fresh);
      if (reset && hadCards) {
        // A refresh must beat any controller that already exists, otherwise
        // stale counts survive the reseed. Seeding alone only helps notifiers
        // that have not been built yet.
        for (final card in fresh) {
          ref
              .read(interactionProvider(EntityRef.ofCard(card)).notifier)
              .hydrateFromCard(card);
        }
      }

      final cards = reset ? fresh : <SurfCard>[...state.cards, ...fresh];
      state = SurfFeedState(
        filter: filter,
        cards: cards,
        aspects: <double>[for (final card in cards) card.tileAspect],
        seed: seed,
        hasMore: rows.length >= pageSize,
        pageAnchor: reset ? 0 : cards.length - fresh.length,
      );

      if (reset && fresh.isNotEmpty) {
        // Persist the first page so the next offline cold start still surfs.
        unawaited(
          ref.read(feedPageCacheProvider).write(
            _cacheKey,
            <Map<String, dynamic>>[for (final card in fresh) card.raw],
          ),
        );
      }
    } on KlectError catch (error) {
      if (state.cards.isEmpty &&
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

  /// Replaces the empty error state with the cached first page, keeping the
  /// error so the footer says why the grid might look familiar. Returns false
  /// when there is nothing cached.
  bool _hydrateFromCache(KlectError error) {
    final rows = ref.read(feedPageCacheProvider).read(_cacheKey);
    if (rows == null) return false;

    _seen.clear();
    final cards = <SurfCard>[];
    for (final row in rows) {
      final card = SurfCard.fromJson(row);
      if (_seen.add(card.key)) cards.add(card);
    }
    if (cards.isEmpty) return false;

    ref.read(interactionSeedStoreProvider).putCards(cards);
    state = SurfFeedState(
      filter: filter,
      cards: cards,
      aspects: <double>[for (final card in cards) card.tileAspect],
      seed: state.seed,
      // The cache holds exactly one page; paging past it needs the network.
      hasMore: false,
      error: error,
      fromCache: true,
    );
    return true;
  }
}

/// The Surf feed, keyed by filter.
final surfFeedProvider =
    NotifierProvider.family<SurfFeedController, SurfFeedState, SurfFilter>(
      SurfFeedController.new,
      name: 'surfFeed',
    );

/// Which filter chip is selected.
class SurfFilterController extends Notifier<SurfFilter> {
  @override
  SurfFilter build() => SurfFilter.all;

  /// Selects [value].
  void select(SurfFilter value) => state = value;
}

/// The selected Surf filter.
final surfFilterProvider = NotifierProvider<SurfFilterController, SurfFilter>(
  SurfFilterController.new,
  name: 'surfFilter',
);
