import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import 'k_pressable.dart';

/// Formats a counter the way KLECT displays them: exact under a thousand,
/// then `1.2K` / `3.4M`.
String formatCount(int value) {
  if (value < 0) return '0';
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final thousands = value / 1000;
    return thousands >= 10
        ? '${thousands.round()}K'
        : '${thousands.toStringAsFixed(1)}K';
  }
  final millions = value / 1000000;
  return millions >= 10
      ? '${millions.round()}M'
      : '${millions.toStringAsFixed(1)}M';
}

/// A count whose digits **roll** vertically when the number changes.
///
/// Never fade the whole number — that reads as a reload. Rolling one digit
/// reads as an increment, which is what actually happened.
///
/// Uses the tabular `count` type step so the pill never changes width mid-roll.
class KRollingCount extends StatefulWidget {
  /// Creates a rolling count.
  const KRollingCount({
    required this.value,
    super.key,
    this.style,
    this.duration = KDurations.base,
  });

  /// The number to show.
  final int value;

  /// Overrides the tabular count style.
  final TextStyle? style;

  /// Roll duration. Collapsed to a fade under reduced motion.
  final Duration duration;

  @override
  State<KRollingCount> createState() => _KRollingCountState();
}

class _KRollingCountState extends State<KRollingCount> {
  late int _previous = widget.value;

  @override
  void didUpdateWidget(KRollingCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _previous = oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? context.kt.count;
    final text = formatCount(widget.value);
    final reduced = KMotion.reduced(context);
    final up = widget.value >= _previous;
    final duration = KMotion.duration(context, widget.duration);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        for (var index = 0; index < text.length; index++)
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: Curves_.emphasized,
            switchOutCurve: Curves_.accelerate,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.center,
              children: <Widget>[...previous, ?current],
            ),
            transitionBuilder: reduced
                ? (child, animation) =>
                    FadeTransition(opacity: animation, child: child)
                : (child, animation) {
                    final isIncoming =
                        child.key == ValueKey<String>('$index:${text[index]}');
                    final begin = Offset(
                      0,
                      isIncoming ? (up ? 1 : -1) : (up ? -1 : 1),
                    );
                    return ClipRect(
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: begin,
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
            child: Text(
              text[index],
              key: ValueKey<String>('$index:${text[index]}'),
              style: style,
            ),
          ),
      ],
    );
  }
}

/// Icon + rolling count.
///
/// Inactive is `textSecondary`; colour appears **only** once the viewer has
/// acted, and the icon fills too — colour is never the only signal.
///
/// When [active] flips on, the icon pops to [KMotion.burstOvershoot] on the
/// `bouncy` spring and settles — the like/save burst from
/// `docs/DESIGN_SYSTEM.md` §3.
class KCountPill extends StatefulWidget {
  /// Creates a count pill.
  const KCountPill({
    required this.icon,
    required this.count,
    super.key,
    this.activeIcon,
    this.active = false,
    this.activeColor,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.showZero = true,
    this.iconSize = Space.s5,
    this.gap = Space.s15,
  });

  /// Icon shown when inactive.
  final IconData icon;

  /// Icon shown when active — usually the filled variant.
  final IconData? activeIcon;

  /// The number.
  final int count;

  /// Whether the viewer has acted.
  final bool active;

  /// The semantic action colour, e.g. `colors.actionLike`.
  final Color? activeColor;

  /// Tap handler. Null renders a read-only pill.
  final VoidCallback? onTap;

  /// Long-press handler, e.g. "who liked this".
  final VoidCallback? onLongPress;

  /// Screen-reader label, e.g. "Like, 24".
  final String? semanticLabel;

  /// When false, a zero count hides the number entirely.
  final bool showZero;

  /// Icon size.
  final double iconSize;

  /// Space between icon and number.
  final double gap;

  @override
  State<KCountPill> createState() => _KCountPillState();
}

class _KCountPillState extends State<KCountPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop;

  @override
  void initState() {
    super.initState();
    // Eager for the same reason as KPressable: dispose() must never be the
    // first thing to touch a `late final` ticker.
    _pop = AnimationController.unbounded(vsync: this, value: 1);
  }

  @override
  void didUpdateWidget(KCountPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && !KMotion.reduced(context)) {
      _pop
        ..value = KMotion.burstOvershoot
        ..animateWith(
          SpringSimulation(
            KMotion.spring(Springs.bouncy),
            KMotion.burstOvershoot,
            1,
            0,
          ),
        );
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = widget.active
        ? (widget.activeColor ?? colors.accentDefault)
        : colors.textSecondary;

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedBuilder(
          animation: _pop,
          builder: (context, child) =>
              Transform.scale(scale: _pop.value, child: child),
          child: Icon(
            widget.active ? (widget.activeIcon ?? widget.icon) : widget.icon,
            size: widget.iconSize,
            color: tint,
          ),
        ),
        if (widget.showZero || widget.count > 0) ...<Widget>[
          SizedBox(width: widget.gap),
          KRollingCount(
            value: widget.count,
            style: context.kt.count.copyWith(color: tint),
          ),
        ],
      ],
    );

    if (widget.onTap == null && widget.onLongPress == null) {
      return Semantics(
        label: widget.semanticLabel,
        excludeSemantics: widget.semanticLabel != null,
        child: row,
      );
    }

    return KPressable(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      semanticLabel: widget.semanticLabel,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s2,
          vertical: Space.s15,
        ),
        child: row,
      ),
    );
  }
}
