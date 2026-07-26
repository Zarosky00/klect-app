import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import 'entity_visual.dart';

/// The `collection_templates` picker: icon, name and the template's own accent.
///
/// Choosing a template is optional — the "Something else" tile clears it — but
/// picking one seeds the collection's accent colour and offers its
/// `suggested_tags` further down the form.
class TemplatePicker extends StatelessWidget {
  /// Creates a template picker.
  const TemplatePicker({
    required this.templates,
    required this.selectedId,
    required this.onSelected,
    super.key,
    this.enabled = true,
  });

  /// The rows from `collection_templates`, in `sort_order`.
  final List<CollectionTemplate> templates;

  /// Currently chosen template id, or null for none.
  final String? selectedId;

  /// Fired with the template, or null when the choice is cleared.
  final ValueChanged<CollectionTemplate?> onSelected;

  /// Disables interaction while a save is in flight.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'What kind of shelf?',
          style: context.kt.label.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: Space.s2),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: <Widget>[
            for (var index = 0; index < templates.length; index++)
              _TemplateTile(
                template: templates[index],
                selected: templates[index].id == selectedId,
                index: index,
                onTap: enabled
                    ? () => onSelected(
                          templates[index].id == selectedId
                              ? null
                              : templates[index],
                        )
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.selected,
    required this.index,
    required this.onTap,
  });

  final CollectionTemplate template;
  final bool selected;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final accent = EntityVisual.accent(context, template.accentColor);

    return KPressable(
      onTap: onTap,
      enabled: onTap != null,
      semanticLabel: template.name,
      enforceMinTapTarget: false,
      child: AnimatedContainer(
        duration: KMotion.duration(context, KDurations.fast),
        curve: KCurves.standard,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s3,
          vertical: Space.s25,
        ),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: Opacities.ghost)
              : colors.surface2,
          borderRadius: BorderRadius.circular(Radii.full),
          border: Border.all(
            color: selected ? accent : colors.borderSubtle,
            width: selected ? Strokes.thick : Strokes.thin,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              EntityVisual.templateIcon(template.icon),
              size: Space.s4,
              color: selected ? accent : colors.textSecondary,
            ),
            const SizedBox(width: Space.s15),
            Text(
              template.name,
              style: context.kt.label.copyWith(
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
