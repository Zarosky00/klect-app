import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feedback/interaction_feedback.dart';
import '../design/motion.dart';
import '../design/theme.dart';

/// Renders contextual, two-line toasts for interaction outcomes.
///
/// Intent events are tactile only. Confirmed likes/saves/reposts stay visual
/// and sonic; follow confirmations plus queued/failed outcomes earn a toast.
class KInteractionFeedbackHost extends ConsumerStatefulWidget {
  /// Wraps the app router with the global feedback presentation layer.
  const KInteractionFeedbackHost({required this.child, super.key});

  /// The application below the floating toast.
  final Widget child;

  @override
  ConsumerState<KInteractionFeedbackHost> createState() =>
      _KInteractionFeedbackHostState();
}

class _KInteractionFeedbackHostState
    extends ConsumerState<KInteractionFeedbackHost>
    with SingleTickerProviderStateMixin {
  static const Duration _dwell = Duration(milliseconds: 3200);

  late final AnimationController _controller;
  Timer? _timer;
  InteractionFeedbackEvent? _event;
  String? _signature;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: KDurations.medium,
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
    _timer = Timer(_dwell, () => unawaited(_dismiss()));
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
          _InteractionToast(
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
    required this.body,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String body;
  final IconData icon;
  final _ToastTone tone;
}

enum _ToastTone { follow, like, save, repost, warning, error }

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
                title: 'You’re following $name',
                body: 'Their new shelves and posts can now reach your Pulse.',
                icon: Icons.person_add_alt_1_rounded,
                tone: _ToastTone.follow,
              )
            : _ToastContent(
                title: '$name left your Pulse',
                body: 'You won’t see new activity unless you follow again.',
                icon: Icons.person_remove_alt_1_rounded,
                tone: _ToastTone.warning,
              ),
      InteractionFeedbackResult.queued => _ToastContent(
        title: active ? 'Follow queued for $name' : 'Unfollow queued for $name',
        body: 'We’ll finish this when you’re back online.',
        icon: Icons.cloud_sync_rounded,
        tone: _ToastTone.warning,
      ),
      InteractionFeedbackResult.failed => _ToastContent(
        title: active ? 'Couldn’t follow $name' : 'Couldn’t unfollow $name',
        body: 'Nothing changed. Check your connection and try again.',
        icon: Icons.person_off_outlined,
        tone: _ToastTone.error,
      ),
      InteractionFeedbackResult.intent => throw StateError('Filtered above'),
    };
  }

  if (event.result == InteractionFeedbackResult.queued) {
    return switch (event.action) {
      InteractionFeedbackAction.like => _ToastContent(
        title: active ? 'Like saved for later' : 'Unlike saved for later',
        body: 'We’ll finish it when you’re back online.',
        icon: Icons.cloud_sync_rounded,
        tone: _ToastTone.like,
      ),
      InteractionFeedbackAction.save => _ToastContent(
        title: active ? 'Shelf save queued' : 'Shelf removal queued',
        body: 'We’ll finish it when you’re back online.',
        icon: Icons.cloud_sync_rounded,
        tone: _ToastTone.save,
      ),
      InteractionFeedbackAction.repost => _ToastContent(
        title: active ? 'Repost queued' : 'Undo repost queued',
        body: 'We’ll finish it when you’re back online.',
        icon: Icons.cloud_sync_rounded,
        tone: _ToastTone.repost,
      ),
      _ => null,
    };
  }

  if (event.result == InteractionFeedbackResult.failed) {
    return switch (event.action) {
      InteractionFeedbackAction.like => _ToastContent(
        title: active ? 'That like didn’t stick' : 'Couldn’t remove the like',
        body: 'We restored the previous state. Try again.',
        icon: Icons.heart_broken_outlined,
        tone: _ToastTone.error,
      ),
      InteractionFeedbackAction.save => _ToastContent(
        title: active ? 'Couldn’t save this' : 'Couldn’t remove this save',
        body: 'Your shelf is unchanged. Try again.',
        icon: Icons.bookmark_remove_outlined,
        tone: _ToastTone.error,
      ),
      InteractionFeedbackAction.repost => _ToastContent(
        title: active ? 'Couldn’t repost this' : 'Couldn’t undo the repost',
        body: 'Your Pulse is unchanged. Try again.',
        icon: Icons.sync_problem_rounded,
        tone: _ToastTone.error,
      ),
      _ => null,
    };
  }

  return null;
}

class _InteractionToast extends StatelessWidget {
  const _InteractionToast({
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
      _ToastTone.follow => colors.semanticSuccess,
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

    final card = Semantics(
      liveRegion: true,
      container: true,
      label: '${content.title}. ${content.body}',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(maxWidth: Layout.readableMaxWidth),
          padding: const EdgeInsets.all(Space.s3),
          decoration: BoxDecoration(
            color: colors.surface3,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(
              color: accent.withValues(alpha: Opacities.disabled),
              width: Strokes.thin,
            ),
            boxShadow: KlectTheme.shadow(Elevation.high),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: Space.s10,
                height: Space.s10,
                decoration: BoxDecoration(
                  color: subtle,
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(content.icon, size: Space.s5, color: accent),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      content.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.kt.bodyStrong,
                    ),
                    const SizedBox(height: Space.s05),
                    Text(
                      content.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.kt.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: Space.s5,
                color: colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(
            Space.s4,
            Space.s4,
            Space.s4,
            Space.s20,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) > 80) onDismiss();
              },
              child: FadeTransition(
                opacity: fade,
                child: reduced
                    ? card
                    : SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.22),
                          end: Offset.zero,
                        ).animate(motion),
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.97,
                            end: 1,
                          ).animate(motion),
                          child: card,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
