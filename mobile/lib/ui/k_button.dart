import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'k_pressable.dart';

/// The three button weights the product uses. Anything else is a [KPressable].
enum KButtonVariant {
  /// Brass fill — the user's own intent. One per screen.
  primary,

  /// Bordered, surface fill.
  secondary,

  /// No fill, no border.
  ghost,

  /// Destructive: delete, block, report.
  danger,
}

/// Button sizes.
enum KButtonSize {
  /// Inline, inside dense rows.
  small,

  /// Default.
  medium,

  /// Full-width call to action.
  large,
}

/// A KLECT button.
class KButton extends StatelessWidget {
  /// Creates a button.
  const KButton({
    required this.label,
    super.key,
    this.onPressed,
    this.variant = KButtonVariant.primary,
    this.size = KButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.busy = false,
    this.semanticLabel,
  });

  /// Text.
  final String label;

  /// Tap handler. Null disables the button.
  final VoidCallback? onPressed;

  /// Visual weight.
  final KButtonVariant variant;

  /// Height and padding ramp.
  final KButtonSize size;

  /// Leading icon.
  final IconData? icon;

  /// Trailing icon.
  final IconData? trailingIcon;

  /// Stretches to the parent's width.
  final bool expand;

  /// Shows a spinner and blocks input.
  final bool busy;

  /// Screen-reader override.
  final String? semanticLabel;

  double get _height => switch (size) {
        KButtonSize.small => Space.s8,
        KButtonSize.medium => Space.s12,
        KButtonSize.large => Space.s14,
      };

  double get _horizontalPadding => switch (size) {
        KButtonSize.small => Space.s3,
        KButtonSize.medium => Space.s5,
        KButtonSize.large => Space.s6,
      };

  double get _radius => switch (size) {
        KButtonSize.small => Radii.sm,
        KButtonSize.medium => Radii.md,
        KButtonSize.large => Radii.lg,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final enabled = onPressed != null && !busy;

    final (Color background, Color foreground, Color border) =
        switch (variant) {
      KButtonVariant.primary => (
          colors.accentDefault,
          colors.textOnAccent,
          colors.accentDefault,
        ),
      KButtonVariant.secondary => (
          colors.surface2,
          colors.textPrimary,
          colors.borderDefault,
        ),
      KButtonVariant.ghost => (
          colors.surface1.withValues(alpha: 0),
          colors.textSecondary,
          colors.surface1.withValues(alpha: 0),
        ),
      KButtonVariant.danger => (
          colors.semanticDangerSubtle,
          colors.semanticDanger,
          colors.semanticDanger,
        ),
    };

    final textStyle = (size == KButtonSize.small
            ? context.kt.label
            : context.kt.bodyStrong)
        .copyWith(color: foreground);

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (busy)
          SizedBox(
            width: Space.s4,
            height: Space.s4,
            child: CircularProgressIndicator(
              strokeWidth: Strokes.thick,
              color: foreground,
            ),
          )
        else if (icon != null)
          Icon(icon, size: Space.s5, color: foreground),
        if (busy || icon != null) const SizedBox(width: Space.s2),
        Flexible(
          child: Text(
            label,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailingIcon != null) ...<Widget>[
          const SizedBox(width: Space.s2),
          Icon(trailingIcon, size: Space.s5, color: foreground),
        ],
      ],
    );

    return KPressable(
      enabled: enabled,
      onTap: onPressed,
      semanticLabel: semanticLabel ?? label,
      enforceMinTapTarget: false,
      child: Container(
        height: _height,
        width: expand ? double.infinity : null,
        padding: EdgeInsets.symmetric(horizontal: _horizontalPadding),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(
            color: variant == KButtonVariant.ghost
                ? background
                : border,
            width: Strokes.thin,
          ),
        ),
        alignment: Alignment.center,
        child: content,
      ),
    );
  }
}

/// A square icon-only button, used in app bars and overlays.
class KIconButton extends StatelessWidget {
  /// Creates an icon button.
  const KIconButton({
    required this.icon,
    required this.semanticLabel,
    super.key,
    this.onPressed,
    this.color,
    this.background,
    this.size = Space.s5,
  });

  /// The glyph.
  final IconData icon;

  /// Required — an icon-only control must announce itself.
  final String semanticLabel;

  /// Tap handler.
  final VoidCallback? onPressed;

  /// Glyph colour. Defaults to `textSecondary`.
  final Color? color;

  /// Optional chip behind the glyph, for overlay chrome on photos.
  final Color? background;

  /// Glyph size.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: semanticLabel,
      child: Container(
        decoration: background == null
            ? null
            : BoxDecoration(color: background, shape: BoxShape.circle),
        padding: const EdgeInsets.all(Space.s25),
        child: Icon(icon, size: size, color: color ?? colors.textSecondary),
      ),
    );
  }
}
