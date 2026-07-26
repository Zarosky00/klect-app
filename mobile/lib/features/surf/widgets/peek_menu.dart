import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// The long-press **peek**: like · save · repost · share · report, fanned out
/// around a blown-up preview of the card you are holding.
///
/// This is the third leg of the gesture contract (`docs/DESIGN_SYSTEM.md` §4)
/// and the reason a Surf tile shows no buttons at rest — the most common
/// action is one gesture away, the rest are two, nothing is three.
abstract final class KPeekMenu {
  /// Opens the peek over the whole app.
  ///
  /// Returns when the peek closes. The toggles it fires go through the
  /// optimistic engine, so the underlying card is already correct by the time
  /// the peek has finished dismissing.
  static Future<void> show(
    BuildContext context, {
    required EntityRef entity,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? blurhash,
    double? aspectRatio,
  }) {
    unawaited(HapticFeedback.mediumImpact());
    return Navigator.of(context, rootNavigator: true).push<void>(
      _PeekRoute(
        entity: entity,
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        blurhash: blurhash,
        aspectRatio: aspectRatio,
        scrim: KlectTheme.of(context).colors.surfaceScrim,
      ),
    );
  }
}

class _PeekRoute extends PopupRoute<void> {
  _PeekRoute({
    required this.entity,
    required this.scrim,
    this.title,
    this.subtitle,
    this.imageUrl,
    this.blurhash,
    this.aspectRatio,
  });

  final EntityRef entity;
  final Color scrim;
  final String? title;
  final String? subtitle;
  final String? imageUrl;
  final String? blurhash;
  final double? aspectRatio;

  @override
  Color get barrierColor => scrim;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'Dismiss quick actions';

  @override
  Duration get transitionDuration => KDurations.medium;

  @override
  Duration get reverseTransitionDuration => KDurations.fast;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      _PeekBody(
        entity: entity,
        animation: animation,
        title: title,
        subtitle: subtitle,
        imageUrl: imageUrl,
        blurhash: blurhash,
        aspectRatio: aspectRatio,
      );
}

class _PeekAction {
  const _PeekAction({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.color,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
}

class _PeekBody extends ConsumerWidget {
  const _PeekBody({
    required this.entity,
    required this.animation,
    this.title,
    this.subtitle,
    this.imageUrl,
    this.blurhash,
    this.aspectRatio,
  });

  final EntityRef entity;
  final Animation<double> animation;
  final String? title;
  final String? subtitle;
  final String? imageUrl;
  final String? blurhash;
  final double? aspectRatio;

  /// How far the outermost action sits below the middle one. A fan, not a row.
  static const double _arcDepth = Space.s5;

  /// Fraction of the entrance each action's spring is offset by.
  static const double _stagger = 0.08;

  Future<void> _share(BuildContext context) async {
    Navigator.of(context).pop();
    final url = KlectLinks.urlFor(entity.type, entity.id);
    final label = title;
    await SharePlus.instance.share(
      ShareParams(text: label == null ? url : '$label\n$url', subject: label),
    );
  }

  void _report(BuildContext context) {
    // Take the navigator's own context before popping: this route's context is
    // about to deactivate, and the report sheet has to outlive the peek.
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(
      KReportSheet.showForEntity(
        navigator.context,
        type: entity.type,
        entityId: entity.id,
        subjectLabel: title,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final social = ref.watch(interactionProvider(entity));
    final controller = ref.read(interactionProvider(entity).notifier);
    final reduced = KMotion.reduced(context);

    void close() => Navigator.of(context).pop();

    final actions = <_PeekAction>[
      _PeekAction(
        icon: Icons.favorite_border_rounded,
        activeIcon: Icons.favorite_rounded,
        label: social.liked ? 'Liked' : 'Like',
        color: colors.actionLike,
        active: social.liked,
        onTap: () {
          unawaited(controller.toggleLike());
          close();
        },
      ),
      _PeekAction(
        icon: Icons.bookmark_border_rounded,
        activeIcon: Icons.bookmark_rounded,
        label: social.saved ? 'Saved' : 'Save',
        color: colors.actionSave,
        active: social.saved,
        onTap: () {
          unawaited(controller.toggleSave());
          close();
        },
      ),
      _PeekAction(
        icon: Icons.repeat_rounded,
        activeIcon: Icons.repeat_on_rounded,
        label: social.reposted ? 'Reposted' : 'Repost',
        color: colors.actionRepost,
        active: social.reposted,
        onTap: () {
          unawaited(controller.toggleRepost());
          close();
        },
      ),
      _PeekAction(
        icon: Icons.ios_share_rounded,
        activeIcon: Icons.ios_share_rounded,
        label: 'Share',
        color: colors.actionShare,
        onTap: () => unawaited(_share(context)),
      ),
      _PeekAction(
        icon: Icons.flag_outlined,
        activeIcon: Icons.flag_rounded,
        label: 'Report',
        color: colors.semanticDanger,
        onTap: () => _report(context),
      ),
    ];

    final curved = CurvedAnimation(
      parent: animation,
      curve: reduced ? KCurves.linear : KCurves.emphasized,
      reverseCurve: KCurves.accelerate,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: close,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: Blurs.sheet, sigmaY: Blurs.sheet),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: curved,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: Layout.readableMaxWidth,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _PeekPreview(
                      animation: curved,
                      reduced: reduced,
                      imageUrl: imageUrl,
                      blurhash: blurhash,
                      aspectRatio: aspectRatio,
                    ),
                    if (title != null) ...<Widget>[
                      const SizedBox(height: Space.s4),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: Space.s6),
                        child: Text(
                          title!,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.title3,
                        ),
                      ),
                    ],
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: Space.s1),
                      Text(
                        subtitle!,
                        style:
                            text.caption.copyWith(color: colors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: Space.s8),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: Space.s4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (var index = 0;
                              index < actions.length;
                              index++)
                            _PeekActionButton(
                              action: actions[index],
                              animation: animation,
                              reduced: reduced,
                              arcOffset: _arcOffsetFor(index, actions.length),
                              delay: index * _stagger,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static double _arcOffsetFor(int index, int count) {
    if (count <= 1) return 0;
    final t = index / (count - 1) * 2 - 1;
    return _arcDepth * t * t;
  }
}

class _PeekPreview extends StatelessWidget {
  const _PeekPreview({
    required this.animation,
    required this.reduced,
    this.imageUrl,
    this.blurhash,
    this.aspectRatio,
  });

  final Animation<double> animation;
  final bool reduced;
  final String? imageUrl;
  final String? blurhash;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final preview = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width - Space.s20,
        maxHeight: MediaQuery.sizeOf(context).height / 2,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xl),
          boxShadow: KlectTheme.shadow(Elevation.high),
          color: colors.surface2,
        ),
        child: KBlurhashImage(
          url: imageUrl,
          blurhash: blurhash,
          aspectRatio: aspectRatio ?? Aspect.cover,
          borderRadius: BorderRadius.circular(Radii.xl),
        ),
      ),
    );

    if (reduced) return preview;
    return ScaleTransition(
      scale: Tween<double>(begin: KMotion.pressScale, end: 1).animate(
        CurvedAnimation(parent: animation, curve: KCurves.overshoot),
      ),
      child: preview,
    );
  }
}

class _PeekActionButton extends StatelessWidget {
  const _PeekActionButton({
    required this.action,
    required this.animation,
    required this.reduced,
    required this.arcOffset,
    required this.delay,
  });

  final _PeekAction action;
  final Animation<double> animation;
  final bool reduced;
  final double arcOffset;
  final double delay;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = action.active ? action.color : colors.textPrimary;

    final button = KPressable(
      onTap: action.onTap,
      semanticLabel: action.label,
      enforceMinTapTarget: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: Layout.tapTargetMin,
            height: Layout.tapTargetMin,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: action.active ? action.color : colors.surface3,
              border: Border.all(
                color: action.active ? action.color : colors.borderDefault,
                width: Strokes.thin,
              ),
            ),
            child: Icon(
              action.active ? action.activeIcon : action.icon,
              size: Space.s5,
              color: action.active ? colors.textOnAccent : tint,
            ),
          ),
          const SizedBox(height: Space.s15),
          Text(
            action.label,
            style: context.kt.micro.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );

    if (reduced) {
      return FadeTransition(opacity: animation, child: button);
    }

    final start = delay.clamp(0.0, 0.6);
    final curve = CurvedAnimation(
      parent: animation,
      curve: Interval(start, 1, curve: KCurves.overshoot),
      reverseCurve: KCurves.accelerate,
    );

    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, arcOffset - (1 - curve.value) * Space.s8),
          child: Transform.scale(scale: curve.value, child: child),
        ),
      ),
      child: button,
    );
  }
}
