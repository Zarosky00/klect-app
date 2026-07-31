import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/klect_api.dart';
import '../../core/feedback/interaction_feedback.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import 'calls/call_config.dart';
import 'calls/call_controller.dart';
import 'calls/call_permissions.dart';
import 'calls/incoming_call_controller.dart';

/// How long the ended card lingers before the screen closes itself.
///
/// Dwell time, not motion — the same category as `KToast.dwell`, which is why
/// it is a named constant here rather than a design token.
const Duration _dismissDelay = Duration(milliseconds: 1400);

/// The in-call screen.
///
/// Audio and video over `flutter_webrtc`, signalled entirely through Supabase
/// Realtime. Everything visible here reads [ActiveCallController]; the screen
/// owns no call state of its own, so navigating away and back — or arriving by
/// deep link — resumes the same call.
class CallScreen extends ConsumerStatefulWidget {
  /// Creates the call screen.
  const CallScreen({required this.callId, super.key});

  /// Route parameter.
  final String callId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with WidgetsBindingObserver {
  Timer? _dismissTimer;
  bool _controlsVisible = true;
  String? _phaseAnnouncement;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(activeCallProvider.notifier).attach(widget.callId));
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    ref.read(activeCallProvider.notifier).handleAppLifecycle(lifecycle);
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(_dismissDelay, () {
      if (!mounted) return;
      ref.read(activeCallProvider.notifier).dismiss();
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(Routes.messages);
      }
    });
  }

  Future<void> _accept() async {
    final call = ref.read(activeCallProvider).call;
    if (call == null) return;
    final granted = await CallPermissions.request(
      context,
      kind: call.kind,
      outgoing: false,
    );
    if (!mounted) return;
    if (granted != CallPermissionResult.granted) {
      await ref.read(activeCallProvider.notifier).decline();
      return;
    }
    ref.read(incomingCallProvider.notifier).clear();
    await ref.read(activeCallProvider.notifier).accept();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final state = ref.watch(activeCallProvider);

    ref.listen(activeCallProvider.select((s) => s.phase), (_, phase) {
      if (phase == CallPhase.ended) _scheduleDismiss();
      if (!mounted) return;
      setState(() {
        _controlsVisible = true;
        _phaseAnnouncement = _phaseLabel(phase);
      });
    });

    return KScaffold(
      backgroundColor: colors.bgSunken,
      safeTop: false,
      safeBottom: false,
      // System back leaves the call running; only the explicit end control
      // hangs up. The shell exposes the retained session through CallPill.
      canPop: true,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!state.isVideo || state.phase != CallPhase.active) return;
          triggerInteractionTapFeedback(context);
          setState(() => _controlsVisible = !_controlsVisible);
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _Stage(state: state),
            _Scrim(visible: state.isVideo && state.hasRemoteVideo),
            Semantics(
              liveRegion: true,
              label: _phaseAnnouncement,
              child: const SizedBox.shrink(),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  _Header(state: state, visible: _controlsVisible),
                  const Spacer(),
                  ExcludeSemantics(
                    excluding: !_controlsVisible,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1 : 0,
                      duration: KMotion.duration(context, KDurations.base),
                      curve: Curves_.emphasized,
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: switch (state.phase) {
                          CallPhase.incoming => _IncomingControls(
                            onAccept: () => unawaited(_accept()),
                            onDecline: () => unawaited(
                              ref.read(activeCallProvider.notifier).decline(),
                            ),
                            isVideo: state.isVideo,
                          ),
                          CallPhase.ended => _EndedControls(
                            state: state,
                            onDone: () {
                              _dismissTimer?.cancel();
                              ref.read(activeCallProvider.notifier).dismiss();
                              if (context.canPop()) {
                                context.pop();
                              } else {
                                context.go(Routes.messages);
                              }
                            },
                          ),
                          _ => _InCallControls(state: state),
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stage extends ConsumerStatefulWidget {
  const _Stage({required this.state});

  final ActiveCallState state;

  @override
  ConsumerState<_Stage> createState() => _StageState();
}

class _StageState extends ConsumerState<_Stage> {
  Offset? _previewOffset;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final colors = context.kc;
    final remote = state.remoteRenderer;
    final local = state.localRenderer;
    final staleSince = state.remoteFrameStaleSince;
    final stale =
        staleSince != null &&
        DateTime.now().difference(staleSince) >=
            KlectCallTimings.remoteFrameTimeout;
    final showRemoteVideo =
        state.isVideo && state.hasRemoteVideo && remote != null && !stale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = MediaQuery.paddingOf(context);
        const previewWidth = Space.s24;
        const previewHeight = Space.s24 * 4 / 3;
        const minX = Space.s4;
        final minY = padding.top + Space.s4;
        final maxX = (constraints.maxWidth - previewWidth - Space.s4).clamp(
          minX,
          double.infinity,
        );
        final maxY =
            (constraints.maxHeight - padding.bottom - previewHeight - Space.s4)
                .clamp(minY, double.infinity);
        final initial = Offset(maxX, padding.top + Space.s16);
        final preview = _previewOffset ?? initial;
        final clamped = Offset(
          preview.dx.clamp(minX, maxX),
          preview.dy.clamp(minY, maxY),
        );

        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (showRemoteVideo)
              RTCVideoView(
                remote,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              ColoredBox(
                color: colors.bgSunken,
                child: _PeerPortrait(state: state),
              ),
            if (state.isVideo && state.cameraEnabled && local != null)
              Positioned(
                left: clamped.dx,
                top: clamped.dy,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    setState(() {
                      final next = clamped + details.delta;
                      _previewOffset = Offset(
                        next.dx.clamp(minX, maxX),
                        next.dy.clamp(minY, maxY),
                      );
                    });
                  },
                  child: _LocalPreview(
                    renderer: local,
                    mirror: state.frontCamera,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PeerPortrait extends ConsumerWidget {
  const _PeerPortrait({required this.state});

  final ActiveCallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final peer = state.peer;
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(peer?.avatarPath, bucket: StorageBucket.avatars);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          KAvatar(size: Space.s24, imageUrl: avatarUrl, name: peer?.name),
          const SizedBox(height: Space.s5),
          Text(
            peer?.name ?? 'KLECT call',
            style: context.kt.display3,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s2),
          Text(
            _statusFor(state),
            // While active the status line is the timer, so it takes the
            // tabular count style and stops jittering as the digits change.
            style:
                (state.phase == CallPhase.active
                        ? context.kt.count
                        : context.kt.body)
                    .copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _LocalPreview extends StatelessWidget {
  const _LocalPreview({required this.renderer, required this.mirror});

  final RTCVideoRenderer renderer;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      width: Space.s24,
      height: Space.s24 * 4 / 3,
      decoration: BoxDecoration(
        color: colors.bgSunken,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderStrong, width: Strokes.thin),
        boxShadow: KlectTheme.shadow(Elevation.mid),
      ),
      clipBehavior: Clip.antiAlias,
      child: RTCVideoView(
        renderer,
        mirror: mirror,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    final colors = context.kc;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            colors.surfaceScrim,
            colors.surfaceScrim.withValues(alpha: 0),
            colors.surfaceScrim,
          ],
          stops: const <double>[0, 0.45, 1],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.visible});

  final ActiveCallState state;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return ExcludeSemantics(
      excluding: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: KMotion.duration(context, KDurations.base),
        curve: Curves_.emphasized,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (state.isVideo && state.hasRemoteVideo)
                      Text(
                        state.peer?.name ?? 'KLECT call',
                        style: context.kt.title3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      _statusFor(state),
                      style: context.kt.count.copyWith(
                        color: state.phase == CallPhase.reconnecting
                            ? colors.semanticWarning
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!state.relayAvailable && state.isBusy)
                Tooltip(
                  message:
                      'No relay server is available, so this call may not '
                      'connect on a restrictive carrier network.',
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: Space.s5,
                    color: colors.semanticWarning,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InCallControls extends ConsumerWidget {
  const _InCallControls({required this.state});

  final ActiveCallState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final controller = ref.read(activeCallProvider.notifier);

    Future<void> apply(
      Future<bool> Function() operation,
      String control,
    ) async {
      final applied = await operation();
      if (!applied && context.mounted) {
        KToast.error(context, '$control could not be changed.');
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s6,
        Space.s4,
        Space.s6,
        Space.s10,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _CallButton(
                icon: state.micEnabled
                    ? Icons.mic_rounded
                    : Icons.mic_off_rounded,
                label: state.micEnabled ? 'Mute' : 'Unmute',
                semanticLabel:
                    'Microphone, ${state.micEnabled ? 'on' : 'off'}, enabled',
                active: !state.micEnabled,
                onPressed: () =>
                    unawaited(apply(controller.toggleMic, 'Microphone')),
              ),
              _CallButton(
                icon: state.speakerOn
                    ? Icons.volume_up_rounded
                    : Icons.hearing_rounded,
                label: state.speakerOn ? 'Speaker' : 'Earpiece',
                semanticLabel:
                    'Speaker, ${state.speakerOn ? 'on' : 'off'}, enabled',
                active: state.speakerOn,
                onPressed: () =>
                    unawaited(apply(controller.toggleSpeaker, 'Speaker')),
              ),
              if (state.isVideo) ...<Widget>[
                _CallButton(
                  icon: state.cameraEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: state.cameraEnabled ? 'Camera on' : 'Camera off',
                  semanticLabel:
                      'Camera, ${state.cameraEnabled ? 'on' : 'off'}, enabled',
                  active: state.cameraEnabled,
                  onPressed: () =>
                      unawaited(apply(controller.toggleCamera, 'Camera')),
                ),
                _CallButton(
                  icon: Icons.cameraswitch_rounded,
                  label: 'Flip',
                  semanticLabel: state.cameraEnabled
                      ? 'Flip camera, enabled'
                      : 'Flip camera, disabled while camera is off',
                  enabled: state.cameraEnabled,
                  onPressed: () =>
                      unawaited(apply(controller.switchCamera, 'Camera')),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.s6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _CallButton(
                icon: Icons.keyboard_arrow_down_rounded,
                label: 'Minimize',
                semanticLabel: 'Minimize call, enabled',
                onPressed: () {
                  if (context.canPop()) context.pop();
                },
              ),
              _CallButton(
                icon: Icons.call_end_rounded,
                label: 'End',
                semanticLabel: 'End call, enabled',
                size: Space.s16,
                background: colors.semanticDanger,
                foreground: colors.textInverse,
                onPressed: () => unawaited(controller.hangUp()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomingControls extends StatelessWidget {
  const _IncomingControls({
    required this.onAccept,
    required this.onDecline,
    required this.isVideo,
  });

  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s10,
        Space.s4,
        Space.s10,
        Space.s12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _CallButton(
            icon: Icons.call_end_rounded,
            label: 'Decline',
            size: Space.s16,
            background: colors.semanticDanger,
            foreground: colors.textInverse,
            onPressed: onDecline,
          ),
          _CallButton(
            icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            label: 'Answer',
            size: Space.s16,
            background: colors.semanticSuccess,
            foreground: colors.textInverse,
            onPressed: onAccept,
          ),
        ],
      ),
    );
  }
}

class _EndedControls extends StatelessWidget {
  const _EndedControls({required this.state, required this.onDone});

  final ActiveCallState state;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.s6, Space.s4, Space.s6, Space.s12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          state.endReason ?? 'Call ended',
          style: context.kt.title3,
          textAlign: TextAlign.center,
        ),
        if (state.elapsed > Duration.zero) ...<Widget>[
          const SizedBox(height: Space.s1),
          Text(
            state.formattedElapsed,
            style: context.kt.count.copyWith(color: context.kc.textSecondary),
          ),
        ],
        const SizedBox(height: Space.s5),
        KButton(
          label: 'Back to chat',
          size: KButtonSize.large,
          expand: true,
          onPressed: onDone,
        ),
      ],
    ),
  );
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.semanticLabel,
    this.active = false,
    this.enabled = true,
    this.size = Space.s14,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final String? semanticLabel;
  final VoidCallback onPressed;
  final bool active;
  final bool enabled;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final fill = background ?? (active ? colors.surface4 : colors.surface2);
    final tint =
        foreground ?? (active ? colors.textPrimary : colors.textSecondary);

    return KPressable(
      enabled: enabled,
      onTap: enabled ? onPressed : null,
      enforceMinTapTarget: false,
      semanticLabel:
          semanticLabel ?? '$label, ${enabled ? 'enabled' : 'disabled'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedContainer(
            duration: KMotion.duration(context, KDurations.fast),
            curve: Curves_.emphasized,
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fill,
              border: Border.all(
                color: colors.borderSubtle,
                width: Strokes.thin,
              ),
            ),
            child: Icon(icon, size: Space.s6, color: tint),
          ),
          const SizedBox(height: Space.s1),
          Text(
            label,
            style: context.kt.micro.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

String _statusFor(ActiveCallState state) => switch (state.phase) {
  CallPhase.idle => 'Connecting',
  CallPhase.dialing => 'Ringing…',
  CallPhase.incoming => state.isVideo ? 'Incoming video call' : 'Incoming call',
  CallPhase.connecting => 'Connecting…',
  CallPhase.active => state.formattedElapsed,
  CallPhase.reconnecting => 'Reconnecting…',
  CallPhase.ended => state.endReason ?? 'Call ended',
};

String _phaseLabel(CallPhase phase) => switch (phase) {
  CallPhase.idle => 'Call idle',
  CallPhase.dialing => 'Call ringing',
  CallPhase.incoming => 'Incoming call',
  CallPhase.connecting => 'Call connecting',
  CallPhase.active => 'Call active',
  CallPhase.reconnecting => 'Call reconnecting',
  CallPhase.ended => 'Call ended',
};
