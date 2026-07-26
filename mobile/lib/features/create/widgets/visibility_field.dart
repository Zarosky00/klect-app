import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import 'entity_visual.dart';

/// The who-can-see-this control.
///
/// Visibility inherits **down** the hierarchy, so subcollections and items may
/// also choose "same as parent" — represented by a null value, exactly as the
/// column is.
class VisibilityField extends StatelessWidget {
  /// Creates a visibility picker.
  const VisibilityField({
    required this.value,
    required this.onChanged,
    super.key,
    this.allowInherit = false,
    this.inheritLabel = 'Same as parent',
    this.label = 'Who can see this',
    this.enabled = true,
  });

  /// Current value. Null means "inherit", which is only offered when
  /// [allowInherit] is true.
  final EntityVisibility? value;

  /// Fired with the new value.
  final ValueChanged<EntityVisibility?> onChanged;

  /// Whether the null/inherit option is offered.
  final bool allowInherit;

  /// Label for the inherit option, e.g. "Same as Anime".
  final String inheritLabel;

  /// Field label.
  final String label;

  /// Disables interaction while a save is in flight.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final options = <EntityVisibility?>[
      if (allowInherit) null,
      ...EntityVisibility.values,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: context.kt.label.copyWith(color: colors.textSecondary)),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: <Widget>[
            for (final option in options)
              KChip(
                label: EntityVisual.visibilityLabel(
                  option,
                  inheritLabel: inheritLabel,
                ),
                icon: EntityVisual.visibilityIcon(option),
                selected: option == value,
                onTap: enabled ? () => onChanged(option) : null,
              ),
          ],
        ),
        const SizedBox(height: Space.s2),
        Text(
          EntityVisual.visibilityHint(value),
          style: context.kt.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}
