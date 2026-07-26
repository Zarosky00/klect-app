import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../core/storage/key_value_store.dart';
import '../../design/motion.dart';

/// Which slice of `search_all` is on screen.
enum SearchSegment {
  /// Everything, sectioned.
  all('All'),

  /// Collectors.
  people('People'),

  /// Collections and the shelves inside them.
  collections('Collections'),

  /// Individual things.
  items('Items'),

  /// Tags.
  tags('Tags');

  const SearchSegment(this.label);

  /// Segment label.
  final String label;
}

/// What the search screen renders.
@immutable
class SearchQueryState {
  /// Creates a search state.
  const SearchQueryState({
    this.query = '',
    this.results,
    this.busy = false,
    this.error,
    this.segment = SearchSegment.all,
  });

  /// The raw text in the field.
  final String query;

  /// The last completed result set, or null before the first search.
  final SearchResults? results;

  /// A request is in flight.
  final bool busy;

  /// The last failure.
  final KlectError? error;

  /// Which segment is selected.
  final SearchSegment segment;

  /// True when the query is too short to search on.
  bool get isIdle => query.trim().length < SearchQueryController.minimumLength;

  /// True when a completed search returned nothing at all.
  bool get isEmptyResult =>
      !busy && !isIdle && results != null && results!.isEmpty;

  /// Copy with overrides. [clear] wipes results and error together.
  SearchQueryState copyWith({
    String? query,
    SearchResults? results,
    bool? busy,
    KlectError? error,
    SearchSegment? segment,
    bool clear = false,
  }) =>
      SearchQueryState(
        query: query ?? this.query,
        results: clear ? null : (results ?? this.results),
        busy: busy ?? this.busy,
        error: clear ? null : (error ?? this.error),
        segment: segment ?? this.segment,
      );
}

/// Debounced, race-proof search over `search_all`.
///
/// Every keystroke restarts a [KDurations.medium] timer instead of firing a
/// request, and each request carries a generation number so a slow early
/// response can never overwrite a fast later one.
class SearchQueryController extends Notifier<SearchQueryState> {
  /// Below this many characters we do not hit the network at all.
  static const int minimumLength = 2;

  /// How many hits each bucket returns.
  static const int pageSize = 20;

  Timer? _debounce;
  int _generation = 0;

  @override
  SearchQueryState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SearchQueryState();
  }

  /// Types into the field. Schedules a search; does not run one.
  void setQuery(String value) {
    _debounce?.cancel();
    if (value.trim().length < minimumLength) {
      _generation++;
      state = state.copyWith(query: value, busy: false, clear: true);
      return;
    }
    state = state.copyWith(query: value, busy: true);
    _debounce = Timer(KDurations.medium, () => unawaited(run()));
  }

  /// Switches the visible segment. No network.
  void setSegment(SearchSegment segment) {
    state = state.copyWith(segment: segment);
  }

  /// Replaces the query and searches immediately — used by recent searches,
  /// trending tags and tag result chips.
  Future<void> submit(String value) {
    _debounce?.cancel();
    state = state.copyWith(query: value, busy: true);
    return run();
  }

  /// Runs the search for whatever is in [SearchQueryState.query] right now.
  Future<void> run() async {
    final query = state.query.trim();
    if (query.length < minimumLength) {
      state = state.copyWith(busy: false, clear: true);
      return;
    }
    final generation = ++_generation;
    try {
      final results = await ref
          .read(klectApiProvider)
          .searchAll(query, limit: pageSize);
      if (generation != _generation) return;
      state = state.copyWith(results: results, busy: false, clear: false);
      // Only a search that actually returned something is worth remembering.
      if (!results.isEmpty) {
        await ref.read(recentSearchesProvider.notifier).record(query);
      }
    } on KlectError catch (error) {
      if (generation != _generation) return;
      state = SearchQueryState(
        query: state.query,
        segment: state.segment,
        error: error,
      );
    }
  }

  /// Empties the field and the results.
  void clear() {
    _debounce?.cancel();
    _generation++;
    state = const SearchQueryState();
  }
}

/// The search screen's state.
final searchQueryProvider =
    NotifierProvider<SearchQueryController, SearchQueryState>(
  SearchQueryController.new,
  name: 'searchQuery',
);

/// Recently searched terms, newest first, persisted across cold starts.
class RecentSearches extends Notifier<List<String>> {
  /// Where the list is persisted.
  static const String storageKey = 'klect.search.recent.v1';

  /// How many terms are kept.
  static const int maxEntries = 10;

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  List<String> build() {
    final raw = _store.getString(storageKey);
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return <String>[
        for (final entry in decoded)
          if (entry is String && entry.isNotEmpty) entry,
      ];
    } on FormatException {
      return const <String>[];
    }
  }

  Future<void> _persist(List<String> next) async {
    state = next;
    await _store.setString(storageKey, jsonEncode(next));
  }

  /// Moves [term] to the front, de-duplicating case-insensitively.
  Future<void> record(String term) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return Future<void>.value();
    final lower = trimmed.toLowerCase();
    final next = <String>[
      trimmed,
      for (final existing in state)
        if (existing.toLowerCase() != lower) existing,
    ];
    return _persist(next.take(maxEntries).toList());
  }

  /// Drops one term.
  Future<void> remove(String term) => _persist(<String>[
        for (final existing in state)
          if (existing != term) existing,
      ]);

  /// Drops everything.
  Future<void> clear() => _persist(const <String>[]);
}

/// Recent searches.
final recentSearchesProvider =
    NotifierProvider<RecentSearches, List<String>>(
  RecentSearches.new,
  name: 'recentSearches',
);
