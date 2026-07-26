import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/key_value_store.dart';

/// Persists the **last successful first page** of a feed as raw JSON rows, so
/// a cold start with no connection opens onto yesterday's content instead of
/// an error screen.
///
/// This is deliberately not "offline support": one page, hydrated only when
/// the live fetch fails with a network error, replaced wholesale on the next
/// successful load. Counts inside the cached rows are stale by definition —
/// they still come from the database columns, just an older read of them.
class FeedPageCache {
  /// Creates a cache over the durable store.
  FeedPageCache(this._store);

  final KeyValueStore _store;

  static const String _prefix = 'feed_page.v1.';

  /// The cached rows for [key], or null when there are none (or the payload
  /// no longer parses — a schema drift simply misses, never crashes).
  List<Map<String, dynamic>>? read(String key) {
    final raw = _store.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final rows = <Map<String, dynamic>>[
        for (final row in decoded)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      return rows.isEmpty ? null : rows;
    } on FormatException {
      return null;
    }
  }

  /// Replaces the cached page for [key]. Best effort — a row that cannot be
  /// encoded must never break the successful fetch that produced it.
  Future<void> write(String key, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    try {
      await _store.setString('$_prefix$key', jsonEncode(rows));
    } on Object {
      // Unencodable payload — skip the cache, keep the feed.
    }
  }
}

/// The app-wide first-page cache.
final feedPageCacheProvider = Provider<FeedPageCache>(
  (ref) => FeedPageCache(ref.watch(keyValueStoreProvider)),
  name: 'feedPageCache',
);
