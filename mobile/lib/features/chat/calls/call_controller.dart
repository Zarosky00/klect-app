import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../../core/api/api_error.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../chat_api.dart';
import 'call_config.dart';

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

  /// `mm:ss`, the in-call timer.
  String get formattedElapsed {
    final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = elapsed.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

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
    Duration? elapsed,
    RTCVideoRenderer? localRenderer,
    RTCVideoRenderer? remoteRenderer,
    String? endReason,
    Object? error,
    bool clearError = false,
    bool clearRenderers = false,
  }) =>
      ActiveCallState(
        call: call ?? this.call,
        phase: phase ?? this.phase,
        peer: peer ?? this.peer,
        micEnabled: micEnabled ?? this.micEnabled,
        cameraEnabled: cameraEnabled ?? this.cameraEnabled,
        speakerOn: speakerOn ?? this.speakerOn,
        frontCamera: frontCamera ?? this.frontCamera,
        hasRemoteVideo: hasRemoteVideo ?? this.hasRemoteVideo,
        elapsed: elapsed ?? this.elapsed,
        localRenderer:
            clearRenderers ? null : (localRenderer ?? this.localRenderer),
        remoteRenderer:
            clearRenderers ? null : (remoteRenderer ?? this.remoteRenderer),
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
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RealtimeChannel? _signals;
  RealtimeChannel? _calls;

  Timer? _ringTimer;
  Timer? _elapsedTimer;
  Timer? _reconnectTimer;

  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  final Set<String> _appliedSignals = <String>{};

  bool _isCaller = false;
  bool _remoteDescriptionSet = false;
  bool _closing = false;
  bool _restartedIce = false;
  DateTime? _connectedAt;
  String? _peerId;
  String? _conversationId;

  ChatApi get _api => ref.read(chatApiProvider);

  String? get _me => ref.read(currentUserIdProvider);

  @override
  ActiveCallState build() {
    ref.onDispose(() => unawaited(_shutdown()));
    return const ActiveCallState();
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
    try {
      final call = await _api.createCall(
        conversationId: conversationId,
        kind: kind,
      );
      _isCaller = true;
      _conversationId = conversationId;
      state = ActiveCallState(
        call: call,
        phase: CallPhase.dialing,
        peer: peer,
        cameraEnabled: kind == CallKind.video,
        speakerOn: kind == CallKind.video,
      );
      await _resolvePeer(conversationId);
      await _openMedia(kind: kind);
      _watch(call);
      await _startNegotiation();
      _armRingTimeout();
      return call;
    } catch (error) {
      state = state.copyWith(
        phase: CallPhase.ended,
        error: KlectError.from(error),
        endReason: 'Could not start the call',
      );
      await _shutdown();
      return null;
    }
  }

  /// Registers an incoming call so the UI can offer accept/decline.
  Future<void> present(CallModel call) async {
    if (state.isBusy) return;
    _isCaller = false;
    _conversationId = call.conversationId;
    state = ActiveCallState(
      call: call,
      phase: CallPhase.incoming,
      cameraEnabled: call.kind == CallKind.video,
      speakerOn: call.kind == CallKind.video,
    );
    await _resolvePeer(call.conversationId);
  }

  /// Answers the call currently being presented.
  ///
  /// Permissions must already have been granted — see `CallPermissions`.
  Future<void> accept() async {
    final call = state.call;
    if (call == null || state.phase != CallPhase.incoming) return;
    try {
      state = state.copyWith(phase: CallPhase.connecting);
      await _openMedia(kind: call.kind);
      _watch(call);
      await _api.joinCall(call.id);
      // Replay whatever the caller already sent, then keep listening.
      await _drainStoredSignals(call.id);
    } catch (error) {
      state = state.copyWith(error: KlectError.from(error));
      await _finish(
        status: CallStatus.failed,
        reason: 'Could not connect',
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
    try {
      final call = await _api.fetchCall(callId);
      if (call == null) {
        state = state.copyWith(
          phase: CallPhase.ended,
          endReason: 'That call no longer exists',
        );
        return;
      }
      if (!call.status.isLive) {
        state = ActiveCallState(
          call: call,
          phase: CallPhase.ended,
          endReason: _describe(call.status),
        );
        await _resolvePeer(call.conversationId);
        return;
      }
      if (call.createdBy == _me) {
        // Our own outgoing call, resumed after the screen was popped.
        _isCaller = true;
        _conversationId = call.conversationId;
        state = ActiveCallState(
          call: call,
          phase: CallPhase.dialing,
          cameraEnabled: call.kind == CallKind.video,
          speakerOn: call.kind == CallKind.video,
        );
        await _resolvePeer(call.conversationId);
        return;
      }
      await present(call);
    } catch (error) {
      state = state.copyWith(
        phase: CallPhase.ended,
        error: KlectError.from(error),
        endReason: 'Could not open that call',
      );
    }
  }

  /// Clears an ended call so the UI can go back to idle.
  void dismiss() {
    if (state.phase != CallPhase.ended) return;
    state = const ActiveCallState();
  }

  // ─────────────────────────────────────────────────────────────── controls ──

  /// Mutes or unmutes the microphone.
  Future<void> toggleMic() async {
    final next = !state.micEnabled;
    for (final track in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = next;
    }
    state = state.copyWith(micEnabled: next);
  }

  /// Switches between the loudspeaker and the earpiece.
  Future<void> toggleSpeaker() async {
    final next = !state.speakerOn;
    try {
      await Helper.setSpeakerphoneOn(next);
      state = state.copyWith(speakerOn: next);
    } catch (_) {
      // Desktop and web have no earpiece; leave the flag where it was.
    }
  }

  /// Turns the camera on or off mid-call, renegotiating if a video track has
  /// to be created for the first time.
  Future<void> toggleCamera() async {
    final stream = _localStream;
    if (stream == null) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) {
      await _upgradeToVideo();
      return;
    }
    final next = !state.cameraEnabled;
    for (final track in videoTracks) {
      track.enabled = next;
    }
    state = state.copyWith(cameraEnabled: next);
  }

  /// Flips between the front and rear cameras.
  Future<void> switchCamera() async {
    final tracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
      state = state.copyWith(frontCamera: !state.frontCamera);
    } catch (_) {
      // Single-camera device.
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

  Future<void> _openMedia({required CallKind kind}) async {
    final local = RTCVideoRenderer();
    final remote = RTCVideoRenderer();
    await local.initialize();
    await remote.initialize();

    final stream = await navigator.mediaDevices.getUserMedia(
      KlectCallIce.mediaConstraints(video: kind == CallKind.video),
    );
    _localStream = stream;
    local.srcObject = stream;

    final pc = await createPeerConnection(await KlectCallIce.resolve());
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
    );

    try {
      await Helper.setSpeakerphoneOn(kind == CallKind.video);
    } catch (_) {
      // Not every platform has a speakerphone toggle.
    }
  }

  Future<void> _upgradeToVideo() async {
    final pc = _pc;
    final stream = _localStream;
    if (pc == null || stream == null) return;
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
    } catch (error) {
      state = state.copyWith(error: KlectError.from(error));
    }
  }

  void _onRemoteTrack(RTCTrackEvent event, RTCVideoRenderer remote) {
    if (event.streams.isEmpty) return;
    _remoteStream = event.streams.first;
    remote.srcObject = _remoteStream;
    if (event.track.kind == 'video') {
      state = state.copyWith(hasRemoteVideo: true, remoteRenderer: remote);
    } else {
      state = state.copyWith(remoteRenderer: remote);
    }
  }

  // ──────────────────────────────────────────────────────────── signalling ──

  void _watch(CallModel call) {
    _signals = _api.callSignalsChannel(
      callId: call.id,
      onSignal: (row) => unawaited(_applySignal(CallSignal.fromJson(row))),
    )..subscribe();

    _calls = _api.callChannel(
      callId: call.id,
      onUpdate: _onCallRow,
    )..subscribe();
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
          reason: asStringOrNull(signal.payload['reason']) ??
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
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _restartedIce = false;
        if (_connectedAt == null) {
          _connectedAt = DateTime.now();
          _ringTimer?.cancel();
          _ringTimer = null;
          _startElapsed();
          unawaited(_markActive());
        }
        state = state.copyWith(phase: CallPhase.active, clearError: true);
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        if (_closing) return;
        state = state.copyWith(phase: CallPhase.reconnecting);
        _armReconnect(KlectCallTimings.reconnectGrace);
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        if (_closing) return;
        state = state.copyWith(phase: CallPhase.reconnecting);
        _armReconnect(Duration.zero);
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
          state = state.copyWith(
            phase: _isCaller ? CallPhase.dialing : CallPhase.connecting,
          );
        }
    }
  }

  void _armReconnect(Duration grace) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(grace, () async {
      final pc = _pc;
      if (pc == null || _closing) return;
      if (pc.connectionState ==
          RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        return;
      }
      if (!_restartedIce) {
        _restartedIce = true;
        try {
          await pc.restartIce();
          if (_isCaller) await _startNegotiation();
        } catch (_) {
          // Fall through to the failure timer.
        }
        _reconnectTimer = Timer(
          KlectCallTimings.reconnectTimeout,
          () => unawaited(
            _finish(
              status: CallStatus.failed,
              reason: KlectCallIce.hasTurn
                  ? 'Lost connection'
                  : 'Lost connection — no relay server is configured',
              notifyPeer: true,
            ),
          ),
        );
        return;
      }
      await _finish(
        status: CallStatus.failed,
        reason: 'Lost connection',
        notifyPeer: true,
      );
    });
  }

  void _armRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = Timer(
      KlectCallTimings.ringTimeout,
      () => unawaited(
        _finish(
          status: CallStatus.missed,
          reason: 'No answer',
          notifyPeer: true,
        ),
      ),
    );
  }

  void _startElapsed() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final since = _connectedAt;
      if (since == null) return;
      state = state.copyWith(elapsed: DateTime.now().difference(since));
    });
  }

  Future<void> _markActive() async {
    final call = state.call;
    if (call == null) return;
    try {
      await _api.updateCallStatus(call.id, CallStatus.active);
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

  Future<void> _finish({
    required CallStatus status,
    required bool notifyPeer,
    String? reason,
    bool writeRow = true,
  }) async {
    if (_closing) return;
    _closing = true;

    final call = state.call;
    final duration = _connectedAt == null
        ? 0
        : DateTime.now().difference(_connectedAt!).inSeconds;

    if (notifyPeer && call != null) {
      await _signal(CallSignalType.bye, <String, dynamic>{'reason': ?reason});
    }

    if (call != null && writeRow) {
      try {
        await _api.updateCallStatus(
          call.id,
          status,
          durationSeconds: duration,
          endReason: reason,
        );
      } on KlectError {
        // Best effort — the media path is already down.
      }
    }

    if (call != null) {
      try {
        await _api.leaveCall(call.id);
      } on KlectError {
        // Best effort.
      }
      // The call log belongs in the conversation, so write it there. Only the
      // side that decided writes it, or the thread would show two markers.
      if (writeRow) {
        unawaited(
          _writeCallEvent(call: call, status: status, duration: duration),
        );
      }
    }

    state = state.copyWith(
      phase: CallPhase.ended,
      endReason: reason ?? _describe(status),
      elapsed: Duration(seconds: duration),
    );
    await _shutdown();
    _closing = false;
  }

  Future<void> _writeCallEvent({
    required CallModel call,
    required CallStatus status,
    required int duration,
  }) async {
    final label = switch (status) {
      CallStatus.ended => call.kind == CallKind.video
          ? 'Video call · ${_formatDuration(duration)}'
          : 'Call · ${_formatDuration(duration)}',
      CallStatus.missed =>
        call.kind == CallKind.video ? 'Missed video call' : 'Missed call',
      CallStatus.declined => 'Call declined',
      CallStatus.failed => 'Call failed',
      CallStatus.ringing || CallStatus.active => 'Call',
    };
    try {
      await _api.sendMessage(
        conversationId: call.conversationId,
        body: label,
        kind: MessageKind.callEvent,
        callId: call.id,
      );
    } on KlectError {
      // A missing marker must never break hanging up.
    }
  }

  Future<void> _shutdown() async {
    _ringTimer?.cancel();
    _elapsedTimer?.cancel();
    _reconnectTimer?.cancel();
    _ringTimer = null;
    _elapsedTimer = null;
    _reconnectTimer = null;

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
    state = state.copyWith(clearRenderers: true, hasRemoteVideo: false);
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
    _restartedIce = false;
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

  static String _formatDuration(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final rest = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$rest';
  }
}

/// The one call the app can be in.
final activeCallProvider =
    NotifierProvider<ActiveCallController, ActiveCallState>(
  ActiveCallController.new,
  name: 'activeCall',
);
