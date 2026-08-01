/// WebRTC transport configuration for KLECT calls.
///
/// Signalling is Supabase (`calls` + `call_signals`); this file is only about
/// how the *media* path is negotiated.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../core/supabase.dart';

/// The outcome of one ICE-server resolution for one call id.
///
/// Resolution never throws: a failure, a timeout, or a response without a
/// usable relay entry all degrade to a STUN-only [configuration] with
/// [relayAvailable] `false` and a [failure] code, so call setup continues and
/// the Call_Screen can show the non-blocking carrier-network warning
/// (Requirements 10.3, 10.4).
class IceResolution {
  /// Creates a resolution.
  const IceResolution({
    required this.configuration,
    required this.relayAvailable,
    this.failure,
  });

  /// Ready to hand to `createPeerConnection`.
  final Map<String, dynamic> configuration;

  /// Whether a relay (TURN) entry carrying both a username and a credential is
  /// part of [configuration]. `false` ⇒ show the carrier-network warning.
  final bool relayAvailable;

  /// `'turn_not_configured' | 'timeout' | 'provider_unavailable'`, or null when
  /// a relay path was resolved.
  final String? failure;

  /// The ICE servers actually passed to the peer connection.
  List<Map<String, dynamic>> get iceServers => <Map<String, dynamic>>[
    for (final server in configuration['iceServers'] as List<dynamic>)
      server as Map<String, dynamic>,
  ];

  /// What `record_call_diagnostic` stores for operator review.
  Map<String, dynamic> get diagnostic => <String, dynamic>{
    'relay_available': relayAvailable,
    if (failure != null) 'failure': failure,
    'ice_server_count': iceServers.length,
  };
}

/// ICE configuration for the peer connection.
///
/// ## ⚠️ TURN IS REQUIRED FOR PRODUCTION — READ THIS
///
/// STUN alone only works when both peers can be reached by punching a hole
/// through their NAT. Roughly 10–20 % of real-world pairs cannot: symmetric
/// NATs (most carrier-grade mobile networks), corporate firewalls that block
/// UDP, and double-NAT home routers all fail. Those calls will ring, negotiate,
/// and then never connect — the peer connection walks
/// `connecting → failed`, and `IceResolution.relayAvailable == false` is why.
///
/// **To fix it, fill in [turnServers] below** with credentials from a TURN
/// provider (coturn on your own box, Cloudflare Calls, Twilio NTS, Xirsys, …).
/// Do *not* paste a long-lived static secret into this file — TURN credentials
/// shipped in a client are world-readable. The correct shape is:
///
/// 1. deploy a Supabase edge function that mints **short-lived** TURN
///    credentials (HMAC of `expiry:username` against your TURN shared secret);
/// 2. fetch them inside [resolve], which the call engine awaits before it
///    creates the peer connection;
/// 3. keep [stunServers] as the first entries so a direct path is still
///    preferred when one exists.
///
/// Until then the app runs on public STUN, which is correct for development
/// and for peers on friendly networks.
abstract final class KlectCallIce {
  /// QA-only switch used by the mandatory relay test matrix.
  ///
  /// Build the candidate with
  /// `--dart-define=KLECT_FORCE_TURN_RELAY=true` to reject host and
  /// server-reflexive candidates. Production builds omit the define and keep
  /// WebRTC's normal direct-path-first behaviour.
  static const bool forceTurnRelay = bool.fromEnvironment(
    'KLECT_FORCE_TURN_RELAY',
  );

  /// Public STUN servers. Free, stateless, and enough to discover a
  /// server-reflexive candidate.
  static const List<Map<String, dynamic>> stunServers = <Map<String, dynamic>>[
    <String, dynamic>{
      'urls': <String>[
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun.cloudflare.com:3478',
      ],
    },
  ];

  /// ★ **ADD TURN CREDENTIALS HERE** (or, better, return them from
  /// [resolve] after fetching short-lived ones from an edge function).
  ///
  /// Expected entry shape:
  /// ```dart
  /// <String, dynamic>{
  ///   'urls': <String>['turn:turn.example.com:3478?transport=udp'],
  ///   'username': '<ephemeral-username>',
  ///   'credential': '<ephemeral-password>',
  /// }
  /// ```
  static const List<Map<String, dynamic>> turnServers =
      <Map<String, dynamic>>[];

  /// At most this many ICE entries reach the peer connection (Requirement
  /// 10.5). Entries beyond the eighth of the STUN-then-relay order are dropped.
  static const int maxIceServers = 8;

  /// The resolution already computed for [_cachedCallId].
  static IceResolution? _cached;
  static String? _cachedCallId;

  /// The `RTCConfiguration` handed to `createPeerConnection`.
  ///
  /// Unified Plan is mandatory — the plan-b semantics `addStream` implies are
  /// removed from modern WebRTC stacks. `iceCandidatePoolSize` warms candidate
  /// gathering so the first offer already carries host candidates.
  static Map<String, dynamic> configuration() => <String, dynamic>{
    'iceServers': <Map<String, dynamic>>[...stunServers, ...turnServers],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 2,
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    if (forceTurnRelay) 'iceTransportPolicy': 'relay',
  };

  /// Builds the final peer-connection configuration.
  ///
  /// [forceRelay] is exposed for deterministic tests; runtime resolution uses
  /// [forceTurnRelay], which is compile-time only and cannot be toggled by a
  /// remote payload or an end user.
  @visibleForTesting
  static Map<String, dynamic> peerConnectionConfiguration(
    List<Map<String, dynamic>> servers, {
    bool forceRelay = forceTurnRelay,
  }) => <String, dynamic>{
    ...configuration(),
    'iceServers': servers.length <= maxIceServers
        ? List<Map<String, dynamic>>.unmodifiable(servers)
        : List<Map<String, dynamic>>.unmodifiable(servers.take(maxIceServers)),
    if (forceRelay) 'iceTransportPolicy': 'relay',
    if (!forceRelay) 'iceTransportPolicy': 'all',
  };

  /// Fetches the raw `turn-credentials` payload. Overridable in tests.
  @visibleForTesting
  static Future<Object?> Function() credentialFetcher = _invokeEdgeFunction;

  static Future<Object?> _invokeEdgeFunction() async {
    final response = await KlectSupabase.client.functions.invoke(
      'turn-credentials',
    );
    return response.data;
  }

  /// Resolves the ICE configuration for [callId] — never throws.
  ///
  /// The whole resolution is capped at [KlectCallTimings.iceConfigTimeout]
  /// (Requirements 10.1, 10.4). On a failure, a timeout, or a response without
  /// a usable relay entry the result is a STUN-only configuration with
  /// `relayAvailable: false`. The outcome is memoised per call id, so no second
  /// `turn-credentials` request is ever issued for the same call.
  static Future<IceResolution> resolve({required String callId}) async {
    final cached = _cached;
    if (cached != null && _cachedCallId == callId) return cached;
    IceResolution resolution;
    try {
      final data = await credentialFetcher().timeout(
        KlectCallTimings.iceConfigTimeout,
      );
      resolution = resolutionFrom(data);
    } on TimeoutException {
      resolution = stunOnly('timeout');
    } catch (_) {
      resolution = stunOnly('provider_unavailable');
    }
    _cached = resolution;
    _cachedCallId = callId;
    return resolution;
  }

  /// Turns a `turn-credentials` payload into a resolution: every STUN entry
  /// first, every relay entry after, the list truncated to [maxIceServers] by
  /// discarding the tail of that order (Requirement 10.5).
  @visibleForTesting
  static IceResolution resolutionFrom(Object? data) {
    final rawServers = data is Map ? data['iceServers'] : null;
    if (rawServers is! List) return stunOnly('provider_unavailable');

    final stun = <Map<String, dynamic>>[];
    final relay = <Map<String, dynamic>>[];
    for (final raw in rawServers) {
      if (raw is! Map) continue;
      final server = <String, dynamic>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
      final urls = _urlsOf(server);
      if (urls.isEmpty) continue;
      if (urls.any(_isRelayUrl)) {
        // An incomplete relay entry cannot authenticate, so it is dropped
        // rather than passed to the peer connection (Requirement 10.3).
        if (_hasCredentials(server)) relay.add(server);
        continue;
      }
      stun.add(server);
    }
    if (stun.isEmpty) stun.addAll(stunServers);
    if (relay.isEmpty) {
      return IceResolution(
        configuration: _configurationWith(stun),
        relayAvailable: false,
        failure: 'turn_not_configured',
      );
    }
    return IceResolution(
      configuration: _configurationWith(<Map<String, dynamic>>[
        ...stun,
        ...relay,
      ]),
      relayAvailable: true,
    );
  }

  /// A STUN-only resolution carrying [failure].
  @visibleForTesting
  static IceResolution stunOnly(String failure) => IceResolution(
    configuration: _configurationWith(stunServers),
    relayAvailable: false,
    failure: failure,
  );

  /// Forgets the memoised resolution — for tests and for a fresh session.
  @visibleForTesting
  static void resetResolution() {
    _cached = null;
    _cachedCallId = null;
  }

  static Map<String, dynamic> _configurationWith(
    List<Map<String, dynamic>> servers,
  ) => peerConnectionConfiguration(servers);

  static bool _isRelayUrl(String url) =>
      url.startsWith('turn:') || url.startsWith('turns:');

  /// Whether the peer connection could actually authenticate with this entry.
  static bool _hasCredentials(Map<String, dynamic> server) {
    final username = server['username'];
    final credential = server['credential'];
    return username is String &&
        username.isNotEmpty &&
        credential is String &&
        credential.isNotEmpty;
  }

  static List<String> _urlsOf(Map<String, dynamic> server) {
    final urls = server['urls'] ?? server['url'];
    if (urls is String) return urls.isEmpty ? <String>[] : <String>[urls];
    if (urls is List) {
      return <String>[
        for (final url in urls)
          if (url is String && url.isNotEmpty) url,
      ];
    }
    return <String>[];
  }

  /// Media constraints for a call of the given kind.
  static Map<String, dynamic> mediaConstraints({required bool video}) =>
      <String, dynamic>{
        'audio': <String, dynamic>{
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video
            ? <String, dynamic>{
                'facingMode': 'user',
                'width': <String, dynamic>{'ideal': 1280},
                'height': <String, dynamic>{'ideal': 720},
                'frameRate': <String, dynamic>{'ideal': 30},
              }
            : false,
      };
}

/// Timings the call state machine runs on.
///
/// These are call-protocol durations, not motion, so they deliberately are not
/// design tokens — `docs/DESIGN_SYSTEM.md` caps *animation* at 480 ms, which
/// has nothing to do with how long a phone rings.
abstract final class KlectCallTimings {
  /// How long the whole ICE-server resolution may take before the call engine
  /// gives up and creates the peer connection with STUN only.
  static const Duration iceConfigTimeout = Duration(seconds: 5);

  /// How long an unanswered call rings before it is marked missed.
  ///
  /// Measured from the `calls` row creation timestamp, never from the moment
  /// the local timer was armed (Requirement 7.5), so a row that arrives late
  /// still rings for the right remaining time.
  static const Duration ringTimeout = Duration(seconds: 45);

  /// How long an answered call may negotiate media before it is declared
  /// failed, measured from the transition into `connecting` (Requirement 7.15).
  static const Duration connectTimeout = Duration(seconds: 30);

  /// How long the `answer_call` RPC may take before the join is abandoned
  /// (Requirement 7.14).
  static const Duration answerTimeout = Duration(seconds: 15);

  /// How long `start_call` may take before the thread recovers its controls.
  static const Duration startTimeout = Duration(seconds: 15);

  /// Maximum time for one in-call device control to apply.
  static const Duration controlTimeout = Duration(seconds: 1);

  /// No remote video frame for this long switches to the named fallback.
  static const Duration remoteFrameTimeout = Duration(seconds: 3);

  /// How long a `disconnected` peer connection is given to heal itself before
  /// an ICE restart is attempted.
  static const Duration reconnectGrace = Duration(seconds: 4);

  /// How long a reconnect attempt runs before the call is declared failed.
  static const Duration reconnectTimeout = Duration(seconds: 25);

  /// How often the in-call duration is republished.
  static const Duration elapsedTick = Duration(seconds: 1);

  /// The upper bound on the client-reported elapsed value handed to `end_call`
  /// (Requirement 7.8) — one day, matching the server-side clamp.
  static const int maxClientElapsedSeconds = 86400;
}
