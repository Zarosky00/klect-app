import 'package:flutter/material.dart';

import '../design/theme.dart';
import 'k_pressable.dart';

/// A filter chip, a tag, or a small piece of metadata.
class KChip extends StatelessWidget {
  /// Creates a chip.
  const KChip({
    required this.label,
    super.key,
    this.icon,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.tint,
    this.dense = false,
  });

  /// Chip text. Tags are rendered with a leading `#` by the caller.
  final String label;

  /// Optional leading glyph.
  final IconData? icon;

  /// Selected chips take the oxblood accent.
  final bool selected;

  /// Tap handler.
  final VoidCallback? onTap;

  /// When set, renders a trailing ✕.
  final VoidCallback? onRemove;

  /// Overrides the selected tint — e.g. a match-score colour.
  final Color? tint;

  /// Tighter padding for inline metadata rows.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final accent = tint ?? colors.accentDefault;
    final foreground = selected ? accent : colors.textSecondary;
    final background = selected ? colors.accentSubtle : colors.surface2;
    final border = selected ? accent : colors.borderSubtle;

    final content = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? Space.s2 : Space.s3,
        vertical: dense ? Space.s1 : Space.s15,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.full),
        border: Border.all(color: border, width: Strokes.thin),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: Space.s4, color: foreground),
            const SizedBox(width: Space.s1),
          ],
          Text(
            label,
            style: context.kt.label.copyWith(color: foreground),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (onRemove != null) ...<Widget>[
            const SizedBox(width: Space.s1),
            KPressable(
              enforceMinTapTarget: false,
              semanticLabel: 'Remove $label',
              onTap: onRemove,
              child: Icon(
                Icons.close_rounded,
                size: Space.s4,
                color: foreground,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: selected ? '$label, selected' : label,
      child: content,
    );
  }
}
