import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feedback/interaction_feedback.dart';
import '../design/motion.dart';
import '../design/theme.dart';

/// Renders concise action outcomes in the app's top-right corner.
///
/// Accepted taps receive platform feedback at the control itself. This host
/// only presents follow confirmations and queued/failed social outcomes.
class KInteractionFeedbackHost extends ConsumerStatefulWidget {
  /// Wraps the app router with the global outcome presentation layer.
  const KInteractionFeedbackHost({required this.child, super.key});

  /// The application below the floating status pill.
  final Widget child;

  @override
  ConsumerState<KInteractionFeedbackHost> createState() =>
      _KInteractionFeedbackHostState();
}

class _KInteractionFeedbackHostState
    extends ConsumerState<KInteractionFeedbackHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  InteractionFeedbackEvent? _event;
  String? _signature;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: KDurations.base,
      reverseDuration: KDurations.fast,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _show(InteractionFeedbackEvent event) {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == AppLifecycleState.paused ||
        lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.detached) {
      return;
    }

    final content = _contentFor(event);
    if (content == null) return;
    final signature = '${event.id}:${event.result.name}';
    if (_signature == signature) return;

    _timer?.cancel();
    setState(() {
      _event = event;
      _signature = signature;
    });
    unawaited(_controller.forward(from: 0));
    _timer = Timer(content.dwell, () => unawaited(_dismiss()));
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    final signature = _signature;
    await _controller.reverse();
    if (!mounted || signature != _signature) return;
    setState(() {
      _event = null;
      _signature = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<InteractionFeedbackEvent?>(interactionFeedbackProvider, (
      previous,
      next,
    ) {
      if (next != null) _show(next);
    });

    final event = _event;
    final content = event == null ? null : _contentFor(event);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (content != null)
          _InteractionStatusPill(
            content: content,
            animation: _controller,
            onDismiss: () => unawaited(_dismiss()),
          ),
      ],
    );
  }
}

@immutable
class _ToastContent {
  const _ToastContent({
    required this.title,
    required this.icon,
    required this.tone,
    required this.dwell,
  });

  final String title;
  final IconData icon;
  final _ToastTone tone;
  final Duration dwell;
}

enum _ToastTone { success, neutral, like, save, repost, warning, error }

const Duration _successDwell = Duration(milliseconds: 1800);
const Duration _attentionDwell = Duration(milliseconds: 2600);

_ToastContent? _contentFor(InteractionFeedbackEvent event) {
  if (event.result == InteractionFeedbackResult.intent) return null;
  if (event.result == InteractionFeedbackResult.confirmed &&
      event.action != InteractionFeedbackAction.follow) {
    return null;
  }

  final active = event.active != false;
  final name = event.targetLabel?.trim().isNotEmpty == true
      ? event.targetLabel!.trim()
      : 'this collector';

  if (event.action == InteractionFeedbackAction.follow) {
    return switch (event.result) {
      InteractionFeedbackResult.confirmed =>
        active
            ? _ToastContent(
                title: 'Following $name',
                icon: Icons.check_rounded,
                tone: _ToastTone.success,
                dwell: _successDwell,
              )
            : _ToastContent(
                title: 'Unfollowed $name',
                icon: Icons.remove_rounded,
                tone: _ToastTone.neutral,
                dwell: _successDwell,
              ),
      InteractionFeedbackResult.queued => _ToastContent(
        title: '${active ? 'Follow' : 'Unfollow'} queued \u00b7 $name',
        icon: Icons.schedule_rounded,
        tone: _ToastTone.warning,
        dwell: _attentionDwell,
      ),
      InteractionFeedbackResult.failed => _ToastContent(
        title:
            '${active ? 'Couldn\u2019t follow' : 'Couldn\u2019t unfollow'} $name',
        icon: Icons.error_outline_rounded,
        tone: _ToastTone.error,
        dwell: _attentionDwell,
      ),
      InteractionFeedbackResult.intent => throw StateError('Filtered above'),
    };
  }

  if (event.result == InteractionFeedbackResult.queued) {
    return switch (event.action) {
      InteractionFeedbackAction.like => _ToastContent(
        title: active ? 'Like queued' : 'Unlike queued',
        icon: Icons.schedule_rounded,
        tone: _ToastTone.like,
        dwell: _attentionDwell,
      ),
      InteractionFeedbackAction.save => _ToastContent(
        title: active ? 'Save queued' : 'Remove save queued',
        icon: Icons.schedule_rounded,
        tone: _ToastTone.save,
        dwell: _attentionDwell,
      ),
      InteractionFeedbackAction.repost => _ToastContent(
        title: active ? 'Repost queued' : 'Undo repost queued',
        icon: Icons.schedule_rounded,
        tone: _ToastTone.repost,
        dwell: _attentionDwell,
      ),
      InteractionFeedbackAction.follow => throw StateError('Handled above'),
    };
  }

  if (event.result == InteractionFeedbackResult.failed) {
    return switch (event.action) {
      InteractionFeedbackAction.like => _ToastContent(
        title: active ? 'Couldn\u2019t like this' : 'Couldn\u2019t unlike this',
        icon: Icons.error_outline_rounded,
        tone: _ToastTone.error,
        dwell: _attentionDwell,
      ),
      InteractionFeedbackAction.save => _ToastContent(
        title: active
            ? 'Couldn\u2019t save this'
            : 'Couldn\u2019t remove this save',
        icon: Icons.error_outline_rounded,
        tone: _ToastTone.error,
        dwell: _attentionDwell,
      ),
      InteractionFeedbackAction.repost => _ToastContent(
        title: active
            ? 'Couldn\u2019t repost this'
            : 'Couldn\u2019t undo the repost',
        icon: Icons.error_outline_rounded,
        tone: _ToastTone.error,
        dwell: _attentionDwell,
      ),
      InteractionFeedbackAction.follow => throw StateError('Handled above'),
    };
  }

  return null;
}

class _InteractionStatusPill extends StatelessWidget {
  const _InteractionStatusPill({
    required this.content,
    required this.animation,
    required this.onDismiss,
  });

  final _ToastContent content;
  final Animation<double> animation;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final reduced = KMotion.reduced(context);
    final accent = switch (content.tone) {
      _ToastTone.success => colors.semanticSuccess,
      _ToastTone.neutral => colors.textSecondary,
      _ToastTone.like => colors.actionLike,
      _ToastTone.save => colors.actionSave,
      _ToastTone.repost => colors.actionRepost,
      _ToastTone.warning => colors.semanticWarning,
      _ToastTone.error => colors.semanticDanger,
    };
    final subtle = switch (content.tone) {
      _ToastTone.like => colors.actionLikeSubtle,
      _ToastTone.save => colors.actionSaveSubtle,
      _ToastTone.repost => colors.actionRepostSubtle,
      _ToastTone.error => colors.semanticDangerSubtle,
      _ => colors.accentSubtle,
    };
    final fade = CurvedAnimation(
      parent: animation,
      curve: reduced ? KCurves.linear : KCurves.emphasized,
      reverseCurve: KCurves.accelerate,
    );
    final motion = CurvedAnimation(
      parent: animation,
      curve: reduced ? KCurves.linear : KCurves.overshoot,
      reverseCurve: KCurves.accelerate,
    );

    final pill = Semantics(
      liveRegion: true,
      container: true,
      label: content.title,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey<String>('interaction-feedback-pill'),
          constraints: const BoxConstraints(maxWidth: Layout.readableMaxWidth),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s3,
            vertical: Space.s2,
          ),
          decoration: BoxDecoration(
            color: colors.surface3,
            borderRadius: BorderRadius.circular(Radii.full),
            border: Border.all(
              color: accent.withValues(alpha: Opacities.disabled),
              width: Strokes.thin,
            ),
            boxShadow: KlectTheme.shadow(Elevation.high),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: Space.s6,
                height: Space.s6,
                decoration: BoxDecoration(
                  color: subtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(content.icon, size: Space.s4, color: accent),
              ),
              const SizedBox(width: Space.s2),
              Flexible(
                child: Text(
                  content.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.kt.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final animated = FadeTransition(
      opacity: fade,
      child: reduced
          ? pill
          : SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.14, -0.18),
                end: Offset.zero,
              ).animate(motion),
              child: pill,
            ),
    );

    return Positioned(
      top:
          MediaQuery.viewPaddingOf(context).top +
          Layout.topBarHeight +
          Space.s2,
      left: Space.s3,
      right: Space.s3,
      child: Align(
        alignment: Alignment.topRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            triggerInteractionTapFeedback(context);
            onDismiss();
          },
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) < -80) onDismiss();
          },
          onHorizontalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0).abs() > 80) onDismiss();
          },
          child: animated,
        ),
      ),
    );
  }
}
