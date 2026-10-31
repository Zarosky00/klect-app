import 'dart:async';

import 'package:flutter/material.dart';

import '../design/motion.dart';

/// Fades and lifts a list row in once, after an optional stagger [delay].
///
/// The caller decides whether a row should [animate] — typically only the
/// first build of a row it has not shown before — so scrolling back past a row
/// or rebuilding the list never replays the entrance. Under reduced motion the
/// row simply appears.
class KReveal extends StatefulWidget {
  /// Creates an entrance wrapper.
  const KReveal({
    required this.child,
    super.key,
    this.animate = true,
    this.delay = Duration.zero,
  });

  /// The row.
  final Widget child;

  /// Whether this mount plays the entrance. Read once, on first build.
  final bool animate;

  /// Stagger before the entrance starts; see [KMotion.staggerDelay].
  final Duration delay;

  @override
  State<KReveal> createState() => _KRevealState();
}

class _KRevealState extends State<KReveal> with SingleTickerProviderStateMixin {
  static final Tween<Offset> _lift = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  );

  AnimationController? _controller;
  CurvedAnimation? _curved;
  Timer? _delay;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (!widget.animate || KMotion.reduced(context)) return;
    final controller = AnimationController(
      vsync: this,
      duration: KDurations.medium,
    );
    _controller = controller;
    _curved = CurvedAnimation(parent: controller, curve: KCurves.emphasized);
    if (widget.delay <= Duration.zero) {
      unawaited(controller.forward());
    } else {
      _delay = Timer(widget.delay, () {
        if (mounted) unawaited(controller.forward());
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _curved?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = _curved;
    if (curved == null) return widget.child;
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: _lift.animate(curved),
        child: widget.child,
      ),
    );
  }
}
