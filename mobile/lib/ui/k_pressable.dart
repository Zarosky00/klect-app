import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../core/feedback/interaction_feedback.dart';
import '../design/motion.dart';
import '../design/theme.dart';

/// The one press affordance in the product.
///
/// Scales to [KMotion.pressScale] on a spring — the finger is driving it, so it
/// is a spring, not a curve. Under reduced motion the travel is replaced by a
/// short opacity dip: we remove the movement, never the confirmation.
class KPressable extends StatefulWidget {
  /// Wraps [child] in press feedback.
  const KPressable({
    required this.child,
    super.key,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.enabled = true,
    this.scale = KMotion.pressScale,
    this.semanticLabel,
    this.enforceMinTapTarget = true,
    this.behavior = HitTestBehavior.opaque,
    this.feedbackEnabled = true,
  });

  /// What to render.
  final Widget child;

  /// Primary action.
  final VoidCallback? onTap;

  /// Secondary action — the peek, on cards.
  final VoidCallback? onLongPress;

  /// Escalation, where the caller wants the framework's own double-tap.
  ///
  /// For the surf-card gesture contract use `KGestureRegion` instead: it has no
  /// double-tap delay.
  final VoidCallback? onDoubleTap;

  /// When false, nothing responds and the child renders disabled.
  final bool enabled;

  /// Pressed scale. Defaults to the design-system value.
  final double scale;

  /// Announced by screen readers.
  final String? semanticLabel;

  /// Grows the hit box to the 44×44 accessibility floor.
  final bool enforceMinTapTarget;

  /// Hit-test behaviour of the underlying detector.
  final HitTestBehavior behavior;

  /// Whether accepted callbacks receive the app's native tap feedback.
  final bool feedbackEnabled;

  @override
  State<KPressable> createState() => _KPressableState();
}

class _KPressableState extends State<KPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    // Eagerly, not lazily: under reduced motion nothing ever reads the
    // controller during build, and a `late final` initialiser that first runs
    // inside dispose() throws "looking up a deactivated widget's ancestor".
    _controller = AnimationController.unbounded(vsync: this, value: 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _spring(double target) {
    if (!mounted) return;
    _controller.animateWith(
      SpringSimulation(
        KMotion.spring(Springs.snappy),
        _controller.value,
        target,
        0,
      ),
    );
  }

  void _setPressed(bool value, {required bool reduced}) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    if (!reduced) _spring(value ? widget.scale : 1);
  }

  bool get _interactive =>
      widget.enabled &&
      (widget.onTap != null ||
          widget.onLongPress != null ||
          widget.onDoubleTap != null);

  void _run(VoidCallback? callback) {
    if (!widget.enabled || callback == null) return;
    if (widget.feedbackEnabled) triggerInteractionTapFeedback(context);
    callback();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = KMotion.reduced(context);

    var content = widget.child;
    if (widget.enforceMinTapTarget) {
      content = ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: Layout.tapTargetMin,
          minHeight: Layout.tapTargetMin,
        ),
        child: Center(widthFactor: 1, heightFactor: 1, child: content),
      );
    }

    content = reduced
        ? AnimatedOpacity(
            opacity: _pressed ? Opacities.pressed : 1,
            duration: Durations.instant,
            curve: Curves_.standard,
            child: content,
          )
        : AnimatedBuilder(
            animation: _controller,
            builder: (context, child) =>
                Transform.scale(scale: _controller.value, child: child),
            child: content,
          );

    if (!widget.enabled) {
      content = Opacity(opacity: Opacities.disabled, child: content);
    }

    return Semantics(
      label: widget.semanticLabel,
      button: widget.onTap != null,
      enabled: widget.enabled,
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: _interactive
            ? (_) => _setPressed(true, reduced: reduced)
            : null,
        onTapUp: _interactive
            ? (_) => _setPressed(false, reduced: reduced)
            : null,
        onTapCancel: _interactive
            ? () => _setPressed(false, reduced: reduced)
            : null,
        onTap: widget.enabled && widget.onTap != null
            ? () => _run(widget.onTap)
            : null,
        onDoubleTap: widget.enabled && widget.onDoubleTap != null
            ? () => _run(widget.onDoubleTap)
            : null,
        onLongPress: widget.enabled && widget.onLongPress != null
            ? () => _run(widget.onLongPress)
            : null,
        child: content,
      ),
    );
  }
}
