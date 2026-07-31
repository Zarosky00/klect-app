import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../storage/key_value_store.dart';

/// A newer release of the app, discovered on GitHub.
@immutable
class AvailableUpdate {
  /// Creates an update descriptor.
  const AvailableUpdate({
    required this.version,
    required this.notes,
    required this.downloadUrl,
    this.sha256,
    this.sizeBytes,
  });

  /// Normalised semantic version of the release — no leading `v`, no build
  /// metadata.
  final String version;

  /// Release notes (the release `body`), shown as plain text.
  final String notes;

  /// Direct HTTPS URL for the release's `klect.apk` asset.
  final String downloadUrl;

  /// GitHub's SHA-256 digest for the APK, when the release provides one.
  final String? sha256;

  /// Expected APK size from GitHub release metadata.
  final int? sizeBytes;

  /// Round-trips through the on-device cache.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'notes': notes,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
  };

  /// Parses a cached update; null when the shape is wrong.
  static AvailableUpdate? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    if (version is! String || version.isEmpty) return null;
    final notes = json['notes'];
    final downloadUrl = json['downloadUrl'];
    final sha256 = json['sha256'];
    final sizeBytes = json['sizeBytes'];
    return AvailableUpdate(
      version: version,
      notes: notes is String ? notes : '',
      // Caches written before the in-app downloader used the stable asset URL.
      downloadUrl: downloadUrl is String && downloadUrl.startsWith('https://')
          ? downloadUrl
          : UpdateChecker.apkUrl,
      sha256: sha256 is String ? sha256 : null,
      sizeBytes: sizeBytes is int ? sizeBytes : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AvailableUpdate &&
          other.version == version &&
          other.notes == notes &&
          other.downloadUrl == downloadUrl &&
          other.sha256 == sha256 &&
          other.sizeBytes == sizeBytes;

  @override
  int get hashCode =>
      Object.hash(version, notes, downloadUrl, sha256, sizeBytes);
}

/// What an explicit, user-requested update check found.
enum ManualUpdateStatus {
  /// GitHub reports a version newer than this build.
  updateAvailable,

  /// GitHub was reached and this build is current.
  upToDate,

  /// GitHub could not be reached or returned unusable release metadata.
  unavailable,
}

/// Result of an explicit update check from Settings.
@immutable
class ManualUpdateResult {
  /// Creates a manual check result.
  const ManualUpdateResult(this.status, {this.update});

  /// The outcome shown to the user.
  final ManualUpdateStatus status;

  /// Present only when [status] is [ManualUpdateStatus.updateAvailable].
  final AvailableUpdate? update;
}

/// Checks the public GitHub repo for a newer sideloaded Android build.
///
/// Everything about this is deliberately quiet: offline, rate-limited,
/// unparsable, repo-gone — every failure resolves to "no update", never to a
/// surfaced error. The APK itself downloads inside Klect and is handed to
/// Android's trusted package installer for explicit user approval.
class UpdateChecker {
  /// Creates a checker over the durable store.
  ///
  /// [client], [currentVersion] and [now] exist for tests; production code
  /// uses the defaults.
  UpdateChecker({
    required KeyValueStore store,
    http.Client? client,
    String currentVersion = kAppVersion,
    DateTime Function() now = DateTime.now,
  }) // ignore_for_file: prefer_initializing_formals
  : _store = store,
       _client = client,
       _currentVersion = currentVersion,
       _now = now;

  /// Latest-release metadata. Public repo — no auth needed.
  static const String releaseEndpoint =
      'https://api.github.com/repos/Zarosky00/klect-app/releases/latest';

  /// Stable APK URL: `latest` re-points itself as releases are published.
  static const String apkUrl =
      'https://github.com/Zarosky00/klect-app/releases/latest/download/klect.apk';

  /// Where the timestamp of the last *successful* check is persisted.
  static const String lastCheckKey = 'klect.update.lastCheckAt.v1';

  /// Where the last successfully fetched release is cached.
  static const String cachedReleaseKey = 'klect.update.latestRelease.v1';

  /// Where "the user skipped version x.y.z" is persisted.
  static const String skippedVersionKey = 'klect.update.skippedVersion.v1';

  /// At most one network check per window; inside it we answer from cache.
  /// Network policy, not motion — like the offline queue's retry cadence it
  /// deliberately does not come from the design tokens.
  static const Duration checkInterval = Duration(hours: 6);

  /// How long GitHub gets before we give up silently.
  static const Duration requestTimeout = Duration(seconds: 12);

  final KeyValueStore _store;
  final http.Client? _client;
  final String _currentVersion;
  final DateTime Function() _now;

  /// The newer release the chrome should offer, or null — up to date,
  /// skipped, throttled-with-no-news, offline and rate-limited all collapse
  /// to null by design.
  Future<AvailableUpdate?> check() async {
    final release = await _latestRelease();
    if (release == null) return null;
    if (!isNewer(release.version, _currentVersion)) return null;
    if (_store.getString(skippedVersionKey) == release.version) return null;
    return release;
  }

  /// Checks GitHub immediately because the user explicitly requested it.
  ///
  /// This bypasses the six-hour background throttle and any skipped-version
  /// preference. A skipped release should still be discoverable here.
  Future<ManualUpdateResult> checkNow() async {
    final release = await _fetchLatestRelease();
    if (release == null) {
      return const ManualUpdateResult(ManualUpdateStatus.unavailable);
    }
    await _cacheRelease(release);
    if (isNewer(release.version, _currentVersion)) {
      return ManualUpdateResult(
        ManualUpdateStatus.updateAvailable,
        update: release,
      );
    }
    return const ManualUpdateResult(ManualUpdateStatus.upToDate);
  }

  /// Persists "stop bannering [version]" — the banner stays gone until a
  /// release with a *different, newer* version appears.
  Future<void> skip(String version) =>
      _store.setString(skippedVersionKey, version);

  /// True when [candidate] is a strictly newer semantic version than
  /// [current].
  ///
  /// Accepts an optional leading `v`/`V` and ignores pre-release and build
  /// metadata (`v1.3.0-rc.1+42` compares as `1.3.0`). Anything that does not
  /// parse compares as "not newer" — a malformed tag must never banner.
  static bool isNewer(String candidate, String current) {
    final a = _parse(candidate);
    final b = _parse(current);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  /// `v1.3.0-rc.1+42` → `1.3.0`, or null when the tag is not a version.
  static String? normalize(String tag) => _parse(tag)?.join('.');

  /// major/minor/patch as ints, or null. Missing segments read as zero
  /// (`v2` → `[2, 0, 0]`).
  static List<int>? _parse(String raw) {
    var version = raw.trim();
    if (version.startsWith('v') || version.startsWith('V')) {
      version = version.substring(1);
    }
    // Pre-release and build metadata never participate in the comparison.
    final metadata = version.indexOf(RegExp('[-+]'));
    if (metadata >= 0) version = version.substring(0, metadata);
    if (version.isEmpty) return null;

    final parts = version.split('.');
    if (parts.length > 3) return null;
    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      numbers.add(number);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }

  /// The newest release we know of: cache inside the throttle window, network
  /// outside it, cache again when the network lets us down.
  Future<AvailableUpdate?> _latestRelease() async {
    final cached = AvailableUpdate.fromJson(_readCachedJson());
    if (_withinThrottleWindow()) return cached;

    final fetched = await _fetchLatestRelease();
    if (fetched == null) {
      // Failure: keep the last known answer and do NOT bump the timestamp,
      // so the next cold start tries the network again.
      return cached;
    }
    await _cacheRelease(fetched);
    return fetched;
  }

  Future<void> _cacheRelease(AvailableUpdate release) async {
    await _store.setString(
      lastCheckKey,
      _now().millisecondsSinceEpoch.toString(),
    );
    await _store.setString(cachedReleaseKey, jsonEncode(release.toJson()));
  }

  bool _withinThrottleWindow() {
    final raw = _store.getString(lastCheckKey);
    final last = raw == null ? null : int.tryParse(raw);
    if (last == null) return false;
    final elapsed = _now().millisecondsSinceEpoch - last;
    // A clock that moved backwards re-checks rather than never checking.
    return elapsed >= 0 && elapsed < checkInterval.inMilliseconds;
  }

  Object? _readCachedJson() {
    final raw = _store.getString(cachedReleaseKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  Future<AvailableUpdate?> _fetchLatestRelease() async {
    final client = _client ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse(releaseEndpoint),
            headers: const <String, String>{
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(requestTimeout);
      // Rate limit (403/429), missing release (404), GitHub trouble (5xx):
      // all silent.
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final tag = decoded['tag_name'];
      if (tag is! String) return null;
      final version = normalize(tag);
      if (version == null) return null;
      final body = decoded['body'];

      final assets = decoded['assets'];
      if (assets is! List) return null;
      Map<Object?, Object?>? apk;
      for (final asset in assets) {
        if (asset is Map<Object?, Object?> &&
            asset['name'] == 'klect.apk' &&
            asset['state'] == 'uploaded') {
          apk = asset;
          break;
        }
      }
      if (apk == null) return null;

      final rawUrl = apk['browser_download_url'];
      if (rawUrl is! String) return null;
      final downloadUri = Uri.tryParse(rawUrl);
      if (downloadUri == null || downloadUri.scheme != 'https') return null;

      String? digest;
      final rawDigest = apk['digest'];
      if (rawDigest is String &&
          RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(rawDigest)) {
        digest = rawDigest.substring('sha256:'.length).toLowerCase();
      }
      final rawSize = apk['size'];
      return AvailableUpdate(
        version: version,
        notes: body is String ? body.trim() : '',
        downloadUrl: downloadUri.toString(),
        sha256: digest,
        sizeBytes: rawSize is int && rawSize > 0 ? rawSize : null,
      );
    } on Exception {
      // Offline, DNS, TLS, timeout, malformed JSON — silent by contract.
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }
}

/// The app-wide checker, over the same durable store as the theme override.
final updateCheckerProvider = Provider<UpdateChecker>(
  (ref) => UpdateChecker(store: ref.watch(keyValueStoreProvider)),
  name: 'updateChecker',
);

/// Drives the update banner: runs the (throttled) check once per cold start
/// and lets the chrome dismiss or skip.
///
/// Android-only by design — iOS cannot sideload an APK and web reloads
/// itself — so every other platform short-circuits to "no update" without a
/// network call.
class UpdatePromptController extends AsyncNotifier<AvailableUpdate?> {
  @override
  Future<AvailableUpdate?> build() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    return ref.watch(updateCheckerProvider).check();
  }

  /// Hides the banner until the next cold start. Nothing is persisted.
  void dismiss() {
    state = const AsyncData<AvailableUpdate?>(null);
  }

  /// Persists the skip: this version never banners again, the next one does.
  Future<void> skip() async {
    final update = state.value;
    if (update == null) return;
    await ref.read(updateCheckerProvider).skip(update.version);
    state = const AsyncData<AvailableUpdate?>(null);
  }
}

/// The update the chrome should offer right now, or null.
final availableUpdateProvider =
    AsyncNotifierProvider<UpdatePromptController, AvailableUpdate?>(
      UpdatePromptController.new,
      name: 'availableUpdate',
    );
