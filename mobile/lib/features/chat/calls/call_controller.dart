import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/api/api_error.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../chat_api.dart';
import 'call_availability.dart';
import 'call_config.dart';
import 'call_duration.dart';

/// Where a call is in its life.
enum CallPhase {
  /// Nothing is happening.
  idle,

  /// We placed it and are waiting for an answer.
  dialing,

  /// Somebody is calling us and we have not answered yet.
  incoming,

  /// Answered; media is negotiating.
  connecting,

  /// Connected.
  active,

  /// Media dropped and we are trying to get it back.
  reconnecting,

  /// Over.
  ended,
}

/// The one call the app can be in.
class ActiveCallState {
  /// Creates a call state.
  const ActiveCallState({
    this.call,
    this.phase = CallPhase.idle,
    this.peer,
    this.micEnabled = true,
    this.cameraEnabled = false,
    this.speakerOn = false,
    this.frontCamera = true,
    this.hasRemoteVideo = false,
    this.relayAvailable = true,
    this.chromeVisible = true,
    this.remoteFrameStaleSince,
    this.elapsed = Duration.zero,
    this.localRenderer,
    this.remoteRenderer,
    this.endReason,
    this.error,
  });

  /// The `calls` row, once we have it.
  final CallModel? call;

  /// Where we are.
  final CallPhase phase;

  /// The other party.
  final Profile? peer;

  /// Whether the microphone track is enabled.
  final bool micEnabled;

  /// Whether the camera track is enabled.
  final bool cameraEnabled;

  /// Loudspeaker vs earpiece.
  final bool speakerOn;

  /// Which camera is capturing.
  final bool frontCamera;

  /// Whether the remote side is sending video right now.
  final bool hasRemoteVideo;

  /// Whether this call's ICE resolution produced a usable relay entry.
  ///
  /// Per call, never static: two sequential calls cannot inherit each other's
  /// relay verdict. `false` ⇒ the Call_Screen shows the non-blocking
  /// carrier-network warning (Requirements 10.3, 10.4).
  final bool relayAvailable;

  /// Whether the Call_Screen chrome (header and controls) is showing.
  ///
  /// Lives here rather than in the screen's `State` so a phase change can
  /// restore it, and so the pill and the screen never disagree.
  final bool chromeVisible;

  /// When the remote video last stopped producing frames, or null while the
  /// remote side is producing them (or is not sending video at all).
  final DateTime? remoteFrameStaleSince;

  /// Time since the call connected.
  final Duration elapsed;

  /// Local preview surface. Null until media is open.
  final RTCVideoRenderer? localRenderer;

  /// Remote surface. Null until media is open.
  final RTCVideoRenderer? remoteRenderer;

  /// Why the call finished — shown on the ended card.
  final String? endReason;

  /// A failure worth telling the user about.
  final Object? error;

  /// Whether this is a video call.
  bool get isVideo => call?.kind == CallKind.video;

  /// Whether there is a call on screen at all.
  bool get isBusy => phase != CallPhase.idle && phase != CallPhase.ended;

  /// The in-call timer: `m:ss` below one hour, `h:mm:ss` from one hour on.
  String get formattedElapsed => formatCallDuration(elapsed);

  /// Copy with overrides.
  ActiveCallState copyWith({
    CallModel? call,
    CallPhase? phase,
    Profile? peer,
    bool? micEnabled,
    bool? cameraEnabled,
    bool? speakerOn,
    bool? frontCamera,
    bool? hasRemoteVideo,
    bool? relayAvailable,
    bool? chromeVisible,
    DateTime? remoteFrameStaleSince,
    Duration? elapsed,
    RTCVideoRenderer? localRenderer,
    RTCVideoRenderer? remoteRenderer,
    String? endReason,
    Object? error,
    bool clearError = false,
    bool clearRenderers = false,
    bool clearRemoteFrameStale = false,
  }) => ActiveCallState(
    call: call ?? this.call,
    phase: phase ?? this.phase,
    peer: peer ?? this.peer,
    micEnabled: micEnabled ?? this.micEnabled,
    cameraEnabled: cameraEnabled ?? this.cameraEnabled,
    speakerOn: speakerOn ?? this.speakerOn,
    frontCamera: frontCamera ?? this.frontCamera,
    hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
    relayAvailable: relayAvailable ?? this.relayAvailable,
    chromeVisible: chromeVisible ?? this.chromeVisible,
    remoteFrameStaleSince: clearRemoteFrameStale
        ? null
        : (remoteFrameStaleSince ?? this.remoteFrameStaleSince),
    elapsed: elapsed ?? this.elapsed,
    localRenderer: clearRenderers
        ? null
        : (localRenderer ?? this.localRenderer),
    remoteRenderer: clearRenderers
        ? null
        : (remoteRenderer ?? this.remoteRenderer),
    endReason: endReason ?? this.endReason,
    error: clearError ? null : (error ?? this.error),
  );
}

/// **The call engine.** One peer connection, one signalling channel, one state.
///
/// ### Protocol (matches `docs/BACKEND_API.md` §3)
/// 1. the caller inserts a `calls` row with `status = 'ringing'`;
/// 2. both sides exchange SDP and ICE through `call_signals` inserts
///    (`offer | answer | ice | renegotiate | bye`), delivered over Realtime and
///    replayed from the table on join so a late subscriber never misses the
///    offer;
/// 3. on connect the row moves to `active` and `started_at` is stamped;
/// 4. on hang-up it moves to `ended` with `duration_seconds`, and a
///    `call_event` message is written into the thread so the call log lives
///    where the conversation does. `missed` and `declined` take the same path.
///
/// ### Reach
/// Media traverses NAT with STUN only — see [KlectCallIce] for why a TURN
/// server is required before this is dependable on real mobile networks.
class ActiveCallController extends Notifier<ActiveCallState> {
  /// The only legal [CallPhase] edges (Requirement 7.9).
  ///
  /// Every phase write goes through [_transition], so this map is the whole
  /// truth about how a call may move. `ended` maps to the empty set, which is
  /// what makes it absorbing for the call id it ended (Requirement 7.10): the
  /// only way back to `idle` is a freshly constructed [ActiveCallState], which
  /// is initialisation for a *different* call rather than an outgoing edge.
  static const Map<CallPhase, Set<CallPhase>> allowedTransitions =
      <CallPhase, Set<CallPhase>>{
        CallPhase.idle: {CallPhase.dialing, CallPhase.incoming},
        CallPhase.dialing: {CallPhase.connecting, CallPhase.ended},
        CallPhase.incoming: {CallPhase.connecting, CallPhase.ended},
        CallPhase.connecting: {CallPhase.active, CallPhase.ended},
        CallPhase.active: {CallPhase.reconnecting, CallPhase.ended},
        CallPhase.reconnecting: {CallPhase.active, CallPhase.ended},
        CallPhase.ended: <CallPhase>{},
      };

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RealtimeChannel? _signals;
  RealtimeChannel? _calls;

  Timer? _ringTimer;
  Timer? _connectTimer;
  Timer? _elapsedTimer;
  Timer? _reconnectDeadlineTimer;
  Timer? _iceRestartTimer;
  Timer? _remoteFrameTimer;

  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  final Set<String> _appliedSignals = <String>{};

  bool _isCaller = false;
  bool _remoteDescriptionSet = false;
  bool _closing = false;
  int _iceRestarts = 0;
  DateTime? _reconnectingSince;
  DateTime? _connectedAt;
  String? _peerId;
  String? _conversationId;

  /// The call id whose relay verdict has already been recorded, so the
  /// `record_call_diagnostic` write happens once per call (Requirement 10.4).
  String? _relayVerdictCallId;

  /// What a caller sees when `answer_call` outruns
  /// [KlectCallTimings.answerTimeout] (Requirement 7.14). A bare
  /// [TimeoutException] would surface as generic offline copy, which is not
  /// what happened.
  static const KlectError _answerTimedOut = KlectError(
    KlectErrorKind.network,
    'Could not join the call — it timed out.',
  );

  static const KlectError _startTimedOut = KlectError(
    KlectErrorKind.network,
    'Could not start the call — it timed out.',
  );

  ChatApi get _api => ref.read(chatApiProvider);

  String? get _me => ref.read(currentUserIdProvider);

  @override
  ActiveCallState build() {
    ref.onDispose(() => unawaited(_shutdown()));
    return const ActiveCallState();
  }

  // ─────────────────────────────────────────────────────────── transitions ──

  /// Moves the engine to [next] if [allowedTransitions] permits it.
  ///
  /// Returns `false` and leaves the state completely untouched when the edge is
  /// illegal, including every edge out of `ended` (Requirements 7.9, 7.10).
  /// Asking for the phase the engine is already in is not a transition between
  /// two values: nothing is written and `true` comes back, so a repeated
  /// connection report is harmless.
  ///
  /// [endReason] is only meaningful for [CallPhase.ended] and is the copy the
  /// ended card shows.
  bool _transition(CallPhase next, {String? endReason}) {
    final current = state.phase;
    // Absorbing: the first ending for a call id is the only ending.
    if (current == CallPhase.ended) return false;
    if (current == next) return true;
    if (!(allowedTransitions[current] ?? const <CallPhase>{}).contains(next)) {
      return false;
    }
    state = state.copyWith(phase: next, endReason: endReason);
    _onPhaseEntered(next);
    return true;
  }

  /// Keeps the lifecycle timers tied to the phase they belong to.
  ///
  /// Because [_transition] is the single writer of `phase`, arming and
  /// cancelling here is enough: no path can enter `connecting` without its 30 s
  /// budget (Requirement 7.15), and no ring or connect timer can outlive the
  /// phase that owns it and end an already-connected or already-ended call.
  void _onPhaseEntered(CallPhase phase) {
    switch (phase) {
      case CallPhase.connecting:
        // Ringing is over the moment the call is being answered.
        _ringTimer?.cancel();
        _ringTimer = null;
        _connectTimer?.cancel();
        _connectTimer = Timer(
          KlectCallTimings.connectTimeout,
          () => unawaited(_connectTimedOut()),
        );
      case CallPhase.active:
      case CallPhase.ended:
        _ringTimer?.cancel();
        _ringTimer = null;
        _connectTimer?.cancel();
        _connectTimer = null;
      case CallPhase.idle:
      case CallPhase.dialing:
      case CallPhase.incoming:
      case CallPhase.reconnecting:
        // `dialing` and `incoming` arm the ring timeout from the row itself,
        // which the phase write cannot do for them: [place], [present] and
        // [attach] each know the row they just learned about.
        break;
    }
  }

  // ──────────────────────────────────────────────────────── timing budgets ──

  /// How much of the 45 s ring budget is left for a row created at
  /// [createdAt], as seen at [now] (Requirement 7.5).
  ///
  /// Measuring from the row rather than from the arm time is what makes a
  /// late-delivered `calls` row ring for the *remaining* time instead of a
  /// fresh 45 s. A row already past its budget yields [Duration.zero], and a
  /// row stamped in the future (a skewed clock) is capped at the full budget
  /// so a call can never ring forever.
  @visibleForTesting
  static Duration ringTimeoutRemaining(
    DateTime? createdAt, {
    required DateTime now,
  }) {
    if (createdAt == null) return KlectCallTimings.ringTimeout;
    final remaining = KlectCallTimings.ringTimeout - now.difference(createdAt);
    if (remaining.isNegative) return Duration.zero;
    return remaining > KlectCallTimings.ringTimeout
        ? KlectCallTimings.ringTimeout
        : remaining;
  }

  /// The value handed to `end_call` as `p_client_elapsed_seconds`
  /// (Requirement 7.8): whole seconds, clamped to
  /// `[0, KlectCallTimings.maxClientElapsedSeconds]`.
  ///
  /// This is a diagnostic, never an authority: the stored `duration_seconds`
  /// stays server-computed from `calls.started_at`.
  @visibleForTesting
  static int clientElapsedSeconds(Duration elapsed) {
    final seconds = elapsed.inSeconds;
    if (seconds <= 0) return 0;
    return seconds > KlectCallTimings.maxClientElapsedSeconds
        ? KlectCallTimings.maxClientElapsedSeconds
        : seconds;
  }

  // ───────────────────────────────────────────────────────────── lifecycle ──

  /// Places a call in [conversationId] and returns the created row.
  ///
  /// Permissions must already have been granted — see `CallPermissions`.
  Future<CallModel?> place({
    required String conversationId,
    required CallKind kind,
    Profile? peer,
  }) async {
    if (state.isBusy) return state.call;
    // Requirement 10.8: while the gate is disabled or unresolved, no
    // `start_call` RPC leaves the device and the phase stays at idle.
    if (!ref.read(callAvailabilityProvider)) return null;

    final CallModel call;
    try {
      call = await _api
          .createCall(conversationId: conversationId, kind: kind)
          .timeout(KlectCallTimings.startTimeout);
    } on TimeoutException {
      state = state.copyWith(error: _startTimedOut);
      return null;
    } catch (error) {
      // `idle → ended` is not a legal edge (7.9): a call that was never
      // created has nothing to end, so the engine stays at idle with the
      // failure carried for the thread to surface.
      state = state.copyWith(error: KlectError.from(error));
      return null;
    }

    _isCaller = true;
    _conversationId = conversationId;
    // Requirement 7.1: `dialing` is entered as soon as `start_call` returns —
    // before any media, ICE or member lookup — so the phase can never lag the
    // server by more than the RPC itself.
    state = ActiveCallState(
      call: call,
      peer: peer,
      cameraEnabled: kind == CallKind.video,
      speakerOn: kind == CallKind.video,
    );
    _transition(CallPhase.dialing);

    try {
      await _resolvePeer(conversationId);
      await _openMedia(kind: kind, callId: call.id);
      _watch(call);
      // Requirement 7.1: the local session description is published for the
      // returned call id through `send_call_signal`.
      await _startNegotiation();
      _armRingTimeout();
      return call;
    } catch (error) {
      state = state.copyWith(error: KlectError.from(error));
      _transition(CallPhase.ended, endReason: 'Could not start the call');
      await _shutdown();
      return null;
    }
  }

  /// Registers an incoming call so the UI can offer accept/decline.
  ///
  /// Requirement 7.2: `incoming` is entered only for a `ringing` row addressed
  /// to this account, and only while no call is held. A row we created, a row
  /// that has already moved on, and a row arriving over a live call are all
  /// ignored here — the busy case is declined by the incoming-call listener.
  Future<void> present(CallModel call) async {
    if (state.isBusy) return;
    if (call.status != CallStatus.ringing) return;
    if (call.createdBy == _me) return;
    // An arriving `calls` row is held at idle while calling is off (10.8).
    if (!ref.read(callAvailabilityProvider)) return;
    _isCaller = false;
    _conversationId = call.conversationId;
    // A fresh state, so an `ended` predecessor is left behind with its call id
    // rather than transitioned out of (7.10).
    state = ActiveCallState(
      call: call,
      cameraEnabled: call.kind == CallKind.video,
      speakerOn: call.kind == CallKind.video,
    );
    _transition(CallPhase.incoming);
    // Requirement 7.5: the callee rings on the same 45 s budget as the caller,
    // measured from the row, so a row delivered late rings for what is left.
    _armRingTimeout();
    await _resolvePeer(call.conversationId);
  }

  /// Answers the call currently being presented.
  ///
  /// Permissions must already have been granted — see `CallPermissions`.
  Future<void> accept() async {
    final call = state.call;
    if (call == null || state.phase != CallPhase.incoming) return;
    // Entering `connecting` arms the 30 s connect budget (7.15).
    if (!_transition(CallPhase.connecting)) return;
    try {
      // Requirement 7.14: an `answer_call` that never answers is a failure,
      // not an indefinite wait, so the join is bounded at 15 s.
      final accepted = await _api
          .answerCall(call.id)
          .timeout(KlectCallTimings.answerTimeout);
      state = state.copyWith(call: accepted);
      await _openMedia(kind: call.kind, callId: call.id);
      _watch(call);
      await _api.joinCall(call.id);
      // Replay whatever the caller already sent, then keep listening.
      await _drainStoredSignals(call.id);
    } on TimeoutException {
      // 7.14: the failure is surfaced, the tracks are released by [_finish],
      // and the phase ends failed rather than sitting in `connecting`.
      state = state.copyWith(error: _answerTimedOut);
      await _finish(
        status: CallStatus.failed,
        reason: 'Could not join the call',
        notifyPeer: true,
      );
    } catch (error) {
      state = state.copyWith(error: KlectError.from(error));
      await _finish(
        status: CallStatus.failed,
        reason: 'Could not join the call',
        notifyPeer: true,
      );
    }
  }

  /// Rejects the call currently being presented.
  Future<void> decline() async {
    if (state.call == null) return;
    await _finish(
      status: CallStatus.declined,
      reason: 'Declined',
      notifyPeer: true,
    );
  }

  /// Hangs up, whatever phase we are in.
  Future<void> hangUp() async {
    final phase = state.phase;
    if (phase == CallPhase.idle || phase == CallPhase.ended) return;
    final connected = _connectedAt != null;
    await _finish(
      status: connected
          ? CallStatus.ended
          : (_isCaller ? CallStatus.missed : CallStatus.declined),
      reason: connected ? null : (_isCaller ? 'Cancelled' : 'Declined'),
      notifyPeer: true,
    );
  }

  /// Attaches to a call reached by deep link (`/call/:id`).
  ///
  /// If it is already the call we hold, nothing happens; otherwise the row is
  /// fetched and either presented (still ringing, not ours) or reported ended.
  Future<void> attach(String callId) async {
    if (state.call?.id == callId && state.phase != CallPhase.idle) return;
    // A call deep link is held at idle while calling is off (10.8).
    if (!ref.read(callAvailabilityProvider)) return;
    try {
      final call = await _api.fetchCall(callId);
      if (call == null) {
        _reportDead(endReason: 'That call no longer exists');
        return;
      }
      if (!call.status.isLive) {
        _reportDead(call: call, endReason: _describe(call.status));
        await _resolvePeer(call.conversationId);
        return;
      }
      if (call.createdBy == _me) {
        // Our own outgoing call, resumed after the screen was popped.
        _isCaller = true;
        _conversationId = call.conversationId;
        state = ActiveCallState(
          call: call,
          cameraEnabled: call.kind == CallKind.video,
          speakerOn: call.kind == CallKind.video,
        );
        _transition(CallPhase.dialing);
        // Requirement 7.5: the budget belongs to the row, so a call resumed by
        // deep link keeps ringing only for what is left of its 45 s.
        _armRingTimeout();
        await _resolvePeer(call.conversationId);
        return;
      }
      await present(call);
    } catch (error) {
      _reportDead(
        endReason: 'Could not open that call',
        error: KlectError.from(error),
      );
    }
  }

  /// Shows a call that is already over — a dead deep link, or a row that
  /// finished before we ever held it.
  ///
  /// This constructs a state rather than transitioning: the engine holds no
  /// call, so there is no live phase to leave and `idle → ended` never has to
  /// become a legal edge (7.9).
  void _reportDead({
    CallModel? call,
    required String endReason,
    Object? error,
  }) {
    if (state.isBusy) return;
    state = ActiveCallState(
      call: call,
      phase: CallPhase.ended,
      endReason: endReason,
      error: error,
    );
  }

  /// Clears an ended call so the UI can go back to idle.
  ///
  /// `ended` is absorbing (7.10), so this builds a new [ActiveCallState]
  /// instead of transitioning out of it.
  void dismiss() {
    if (state.phase != CallPhase.ended) return;
    state = const ActiveCallState();
  }

  // ─────────────────────────────────────────────────────────────── controls ──

  /// Mutes or unmutes the microphone.
  Future<bool> toggleMic() async {
    final next = !state.micEnabled;
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    try {
      for (final track in tracks) {
        track.enabled = next;
      }
      state = state.copyWith(micEnabled: next);
      return true;
    } catch (_) {
      for (final track in tracks) {
        track.enabled = state.micEnabled;
      }
      return false;
    }
  }

  /// Switches between the loudspeaker and the earpiece.
  Future<bool> toggleSpeaker() async {
    final next = !state.speakerOn;
    try {
      await Helper.setSpeakerphoneOn(
        next,
      ).timeout(KlectCallTimings.controlTimeout);
      state = state.copyWith(speakerOn: next);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Turns the camera on or off mid-call, renegotiating if a video track has
  /// to be created for the first time.
  Future<bool> toggleCamera() async {
    final stream = _localStream;
    if (stream == null || !state.isVideo) return false;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) {
      return _upgradeToVideo().timeout(
        KlectCallTimings.controlTimeout,
        onTimeout: () => false,
      );
    }
    final next = !state.cameraEnabled;
    try {
      for (final track in videoTracks) {
        track.enabled = next;
      }
      state = state.copyWith(cameraEnabled: next);
      return true;
    } catch (_) {
      for (final track in videoTracks) {
        track.enabled = state.cameraEnabled;
      }
      return false;
    }
  }

  /// Flips between the front and rear cameras.
  Future<bool> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty || !state.cameraEnabled) return false;
    try {
      await Helper.switchCamera(
        tracks.first,
      ).timeout(KlectCallTimings.controlTimeout);
      state = state.copyWith(frontCamera: !state.frontCamera);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Called by the call screen's lifecycle observer.
  ///
  /// Backgrounding stops the camera (the OS would suspend it anyway, and the
  /// privacy indicator should go out) but keeps audio flowing, which is what
  /// every phone does. Nothing is torn down, so returning resumes instantly.
  void handleAppLifecycle(AppLifecycleState lifecycle) {
    final stream = _localStream;
    if (stream == null) return;
    switch (lifecycle) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        for (final track in stream.getVideoTracks()) {
          track.enabled = false;
        }
      case AppLifecycleState.resumed:
        for (final track in stream.getVideoTracks()) {
          track.enabled = state.cameraEnabled;
        }
      case AppLifecycleState.detached:
        unawaited(hangUp());
    }
  }

  // ──────────────────────────────────────────────────────────────── media ──

  Future<void> _openMedia({
    required CallKind kind,
    required String callId,
  }) async {
    final local = RTCVideoRenderer();
    final remote = RTCVideoRenderer();
    await local.initialize();
    await remote.initialize();
    remote.onFirstFrameRendered = _markRemoteFrameLive;
    remote.onResize = _markRemoteFrameLive;

    final stream = await navigator.mediaDevices.getUserMedia(
      KlectCallIce.mediaConstraints(video: kind == CallKind.video),
    );
    _localStream = stream;
    local.srcObject = stream;

    // Resolution never throws: a failure or a timeout degrades to STUN only
    // with `relayAvailable: false`, and the call still gets a peer connection
    // (Requirements 10.1, 10.3, 10.4).
    final ice = await KlectCallIce.resolve(callId: callId);
    unawaited(_recordRelayVerdict(callId: callId, ice: ice));
    final pc = await createPeerConnection(ice.configuration);
    _pc = pc;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }

    // The webrtc_interface callbacks are `Function(...)?`, i.e. they return
    // `dynamic`. Block bodies keep our void handlers out of that return slot.
    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _onLocalCandidate(candidate);
    };
    pc.onTrack = (RTCTrackEvent event) {
      _onRemoteTrack(event, remote);
    };
    pc.onConnectionState = (RTCPeerConnectionState connection) {
      _onConnectionState(connection);
    };
    pc.onRenegotiationNeeded = () {
      _onRenegotiationNeeded();
    };

    state = state.copyWith(
      localRenderer: local,
      remoteRenderer: remote,
      cameraEnabled: kind == CallKind.video,
      relayAvailable: ice.relayAvailable,
    );

    try {
      await Helper.setSpeakerphoneOn(kind == CallKind.video);
    } catch (_) {
      // Not every platform has a speakerphone toggle.
    }
  }

  /// Reports the relay verdict for [callId] once, for operator review
  /// (Requirements 10.3, 10.4). A failed write is never surfaced: a diagnostic
  /// must not be able to break a call.
  Future<void> _recordRelayVerdict({
    required String callId,
    required IceResolution ice,
  }) async {
    if (_relayVerdictCallId == callId) return;
    _relayVerdictCallId = callId;
    try {
      await _api.recordCallDiagnostic(
        callId: callId,
        key: 'ice',
        value: ice.diagnostic,
      );
    } catch (_) {
      // Diagnostics are best-effort.
    }
  }

  Future<bool> _upgradeToVideo() async {
    final pc = _pc;
    final stream = _localStream;
    if (pc == null || stream == null) return false;
    try {
      final camera = await navigator.mediaDevices.getUserMedia(
        KlectCallIce.mediaConstraints(video: true),
      );
      for (final track in camera.getVideoTracks()) {
        await stream.addTrack(track);
        await pc.addTrack(track, stream);
      }
      state.localRenderer?.srcObject = stream;
      state = state.copyWith(cameraEnabled: true);
      // Adding a track changes the SDP: whoever is the offerer renegotiates.
      if (_isCaller) {
        await _startNegotiation();
      } else {
        await _signal(CallSignalType.renegotiate, const <String, dynamic>{});
      }
      return true;
    } catch (error) {
      state = state.copyWith(error: KlectError.from(error));
      return false;
    }
  }

  void _onRemoteTrack(RTCTrackEvent event, RTCVideoRenderer remote) {
    if (event.streams.isEmpty) return;
    _remoteStream = event.streams.first;
    remote.srcObject = _remoteStream;
    if (event.track.kind == 'video') {
      final waitingSince = DateTime.now();
      state = state.copyWith(
        hasRemoteVideo: true,
        remoteRenderer: remote,
        remoteFrameStaleSince: waitingSince,
      );
      _remoteFrameTimer?.cancel();
      _remoteFrameTimer = Timer(KlectCallTimings.remoteFrameTimeout, () {
        if (state.remoteFrameStaleSince != waitingSince) return;
        // Republish at the deadline so the video surface deterministically
        // swaps to its fallback even when no renderer callback ever arrives.
        state = state.copyWith(remoteFrameStaleSince: waitingSince);
      });
    } else {
      state = state.copyWith(remoteRenderer: remote);
    }
  }

  void _markRemoteFrameLive() {
    _remoteFrameTimer?.cancel();
    _remoteFrameTimer = null;
    if (state.remoteFrameStaleSince != null) {
      state = state.copyWith(clearRemoteFrameStale: true);
    }
  }

  // ──────────────────────────────────────────────────────────── signalling ──

  void _watch(CallModel call) {
    _signals = _api.callSignalsChannel(
      callId: call.id,
      onSignal: (row) => unawaited(_applySignal(CallSignal.fromJson(row))),
    )..subscribe();

    _calls = _api.callChannel(callId: call.id, onUpdate: _onCallRow)
      ..subscribe();
  }

  Future<void> _startNegotiation() async {
    final pc = _pc;
    if (pc == null) return;
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _signal(CallSignalType.offer, <String, dynamic>{
      'sdp': offer.sdp,
      'type': offer.type,
    });
  }

  Future<void> _drainStoredSignals(String callId) async {
    final stored = await _api.fetchCallSignals(callId);
    for (final signal in stored) {
      await _applySignal(signal);
    }
  }

  Future<void> _applySignal(CallSignal signal) async {
    if (_closing) return;
    if (signal.senderId == _me) return;
    if (!_appliedSignals.add(signal.id)) return;
    final pc = _pc;

    switch (signal.type) {
      case CallSignalType.offer:
        if (pc == null) return;
        await pc.setRemoteDescription(
          RTCSessionDescription(
            asStringOrNull(signal.payload['sdp']),
            asString(signal.payload['type'], 'offer'),
          ),
        );
        _remoteDescriptionSet = true;
        await _drainCandidates();
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        await _signal(CallSignalType.answer, <String, dynamic>{
          'sdp': answer.sdp,
          'type': answer.type,
        });
      case CallSignalType.answer:
        if (pc == null) return;
        await pc.setRemoteDescription(
          RTCSessionDescription(
            asStringOrNull(signal.payload['sdp']),
            asString(signal.payload['type'], 'answer'),
          ),
        );
        _remoteDescriptionSet = true;
        await _drainCandidates();
      case CallSignalType.ice:
        final candidate = RTCIceCandidate(
          asStringOrNull(signal.payload['candidate']),
          asStringOrNull(signal.payload['sdpMid']),
          asIntOrNull(signal.payload['sdpMLineIndex']),
        );
        if (pc == null || !_remoteDescriptionSet) {
          _pendingRemoteCandidates.add(candidate);
        } else {
          await pc.addCandidate(candidate);
        }
      case CallSignalType.renegotiate:
        if (_isCaller) await _startNegotiation();
      case CallSignalType.bye:
        await _finish(
          status: _connectedAt == null ? CallStatus.declined : CallStatus.ended,
          reason:
              asStringOrNull(signal.payload['reason']) ??
              (_connectedAt == null ? 'Declined' : 'Call ended'),
          notifyPeer: false,
        );
    }
  }

  Future<void> _drainCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    final queued = <RTCIceCandidate>[..._pendingRemoteCandidates];
    _pendingRemoteCandidates.clear();
    for (final candidate in queued) {
      await pc.addCandidate(candidate);
    }
  }

  void _onLocalCandidate(RTCIceCandidate candidate) {
    if (candidate.candidate == null) return;
    unawaited(
      _signal(CallSignalType.ice, <String, dynamic>{
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }),
    );
  }

  void _onRenegotiationNeeded() {
    // Only the offerer may re-offer; the answerer asks for one instead.
    if (_pc == null || state.phase == CallPhase.incoming) return;
    if (!_isCaller) return;
    if (_connectedAt == null) return;
    unawaited(_startNegotiation());
  }

  Future<void> _signal(
    CallSignalType type,
    Map<String, dynamic> payload,
  ) async {
    final call = state.call;
    if (call == null) return;
    try {
      await _api.sendCallSignal(
        callId: call.id,
        type: type,
        payload: payload,
        recipientId: _peerId,
      );
    } on KlectError {
      // A single dropped candidate is survivable; a dropped offer surfaces as
      // a connection failure, which the state machine already handles.
    }
  }

  // ────────────────────────────────────────────────────────── connectivity ──

  void _onConnectionState(RTCPeerConnectionState connection) {
    switch (connection) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        if (_closing) return;
        _enterActive();
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        if (_closing) return;
        if (_transition(CallPhase.reconnecting)) {
          _beginReconnect();
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        if (_closing) return;
        if (_transition(CallPhase.reconnecting)) {
          _beginReconnect();
          return;
        }
        // A failure before the call ever connected has no `active` to return
        // to, so `reconnecting` is not on the table: the negotiation is over.
        if (state.phase == CallPhase.connecting) {
          unawaited(
            _finish(
              status: CallStatus.failed,
              reason: 'Call failed',
              notifyPeer: true,
            ),
          );
        }
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (_closing) return;
        unawaited(
          _finish(
            status: _connectedAt == null ? CallStatus.failed : CallStatus.ended,
            reason: 'Connection closed',
            notifyPeer: false,
          ),
        );
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        if (_connectedAt == null && state.phase != CallPhase.incoming) {
          // The caller stays at `dialing` until the callee answers, so this is
          // a no-op there; for the callee it confirms `connecting`.
          _transition(_isCaller ? CallPhase.dialing : CallPhase.connecting);
        }
    }
  }

  /// Takes the connected peer connection into [CallPhase.active].
  ///
  /// Requirement 7.3: elapsed duration starts at zero at that transition. A
  /// caller whose peer connection jumps straight from `dialing` to connected
  /// still takes the `connecting` hop, so the edge set holds (7.9).
  void _enterActive() {
    _reconnectDeadlineTimer?.cancel();
    _iceRestartTimer?.cancel();
    _remoteFrameTimer?.cancel();
    _reconnectDeadlineTimer = null;
    _iceRestartTimer = null;
    _remoteFrameTimer = null;
    _reconnectingSince = null;
    _iceRestarts = 0;

    final phase = state.phase;
    if (phase == CallPhase.dialing || phase == CallPhase.incoming) {
      if (!_transition(CallPhase.connecting)) return;
    }

    final firstConnect = _connectedAt == null;
    if (!_transition(CallPhase.active)) return;
    // Requirement 7.3: elapsed starts at zero *at* the transition into
    // `active`, so the write happens only once the edge has been taken. A
    // `reconnecting → active` hop keeps the duration it had accumulated.
    state = firstConnect
        ? state.copyWith(elapsed: Duration.zero, clearError: true)
        : state.copyWith(clearError: true);

    if (firstConnect) {
      _connectedAt = DateTime.now();
      _ringTimer?.cancel();
      _ringTimer = null;
      _startElapsed();
      unawaited(_markActive());
    }
  }

  /// Starts one bounded reconnect period without touching either media stream.
  ///
  /// Repeated disconnected or failed reports while already reconnecting are
  /// harmless: the original deadline stays authoritative and no second restart
  /// chain is created.
  void _beginReconnect() {
    if (_reconnectingSince != null || state.phase != CallPhase.reconnecting) {
      return;
    }
    _reconnectingSince = DateTime.now();
    _iceRestarts = 0;
    _reconnectDeadlineTimer = Timer(
      KlectCallTimings.reconnectTimeout,
      () => unawaited(
        _finish(
          status: CallStatus.failed,
          reason: state.relayAvailable
              ? 'Lost connection'
              : 'Lost connection — no relay server is configured',
          notifyPeer: true,
        ),
      ),
    );
    _scheduleIceRestart();
  }

  void _scheduleIceRestart() {
    if (state.phase != CallPhase.reconnecting || _iceRestarts >= 3) return;
    _iceRestartTimer?.cancel();
    _iceRestartTimer = Timer(
      KlectCallTimings.reconnectGrace,
      () => unawaited(_attemptIceRestart()),
    );
  }

  Future<void> _attemptIceRestart() async {
    _iceRestartTimer = null;
    final pc = _pc;
    if (pc == null || _closing || state.phase != CallPhase.reconnecting) {
      return;
    }
    if (pc.connectionState ==
        RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      _enterActive();
      return;
    }
    if (_iceRestarts >= 3) return;
    _iceRestarts += 1;
    try {
      // Existing local and remote tracks remain attached throughout the whole
      // reconnect window; only ICE is restarted.
      await pc.restartIce();
      if (_isCaller) await _startNegotiation();
    } catch (_) {
      // The shared deadline remains in force; a later attempt may still heal.
    }
    _scheduleIceRestart();
  }

  /// Arms the ring budget for the row the engine currently holds.
  ///
  /// Requirement 7.5: the deadline is `createdAt + ringTimeout`, so arming late
  /// shortens the timer rather than restarting it.
  void _armRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(
      ringTimeoutRemaining(state.call?.createdAt, now: DateTime.now()),
      () => unawaited(_ringTimedOut()),
    );
  }

  /// Requirement 7.5: an unanswered call ends missed with its tracks released.
  ///
  /// Only the caller may write the `missed` outcome — the server refuses
  /// `p_outcome = 'missed'` from anyone else (`bad_missed_transition`) — so the
  /// callee ends locally and lets the caller's own budget write the row. Either
  /// way exactly one `end_call` is issued for the call id (7.11).
  Future<void> _ringTimedOut() async {
    final phase = state.phase;
    if (phase != CallPhase.dialing && phase != CallPhase.incoming) return;
    await _finish(
      status: CallStatus.missed,
      reason: 'No answer',
      notifyPeer: _isCaller,
      writeRow: _isCaller,
    );
  }

  /// Requirement 7.15: media that never connects within 30 s of entering
  /// `connecting` ends the call `failed` with a zero elapsed duration — a call
  /// that never became `active` has none to report.
  Future<void> _connectTimedOut() async {
    if (state.phase != CallPhase.connecting) return;
    await _finish(
      status: CallStatus.failed,
      reason: 'Could not connect',
      notifyPeer: true,
    );
  }

  void _startElapsed() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(KlectCallTimings.elapsedTick, (_) {
      final since = _connectedAt;
      if (since == null) return;
      state = state.copyWith(elapsed: DateTime.now().difference(since));
    });
  }

  Future<void> _markActive() async {
    final call = state.call;
    if (call == null) return;
    try {
      await _api.joinCall(call.id);
    } on KlectError {
      // The row is bookkeeping; a failure here must not drop live media.
    }
  }

  void _onCallRow(Map<String, dynamic> row) {
    final status = CallStatus.parse(row['status']);
    if (status.isLive) return;
    if (_closing || state.phase == CallPhase.ended) return;
    unawaited(
      _finish(
        status: status,
        reason: _describe(status),
        notifyPeer: false,
        writeRow: false,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────── ending ──

  /// The one way out of a live call — every termination path lands here.
  ///
  /// The phase is written and the media released **before** any RPC leaves the
  /// device, so `ended` is reached within 1 second of the activation regardless
  /// of whether `decline_call` / `end_call` succeed, fail or hang
  /// (Requirements 7.4, 7.8). `_closing` plus `ended` absorption means at most
  /// one `end_call` is issued per call id (7.11) — and a repeat would be a
  /// server-side no-op anyway.
  Future<void> _finish({
    required CallStatus status,
    required bool notifyPeer,
    String? reason,
    bool writeRow = true,
  }) async {
    if (_closing) return;
    // Nothing to end: `ended` is absorbing (7.10) and `idle` holds no call.
    if (state.phase == CallPhase.ended || state.phase == CallPhase.idle) return;
    _closing = true;

    final call = state.call;
    // Requirement 7.8: whole seconds counted from the transition into `active`,
    // zero where the call never became `active`, clamped to a day. A
    // diagnostic, not an authority — `end_call` computes the stored duration
    // from `calls.started_at`.
    final elapsedSeconds = clientElapsedSeconds(
      _connectedAt == null
          ? Duration.zero
          : DateTime.now().difference(_connectedAt!),
    );

    if (_transition(CallPhase.ended, endReason: reason ?? _describe(status))) {
      state = state.copyWith(elapsed: Duration(seconds: elapsedSeconds));
    }
    // Requirements 7.4, 7.5, 7.8, 7.14: every local audio and video track is
    // released on every termination path, before the network work.
    await _shutdown();

    try {
      if (notifyPeer && call != null) {
        await _signal(CallSignalType.bye, <String, dynamic>{'reason': ?reason});
      }

      if (call != null && writeRow) {
        try {
          await _api.updateCallStatus(
            call.id,
            status,
            clientElapsedSeconds: elapsedSeconds,
            endReason: reason,
          );
        } catch (_) {
          // Best effort — the phase is already `ended` and the media path is
          // already down, so a refused or slow RPC changes nothing here.
        }
      }

      if (call != null) {
        try {
          await _api.leaveCall(call.id);
        } catch (_) {
          // Best effort.
        }
      }
    } finally {
      // Released so a *later* call can end; this call id cannot re-enter
      // because `ended` absorbs it.
      _closing = false;
    }
  }

  Future<void> _shutdown() async {
    _ringTimer?.cancel();
    _connectTimer?.cancel();
    _elapsedTimer?.cancel();
    _reconnectDeadlineTimer?.cancel();
    _iceRestartTimer?.cancel();
    _ringTimer = null;
    _connectTimer = null;
    _elapsedTimer = null;
    _reconnectDeadlineTimer = null;
    _iceRestartTimer = null;

    final signals = _signals;
    final calls = _calls;
    _signals = null;
    _calls = null;
    if (signals != null) await _api.removeChannel(signals);
    if (calls != null) await _api.removeChannel(calls);

    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await _quietly(track.stop);
      }
      await _quietly(stream.dispose);
    }
    _remoteStream = null;

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      await _quietly(pc.close);
      await _quietly(pc.dispose);
    }

    final local = state.localRenderer;
    final remote = state.remoteRenderer;
    state = state.copyWith(
      clearRenderers: true,
      hasRemoteVideo: false,
      clearRemoteFrameStale: true,
    );
    if (local != null) {
      local.srcObject = null;
      await _quietly(local.dispose);
    }
    if (remote != null) {
      remote.srcObject = null;
      await _quietly(remote.dispose);
    }

    _pendingRemoteCandidates.clear();
    _appliedSignals.clear();
    _remoteDescriptionSet = false;
    _iceRestarts = 0;
    _reconnectingSince = null;
    _connectedAt = null;
  }

  Future<void> _resolvePeer(String conversationId) async {
    _conversationId = conversationId;
    final me = _me;
    try {
      final members = await _api.fetchMembers(conversationId);
      for (final member in members) {
        if (member.userId == me) continue;
        _peerId = member.userId;
        if (member.profile != null) {
          state = state.copyWith(peer: member.profile);
        }
        return;
      }
    } on KlectError {
      // The name is cosmetic; the call still works without it.
    }
  }

  /// The conversation this call belongs to, for the "back to chat" affordance.
  String? get conversationId => _conversationId ?? state.call?.conversationId;

  static String _describe(CallStatus status) => switch (status) {
    CallStatus.ended => 'Call ended',
    CallStatus.missed => 'No answer',
    CallStatus.declined => 'Declined',
    CallStatus.failed => 'Call failed',
    CallStatus.ringing => 'Ringing',
    CallStatus.active => 'In call',
  };

  /// Teardown must never throw: the native layer happily reports "already
  /// closed" as an error, and by then we no longer care.
  static Future<void> _quietly(Future<void> Function() body) async {
    try {
      await body();
    } catch (_) {
      // Intentionally ignored.
    }
  }
}

/// The one call the app can be in.
final activeCallProvider =
    NotifierProvider<ActiveCallController, ActiveCallState>(
      ActiveCallController.new,
      name: 'activeCall',
    );
