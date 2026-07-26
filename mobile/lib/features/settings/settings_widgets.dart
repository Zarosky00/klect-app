import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../ui/ui.dart';

/// A small all-caps eyebrow above a group of settings rows.
class SettingsSectionHeader extends StatelessWidget {
  /// Creates a section header.
  const SettingsSectionHeader({required this.label, super.key, this.note});

  /// Section name.
  final String label;

  /// An optional sentence under the label, for anything that needs explaining
  /// before the user changes it.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.s1,
        Space.s6,
        Space.s1,
        Space.s2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: context.kt.micro.copyWith(color: colors.textTertiary),
          ),
          if (note != null) ...<Widget>[
            const SizedBox(height: Space.s1),
            Text(
              note!,
              style: context.kt.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable settings row with a chevron.
class SettingsRow extends StatelessWidget {
  /// Creates a row.
  const SettingsRow({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
    this.subtitle,
    this.value,
    this.destructive = false,
  });

  /// Leading glyph.
  final IconData icon;

  /// Row title.
  final String title;

  /// One line of explanation.
  final String? subtitle;

  /// The current value, shown on the right before the chevron.
  final String? value;

  /// Renders in `semantic.danger`.
  final bool destructive;

  /// Tap handler.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = destructive ? colors.semanticDanger : colors.textPrimary;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: value == null ? title : '$title, $value',
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.s2),
        padding: const EdgeInsets.all(Space.s4),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              size: Space.s6,
              color: destructive ? colors.semanticDanger : colors.textSecondary,
            ),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: context.kt.bodyStrong.copyWith(color: tint)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                ],
              ),
            ),
            if (value != null) ...<Widget>[
              const SizedBox(width: Space.s3),
              Text(
                value!,
                style: context.kt.callout
                    .copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(width: Space.s1),
            Icon(
              Icons.chevron_right_rounded,
              size: Space.s5,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A settings row with a switch.
class SettingsToggleRow extends StatelessWidget {
  /// Creates a toggle row.
  const SettingsToggleRow({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
    this.icon,
  });

  /// Row title.
  final String title;

  /// One line of explanation.
  final String? subtitle;

  /// Optional leading glyph.
  final IconData? icon;

  /// Current state.
  final bool value;

  /// Change handler.
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Semantics(
      toggled: value,
      label: title,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.s2),
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s3,
          Space.s2,
        ),
        decoration: BoxDecoration(
          color: colors.surface1,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: Space.s6, color: colors.textSecondary),
              const SizedBox(width: Space.s4),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: context.kt.bodyStrong),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            ExcludeSemantics(
              child: Switch(value: value, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}

/// A radio-style choice row, used by every privacy picker.
class SettingsChoiceRow extends StatelessWidget {
  /// Creates a choice row.
  const SettingsChoiceRow({
    required this.title,
    required this.selected,
    required this.onTap,
    super.key,
    this.subtitle,
    this.icon,
  });

  /// Option label.
  final String title;

  /// What choosing it means.
  final String? subtitle;

  /// Optional leading glyph.
  final IconData? icon;

  /// Whether this is the current choice.
  final bool selected;

  /// Tap handler.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: selected ? '$title, selected' : title,
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.s2),
        padding: const EdgeInsets.all(Space.s4),
        decoration: BoxDecoration(
          color: selected ? colors.accentSubtle : colors.surface1,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(
            color: selected ? colors.accentDefault : colors.borderSubtle,
            width: Strokes.thin,
          ),
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: Space.s6,
                color: selected ? colors.accentDefault : colors.textSecondary,
              ),
              const SizedBox(width: Space.s4),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: context.kt.bodyStrong),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: Space.s5,
              color: selected ? colors.accentDefault : colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
