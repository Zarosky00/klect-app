import 'package:flutter/material.dart';

import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../chat_models.dart';

/// The three-dot "someone is typing" bubble.
///
/// Fed entirely by Realtime **broadcast** — nothing about typing is ever
/// written to a table, so it costs one websocket frame and no rows.
///
/// Under reduced motion the dots stop travelling and hold at full opacity: the
/// signal survives, the movement does not.
class TypingIndicator extends StatefulWidget {
  /// Creates a typing indicator.
  const TypingIndicator({required this.typing, super.key});

  /// Everyone currently typing, excluding the viewer.
  final List<TypingUser> typing;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  static const int _dots = 3;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.deliberate * 2,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _label {
    final names = widget.typing.map((user) => user.name).toList();
    if (names.isEmpty) return '';
    if (names.length == 1) return '${names.first} is typing';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing';
    return '${names.length} people are typing';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.typing.isEmpty) return const SizedBox.shrink();
    final colors = context.kc;
    final reduced = KMotion.reduced(context);

    return Semantics(
      liveRegion: true,
      label: _label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(
          left: Space.s4,
          right: Space.s4,
          bottom: Space.s2,
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s3,
                vertical: Space.s2,
              ),
              decoration: BoxDecoration(
                color: colors.surface2,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(Radii.lg),
                  topRight: Radius.circular(Radii.lg),
                  bottomRight: Radius.circular(Radii.lg),
                  bottomLeft: Radius.circular(Radii.xs),
                ),
                border: Border.all(
                  color: colors.borderSubtle,
                  width: Strokes.thin,
                ),
              ),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (var index = 0; index < _dots; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          right: index == _dots - 1 ? 0 : Space.s1,
                        ),
                        child: Opacity(
                          opacity:
                              reduced ? 1 : _opacityFor(index, _controller.value),
                          child: Container(
                            width: Space.s15,
                            height: Space.s15,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Space.s2),
            Flexible(
              child: Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.kt.caption.copyWith(color: colors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A travelling wave: each dot lags the one before it by a third of a cycle.
  static double _opacityFor(int index, double t) {
    final phase = (t + index / _dots) % 1;
    final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    return Opacities.disabled + (1 - Opacities.disabled) * wave;
  }
}
