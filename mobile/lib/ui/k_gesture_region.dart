import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/motion.dart';

/// **The gesture contract** (`docs/DESIGN_SYSTEM.md` §4), with no double-tap
/// penalty.
///
/// | gesture | callback |
/// |---|---|
/// | single tap | [onTap] — fires the instant the finger lifts |
/// | double tap | [onDoubleTap] — a second tap inside [window] |
/// | long press | [onLongPress] — the radial peek |
///
/// A naive `onTap` + `onDoubleTap` pair makes Flutter wait ~260ms on *every*
/// single tap to find out whether a second one is coming, and that delay is
/// exactly what makes an app feel cheap. So we do not use `onDoubleTap` at all.
///
/// Instead: the first tap fires [onTap] immediately and *optimistically* — the
/// closeup starts opening — while a [window] timer runs. If a second tap
/// arrives inside the window we call [onDoubleTap], and the caller escalates
/// (typically by replacing the just-pushed closeup with the immersive viewer).
/// If the window elapses quietly, [onTapSettled] confirms the single tap.
///
/// The user perceives zero delay, and the double tap still works.
class KGestureRegion extends StatefulWidget {
  /// Wraps [child] in the KLECT gesture contract.
  const KGestureRegion({
    required this.child,
    super.key,
    this.onTap,
    this.onDoubleTap,
    this.onTapSettled,
    this.onLongPress,
    this.window = KMotion.doubleTapWindow,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
    this.semanticLabel,
  });

  /// What to render.
  final Widget child;

  /// Fires on the first tap-up, with no delay. Start the closeup here.
  final VoidCallback? onTap;

  /// Fires when a second tap lands inside [window]. Escalate to immersive.
  final VoidCallback? onDoubleTap;

  /// Fires when [window] elapses with no second tap — the single tap is now
  /// definitive. Use it for anything that must *not* be undone by an
  /// escalation (analytics, `record_view`).
  final VoidCallback? onTapSettled;

  /// The radial quick-action peek: like · save · repost · share · report.
  final VoidCallback? onLongPress;

  /// How long a second tap may arrive.
  final Duration window;

  /// When false the region is inert.
  final bool enabled;

  /// Hit-test behaviour.
  final HitTestBehavior behavior;

  /// Announced by screen readers.
  final String? semanticLabel;

  @override
  State<KGestureRegion> createState() => _KGestureRegionState();
}

class _KGestureRegionState extends State<KGestureRegion> {
  Timer? _timer;
  bool _awaitingSecondTap = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.enabled) return;

    if (_awaitingSecondTap) {
      // Second tap inside the window: escalate.
      _timer?.cancel();
      _awaitingSecondTap = false;
      widget.onDoubleTap?.call();
      return;
    }

    // First tap: act now, decide later.
    _awaitingSecondTap = true;
    widget.onTap?.call();
    _timer?.cancel();
    _timer = Timer(widget.window, () {
      if (!mounted) return;
      _awaitingSecondTap = false;
      widget.onTapSettled?.call();
    });
  }

  void _handleLongPress() {
    if (!widget.enabled) return;
    _timer?.cancel();
    _awaitingSecondTap = false;
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: widget.semanticLabel,
        button: widget.onTap != null,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: GestureDetector(
          behavior: widget.behavior,
          onTap: _handleTap,
          onLongPress:
              widget.onLongPress == null ? null : _handleLongPress,
          child: widget.child,
        ),
      );
}
