import 'package:flutter/material.dart';

import '../design/motion.dart';

/// Applies the platform keyboard inset exactly once around bottom composition.
///
/// Screens using this widget must disable Scaffold's automatic IME resizing so
/// edge-to-edge Android devices cannot apply the same space twice or miss it.
class KKeyboardInset extends StatelessWidget {
  /// Creates a keyboard-safe region.
  const KKeyboardInset({required this.child, super.key});

  /// Content that must remain above the software keyboard.
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    key: const ValueKey<String>('k-keyboard-inset'),
    duration: KMotion.duration(context, KDurations.fast),
    curve: KMotion.curve(context, KCurves.emphasized),
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: child,
  );
}
