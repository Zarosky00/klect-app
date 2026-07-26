import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/motion.dart';
import '../../design/theme.dart';

/// Where a match score sits on the four-stop match ramp.
///
/// The thresholds are product data, not design values — the *colours* they
/// resolve to are the tokens `match.low/mid/high/peak`.
abstract final class MatchScale {
  /// At or above this, the ramp reaches oxblood.
  static const int peak = 85;

  /// At or above this, mint.
  static const int high = 65;

  /// At or above this, azure.
  static const int mid = 40;

  /// Resolves [percent] onto the match colour ramp.
  static Color colorFor(KlectColors colors, int percent) {
    if (percent >= peak) return colors.matchPeak;
    if (percent >= high) return colors.matchHigh;
    if (percent >= mid) return colors.matchMid;
    return colors.matchLow;
  }

  /// A one-word reading of the score, so colour is never the only signal.
  static String labelFor(int percent) {
    if (percent >= peak) return 'Twin taste';
    if (percent >= high) return 'Strong overlap';
    if (percent >= mid) return 'Some overlap';
    return 'A little overlap';
  }
}

/// A circular meter around an avatar, showing taste overlap.
///
/// The arc sweeps in once on the `emphasized` curve; under reduced motion it
/// is simply drawn at its final value — the information stays, the travel goes.
class MatchRing extends StatefulWidget {
  /// Creates a ring around [child].
  const MatchRing({
    required this.percent,
    required this.child,
    super.key,
    this.size = Space.s16,
    this.strokeWidth = Strokes.thick,
  });

  /// Overlap score, 0–100.
  final int percent;

  /// Usually a `KAvatar`.
  final Widget child;

  /// Outer diameter of the ring.
  final double size;

  /// Ring thickness.
  final double strokeWidth;

  @override
  State<MatchRing> createState() => _MatchRingState();
}

class _MatchRingState extends State<MatchRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.slow,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void didUpdateWidget(MatchRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.percent != widget.percent) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = MatchScale.colorFor(colors, widget.percent);
    final reduced = KMotion.reduced(context);
    final animation = reduced
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(parent: _controller, curve: Curves_.emphasized);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Semantics(
        label: '${widget.percent} percent taste match, '
            '${MatchScale.labelFor(widget.percent)}',
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) => CustomPaint(
            painter: _RingPainter(
              progress: widget.percent / 100 * animation.value,
              tint: tint,
              track: colors.borderSubtle,
              strokeWidth: widget.strokeWidth,
            ),
            child: child,
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.strokeWidth + Space.s15),
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.tint,
    required this.track,
    required this.strokeWidth,
  });

  final double progress;
  final Color tint;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0) return;
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = tint;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.tint != tint ||
      oldDelegate.track != track ||
      oldDelegate.strokeWidth != strokeWidth;
}
