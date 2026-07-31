import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/k_pressable.dart';
import '../../../ui/k_tab_pager.dart';

/// One action revealed by swiping a row.
class SwipeAction {
  /// Creates a swipe action.
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tint,
    this.destructive = false,
  });

  /// The glyph.
  final IconData icon;

  /// Announced by screen readers and drawn under the glyph.
  final String label;

  /// What it does.
  final VoidCallback onPressed;

  /// Overrides the fill; defaults to `surface3`, or `semantic.danger` when
  /// [destructive].
  final Color? tint;

  /// Destructive actions take the danger colour and ask before running.
  final bool destructive;
}

/// Swipe a row leftwards to reveal its actions.
///
/// "Hidden but easily accessible": the inbox shows nothing but the
/// conversation at rest, and mute / archive / delete are one gesture away.
/// The drag is finger-driven, so it settles on a spring — never a curve.
///
/// Every action is also reachable from the row's long-press sheet, because a
/// swipe is not discoverable and is impossible for a switch-control user.
class KSwipeActions extends StatefulWidget {
  /// Wraps [child] in a swipeable row.
  const KSwipeActions({
    required this.child,
    required this.actions,
    super.key,
    this.enabled = true,
  });

  /// The row itself.
  final Widget child;

  /// Up to three actions, drawn right to left.
  final List<SwipeAction> actions;

  /// When false the row does not move.
  final bool enabled;

  @override
  State<KSwipeActions> createState() => _KSwipeActionsState();
}

class _KSwipeActionsState extends State<KSwipeActions>
    with SingleTickerProviderStateMixin {
  static const double _actionWidth = Space.s16;

  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
  );

  double get _extent => widget.actions.length * _actionWidth;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _settle(double target, {double velocity = 0}) {
    if (KMotion.reduced(context)) {
      _controller.value = target;
      return;
    }
    _controller.animateWith(
      SpringSimulation(
        KMotion.spring(Springs.snappy),
        _controller.value,
        target,
        velocity,
      ),
    );
  }

  void _close() => _settle(0);

  void _onDragUpdate(DragUpdateDetails details) {
    final next = _controller.value - details.primaryDelta!;
    _controller.value = next.clamp(0.0, _extent);
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = -details.velocity.pixelsPerSecond.dx;
    final shouldOpen =
        velocity > _actionWidth || _controller.value > _extent / 2;
    _settle(shouldOpen ? _extent : 0, velocity: velocity);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.actions.isEmpty) return widget.child;
    final colors = context.kc;

    return KHorizontalDragClaimRegion(
      child: GestureDetector(
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final revealed = _controller.value.clamp(0.0, _extent);
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ClipRect(
                      child: SizedBox(
                        width: revealed,
                        child: OverflowBox(
                          alignment: Alignment.centerRight,
                          maxWidth: _extent,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              for (final action in widget.actions)
                                _ActionButton(
                                  action: action,
                                  width: _actionWidth,
                                  onTap: () {
                                    _close();
                                    action.onPressed();
                                  },
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(-revealed, 0),
                  child: ColoredBox(color: colors.bgBase, child: child),
                ),
              ],
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    required this.width,
    required this.onTap,
  });

  final SwipeAction action;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final background =
        action.tint ??
        (action.destructive ? colors.semanticDangerSubtle : colors.surface2);
    final foreground = action.destructive
        ? colors.semanticDanger
        : colors.textSecondary;

    return Semantics(
      button: true,
      label: action.label,
      excludeSemantics: true,
      child: KPressable(
        enforceMinTapTarget: false,
        onTap: onTap,
        child: Container(
          width: width,
          color: background,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(action.icon, size: Space.s5, color: foreground),
              const SizedBox(height: Space.s1),
              Text(
                action.label,
                style: context.kt.micro.copyWith(color: foreground),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
