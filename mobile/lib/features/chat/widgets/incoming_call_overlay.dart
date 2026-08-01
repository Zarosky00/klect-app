import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../calls/call_controller.dart';
import '../calls/call_notifications.dart';
import '../calls/call_permissions.dart';
import '../calls/incoming_call_controller.dart';
import 'call_pill.dart';

/// Wraps a subtree so an incoming call can appear over it.
///
/// Mount this as high as you can — around the tab shell — and a call rings
/// wherever the user happens to be. The chat screens mount it themselves so
/// the feature is complete on its own; wrapping the shell as well costs
/// nothing (the banner only ever renders once, because
/// [incomingCallProvider] holds a single call).
class CallOverlayHost extends ConsumerWidget {
  /// Wraps [child].
  const CallOverlayHost({required this.child, required this.router, super.key});

  /// The subtree the banner floats over.
  final Widget child;

  /// The app router, passed from [MaterialApp.router] so this overlay does not
  /// try to look it up from the builder context (which sits above the router).
  final GoRouter router;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(incomingCallProvider);
    final active = ref.watch(activeCallProvider);
    final notifications = ref.watch(callNotificationsProvider)..ensureStarted();

    ref.listen<CallModel?>(incomingCallProvider, (previous, next) {
      if (next != null) {
        unawaited(
          notifications.presentIfBackgrounded(
            next,
            callerName: ref.read(activeCallProvider).peer?.name,
          ),
        );
      } else if (previous != null) {
        unawaited(notifications.cancelCall(previous.id));
      }
    });
    ref.listen(activeCallProvider.select((state) => state.phase), (_, phase) {
      final callId = ref.read(activeCallProvider).call?.id;
      if (callId != null) {
        unawaited(notifications.syncPhase(callId, phase));
      }
    });
    ref.listen<String?>(callNotificationMessageProvider, (_, message) {
      if (message == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        KToast.error(context, message);
        ref.read(callNotificationMessageProvider.notifier).clear();
      });
    });

    return AnimatedBuilder(
      animation: router.routerDelegate,
      builder: (context, _) {
        final path = router.routerDelegate.currentConfiguration.uri.path;
        final onCallRoute = path.split('/').contains('call');
        return Stack(
          children: <Widget>[
            child,
            if (active.isBusy && !onCallRoute)
              Positioned(
                left: Space.s4,
                right: Space.s4,
                bottom:
                    MediaQuery.paddingOf(context).bottom +
                    Layout.bottomBarHeight +
                    Space.s2,
                child: const CallPill(),
              ),
            if (call != null && active.phase == CallPhase.incoming)
              Positioned(
                top: MediaQuery.paddingOf(context).top + Space.s2,
                left: Space.s3,
                right: Space.s3,
                child: _IncomingCallBanner(call: call),
              ),
          ],
        );
      },
    );
  }
}

class _IncomingCallBanner extends ConsumerStatefulWidget {
  const _IncomingCallBanner({required this.call});

  final CallModel call;

  @override
  ConsumerState<_IncomingCallBanner> createState() =>
      _IncomingCallBannerState();
}

class _IncomingCallBannerState extends ConsumerState<_IncomingCallBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: KDurations.deliberate * 2,
  )..repeat();

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(HapticFeedback.mediumImpact());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final callId = widget.call.id;
    final granted = await CallPermissions.request(
      context,
      kind: widget.call.kind,
      outgoing: false,
    );
    if (!mounted) return;
    if (granted != CallPermissionResult.granted) {
      setState(() => _busy = false);
      await ref.read(activeCallProvider.notifier).decline();
      ref.read(incomingCallProvider.notifier).clear();
      return;
    }
    ref.read(incomingCallProvider.notifier).clear();
    await ref.read(activeCallProvider.notifier).accept();
    if (!mounted) return;
    unawaited(context.push('/call/$callId'));
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ref.read(activeCallProvider.notifier).decline();
    ref.read(incomingCallProvider.notifier).clear();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final text = context.kt;
    final peer = ref.watch(activeCallProvider.select((s) => s.peer));
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(peer?.avatarPath, bucket: StorageBucket.avatars);
    final isVideo = widget.call.kind == CallKind.video;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(Space.s3),
        decoration: BoxDecoration(
          color: colors.surface3,
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: colors.borderStrong, width: Strokes.thin),
          boxShadow: KlectTheme.shadow(Elevation.high),
        ),
        child: Row(
          children: <Widget>[
            _PulsingAvatar(
              pulse: _pulse,
              imageUrl: avatarUrl,
              name: peer?.name,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    peer?.name ?? 'Incoming call',
                    style: text.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    isVideo ? 'Video call' : 'Audio call',
                    style: text.caption.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            _RoundButton(
              icon: Icons.call_end_rounded,
              background: colors.semanticDanger,
              foreground: colors.textInverse,
              semanticLabel: 'Decline call',
              onPressed: _busy ? null : () => unawaited(_decline()),
            ),
            const SizedBox(width: Space.s2),
            _RoundButton(
              icon: isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              background: colors.semanticSuccess,
              foreground: colors.textInverse,
              semanticLabel: 'Answer call',
              onPressed: _busy ? null : () => unawaited(_accept()),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingAvatar extends StatelessWidget {
  const _PulsingAvatar({
    required this.pulse,
    required this.imageUrl,
    required this.name,
  });

  final Animation<double> pulse;
  final String? imageUrl;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final avatar = KAvatar(size: Space.s12, imageUrl: imageUrl, name: name);
    if (KMotion.reduced(context)) return avatar;

    return SizedBox(
      width: Space.s16,
      height: Space.s16,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final t = Curves_.decelerate.transform(pulse.value);
              return Container(
                width: Space.s12 + (Space.s4 * t),
                height: Space.s12 + (Space.s4 * t),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.accentDefault.withValues(alpha: 1 - t),
                    width: Strokes.thick,
                  ),
                ),
              );
            },
          ),
          avatar,
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => KPressable(
    enabled: onPressed != null,
    onTap: onPressed,
    enforceMinTapTarget: false,
    semanticLabel: semanticLabel,
    child: Container(
      width: Layout.tapTargetMin,
      height: Layout.tapTargetMin,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: Space.s5, color: foreground),
    ),
  );
}
