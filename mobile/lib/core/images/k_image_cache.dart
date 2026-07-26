import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// The disk cache behind every network image in the product.
///
/// The stock pipeline has two failure modes this closes: a request with no
/// timeout sits on a dead connection forever (so a broken image looks like
/// loading forever), and a transient blip fails immediately with no second
/// chance. Fetches here fail fast and retry a *bounded* number of times, so
/// the error state actually appears and a flaky cell connection still wins.
abstract final class KImageCache {
  static CacheManager? _manager;

  /// The shared manager. Lazy, so nothing touches the file system until a
  /// network image is actually built.
  static CacheManager get instance =>
      _manager ??= CacheManager(Config(_key, fileService: _BoundedRetryFileService()));

  static const String _key = 'klectImageCache';
}

/// An HTTP file service with a per-attempt timeout and bounded retries.
class _BoundedRetryFileService extends HttpFileService {
  /// Total attempts per fetch, the first try included.
  static const int _maxAttempts = 3;

  /// How long one attempt may hang before the connection is called dead.
  ///
  /// Operational constant, not a design value — the same class of number as
  /// the offline queue's retry interval.
  static const Duration _attemptTimeout = Duration(seconds: 15);

  /// Breather between attempts, so a hiccuping network gets time to recover.
  static const Duration _retryDelay = Duration(seconds: 1);

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    for (var attempt = 1; ; attempt++) {
      try {
        final response =
            await super.get(url, headers: headers).timeout(_attemptTimeout);
        // A server error is worth another try. Anything else is an answer:
        // 2xx streams, 4xx fails fast in the cache layer without more
        // attempts — a 404 will not become a 200 by asking again.
        if (response.statusCode < 500 || attempt >= _maxAttempts) {
          return response;
        }
      } on Exception {
        if (attempt >= _maxAttempts) rethrow;
      }
      await Future<void>.delayed(_retryDelay);
    }
  }
}
