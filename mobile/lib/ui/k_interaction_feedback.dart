import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/klect_api.dart';
import '../core/feedback/interaction_feedback.dart';
import '../core/models/enums.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import 'k_avatar.dart';

/// Renders follow outcomes and exceptional social-action notices above the app.
///
/// Follow outcomes use the wide avatar-backed panel from the supplied visual
/// reference. Queued and failed non-follow actions retain the smaller corner
/// treatment so routine social activity never becomes noisy.
class KInteractionFeedbackHost extends ConsumerStatefulWidget {
  /// Wraps the app router with the global outcome presentation layer.
  const KInteractionFeedbackHost({required this.child, super.key});

  /// The application below the floating outcome presentation.
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
    final avatarUrl =
        content?.presentation == _ToastPresentation.followPanel &&
            content?.avatarPath != null
        ? ref
              .watch(klectApiProvider)
              .publicUrl(content?.avatarPath, bucket: StorageBucket.avatars)
        : null;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        widget.child,
        if (content != null)
          switch (content.presentation) {
            _ToastPresentation.followPanel => _FollowOutcomePanel(
              content: content,
              avatarUrl: avatarUrl,
              animation: _controller,
              onDismiss: () => unawaited(_dismiss()),
            ),
            _ToastPresentation.compact => _InteractionStatusPill(
              content: content,
              animation: _controller,
              onDismiss: () => unawaited(_dismiss()),
            ),
          },
      ],
    );
  }
}

enum _ToastPresentation { followPanel, compact }

@immutable
class _ToastContent {
  const _ToastContent({
    required this.title,
    required this.semanticLabel,
    required this.icon,
    required this.tone,
    required this.dwell,
    required this.presentation,
    this.targetName,
    this.avatarPath,
  });

  final String title;
  final String semanticLabel;
  final IconData icon;
  final _ToastTone tone;
  final Duration dwell;
  final _ToastPresentation presentation;
  final String? targetName;
  final String? avatarPath;
}

enum _ToastTone { success, neutral, like, save, repost, warning, error }

final Duration _successDwell = KDurations.deliberate * 5;
final Duration _attentionDwell = KDurations.base * 16;

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
    final content = switch (event.result) {
      InteractionFeedbackResult.confirmed =>
        active
            ? (
                'Following! Their new shelves and posts will appear in your Pulse.',
                _ToastTone.success,
                _successDwell,
              )
            : (
                'Unfollowed. Their new activity will no longer appear in your Pulse.',
                _ToastTone.neutral,
                _successDwell,
              ),
      InteractionFeedbackResult.queued =>
        active
            ? (
                'Follow queued. We\u2019ll add their activity when you\u2019re back online.',
                _ToastTone.warning,
                _attentionDwell,
              )
            : (
                'Unfollow queued. We\u2019ll update your Pulse when you\u2019re back online.',
                _ToastTone.warning,
                _attentionDwell,
              ),
      InteractionFeedbackResult.failed =>
        active
            ? (
                'Couldn\u2019t follow $name. Nothing changed\u2014try again.',
                _ToastTone.error,
                _attentionDwell,
              )
            : (
                'Couldn\u2019t unfollow $name. Nothing changed\u2014try again.',
                _ToastTone.error,
                _attentionDwell,
              ),
      InteractionFeedbackResult.intent => throw StateError('Filtered above'),
    };

    return _ToastContent(
      title: content.$1,
      semanticLabel:
          '${active ? 'Following' : 'Unfollowed'} $name. '
          '${content.$1}',
      icon: Icons.person_rounded,
      tone: content.$2,
      dwell: content.$3,
      presentation: _ToastPresentation.followPanel,
      targetName: name,
      avatarPath: event.targetAvatarPath,
    );
  }

  if (event.result == InteractionFeedbackResult.queued) {
    return switch (event.action) {
      InteractionFeedbackAction.like => _compact(
        title: active ? 'Like queued' : 'Unlike queued',
        icon: Icons.schedule_rounded,
        tone: _ToastTone.like,
      ),
      InteractionFeedbackAction.save => _compact(
        title: active ? 'Save queued' : 'Remove save queued',
        icon: Icons.schedule_rounded,
        tone: _ToastTone.save,
      ),
      InteractionFeedbackAction.repost => _compact(
        title: active ? 'Repost queued' : 'Undo repost queued',
        icon: Icons.schedule_rounded,
        tone: _ToastTone.repost,
      ),
      InteractionFeedbackAction.follow => throw StateError('Handled above'),
    };
  }

  if (event.result == InteractionFeedbackResult.failed) {
    return switch (event.action) {
      InteractionFeedbackAction.like => _compact(
        title: active ? 'Couldn\u2019t like this' : 'Couldn\u2019t unlike this',
        icon: Icons.error_outline_rounded,
        tone: _ToastTone.error,
      ),
      InteractionFeedbackAction.save => _compact(
        title: active
            ? 'Couldn\u2019t save this'
            : 'Couldn\u2019t remove this save',
        icon: Icons.error_outline_rounded,
        tone: _ToastTone.error,
      ),
      InteractionFeedbackAction.repost => _compact(
        title: active
            ? 'Couldn\u2019t repost this'
            : 'Couldn\u2019t undo the repost',
        icon: Icons.error_outline_rounded,
        tone: _ToastTone.error,
      ),
      InteractionFeedbackAction.follow => throw StateError('Handled above'),
    };
  }

  return null;
}

_ToastContent _compact({
  required String title,
  required IconData icon,
  required _ToastTone tone,
}) => _ToastContent(
  title: title,
  semanticLabel: title,
  icon: icon,
  tone: tone,
  dwell: _attentionDwell,
  presentation: _ToastPresentation.compact,
);

class _FollowOutcomePanel extends StatelessWidget {
  const _FollowOutcomePanel({
    required this.content,
    required this.avatarUrl,
    required this.animation,
    required this.onDismiss,
  });

  final _ToastContent content;
  final String? avatarUrl;
  final Animation<double> animation;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final reduced = KMotion.reduced(context);
    final scheme = Theme.of(context).colorScheme;
    final fade = CurvedAnimation(
      parent: animation,
      curve: reduced ? KCurves.linear : KCurves.emphasized,
      reverseCurve: KCurves.accelerate,
    );
    final settle = CurvedAnimation(
      parent: animation,
      curve: reduced ? KCurves.linear : KCurves.overshoot,
      reverseCurve: KCurves.accelerate,
    );

    final panel = Material(
      type: MaterialType.transparency,
      child: Semantics(
        liveRegion: true,
        container: true,
        label: content.semanticLabel,
        child: ExcludeSemantics(
          child: Container(
            key: const ValueKey<String>('interaction-follow-panel'),
            constraints: const BoxConstraints(
              maxWidth: Layout.readableMaxWidth,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s3,
              vertical: Space.s2,
            ),
            decoration: BoxDecoration(
              color: scheme.inverseSurface,
              borderRadius: BorderRadius.circular(Radii.xl),
              boxShadow: KlectTheme.shadow(Elevation.high),
            ),
            child: Row(
              children: <Widget>[
                KAvatar(
                  imageUrl: avatarUrl,
                  name: content.targetName,
                  size: Space.s10,
                ),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Text(
                    content.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.kt.bodyStrong.copyWith(
                      color: scheme.onInverseSurface,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final animated = FadeTransition(
      opacity: fade,
      child: reduced
          ? panel
          : SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.34),
                end: Offset.zero,
              ).animate(settle),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1).animate(settle),
                child: panel,
              ),
            ),
    );

    return Positioned(
      top: MediaQuery.viewPaddingOf(context).top + Space.s3,
      left: Space.s4,
      right: Space.s4,
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
    );
  }
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

    final pill = Material(
      type: MaterialType.transparency,
      child: Semantics(
        liveRegion: true,
        container: true,
        label: content.semanticLabel,
        child: ExcludeSemantics(
          child: Container(
            key: const ValueKey<String>('interaction-feedback-pill'),
            constraints: const BoxConstraints(
              maxWidth: Layout.readableMaxWidth,
            ),
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
                    style: context.kt.label.copyWith(
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
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
