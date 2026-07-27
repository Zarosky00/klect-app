/// WebRTC transport configuration for KLECT calls.
///
/// Signalling is Supabase (`calls` + `call_signals`); this file is only about
/// how the *media* path is negotiated.
library;

import '../../../core/supabase.dart';

/// ICE configuration for the peer connection.
///
/// ## ⚠️ TURN IS REQUIRED FOR PRODUCTION — READ THIS
///
/// STUN alone only works when both peers can be reached by punching a hole
/// through their NAT. Roughly 10–20 % of real-world pairs cannot: symmetric
/// NATs (most carrier-grade mobile networks), corporate firewalls that block
/// UDP, and double-NAT home routers all fail. Those calls will ring, negotiate,
/// and then never connect — the peer connection walks
/// `connecting → failed`, and [hasTurn] is why.
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
  static bool _hasTurn = false;

  /// Whether a relay path is available. False means cross-NAT calls can fail.
  static bool get hasTurn => _hasTurn;

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
  };

  /// The configuration the call engine actually uses.
  ///
  /// ★ This is the hook: replace the body with a call to your
  /// credential-minting edge function and return
  /// `{...configuration(), 'iceServers': [...stunServers, ...fetchedTurn]}`.
  /// It is already awaited on every call setup, so nothing else has to change.
  static Future<Map<String, dynamic>> resolve() async {
    final response = await KlectSupabase.client.functions.invoke(
      'turn-credentials',
    );
    final data = response.data;
    if (data is! Map) {
      throw StateError('TURN credentials are unavailable.');
    }
    final rawServers = data['iceServers'];
    if (rawServers is! List || rawServers.isEmpty) {
      throw StateError('TURN credentials are unavailable.');
    }
    final servers = <Map<String, dynamic>>[
      for (final server in rawServers)
        if (server is Map)
          <String, dynamic>{
            for (final entry in server.entries)
              entry.key.toString(): entry.value,
          },
    ];
    _hasTurn = servers.any(
      (server) => server['username'] != null && server['credential'] != null,
    );
    if (!_hasTurn) throw StateError('TURN credentials are unavailable.');
    return <String, dynamic>{...configuration(), 'iceServers': servers};
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
  /// How long an unanswered call rings before it is marked missed.
  static const Duration ringTimeout = Duration(seconds: 45);

  /// How long a `disconnected` peer connection is given to heal itself before
  /// an ICE restart is attempted.
  static const Duration reconnectGrace = Duration(seconds: 4);

  /// How long a reconnect attempt runs before the call is declared failed.
  static const Duration reconnectTimeout = Duration(seconds: 25);
}
