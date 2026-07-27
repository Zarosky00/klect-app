import 'package:flutter/material.dart';

import '../../core/feedback/interaction_feedback.dart';
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

/// One rounded island holding a group of related settings rows.
///
/// The depth belongs to the section, not to every row: a single `surface.1`
/// container with an `elevation.low` shadow, hairline dividers between flat
/// rows inside. This is what keeps a settings screen from reading as a stack
/// of identical grey slabs.
class SettingsSection extends StatelessWidget {
  /// Creates a section.
  const SettingsSection({
    required this.children,
    super.key,
    this.header,
    this.note,
  });

  /// The rows, in order. Use the flat row widgets from this file.
  final List<Widget> children;

  /// Optional eyebrow rendered above the island.
  final String? header;

  /// Optional explainer under the eyebrow.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) rows.add(const _RowDivider());
      rows.add(children[index]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (header != null) SettingsSectionHeader(label: header!, note: note),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: colors.surface1,
            borderRadius: BorderRadius.circular(Radii.lg),
            border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
            boxShadow: KlectTheme.shadow(Elevation.low),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }
}

/// The hairline between two rows inside a [SettingsSection].
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) => Container(
    height: Strokes.hairline,
    margin: const EdgeInsetsDirectional.only(start: Space.s4),
    color: context.kc.borderSubtle,
  );
}

/// The tinted square behind a row's leading glyph.
///
/// `surface.3` at rest, `accent.subtle` when the row is the current choice,
/// `danger.subtle` for destructive rows — the tier system doing the talking
/// instead of a bare grey icon.
class _SettingsIconChip extends StatelessWidget {
  const _SettingsIconChip({
    required this.icon,
    this.selected = false,
    this.destructive = false,
  });

  final IconData icon;
  final bool selected;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final Color background;
    final Color tint;
    if (destructive) {
      background = colors.semanticDangerSubtle;
      tint = colors.semanticDanger;
    } else if (selected) {
      background = colors.accentSubtle;
      tint = colors.accentDefault;
    } else {
      background = colors.surface3;
      tint = colors.textSecondary;
    }
    return Container(
      width: Space.s8,
      height: Space.s8,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Icon(icon, size: Space.s5, color: tint),
    );
  }
}

/// A tappable settings row with a chevron. Flat — lives inside a
/// [SettingsSection], which owns the surface and the border.
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
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        child: Row(
          children: <Widget>[
            _SettingsIconChip(icon: icon, destructive: destructive),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: context.kt.bodyStrong.copyWith(color: tint),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: context.kt.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (value != null) ...<Widget>[
              const SizedBox(width: Space.s3),
              Text(
                value!,
                style: context.kt.callout.copyWith(color: colors.textSecondary),
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

/// A settings row with a switch. Flat — lives inside a [SettingsSection].
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s3,
          Space.s2,
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              _SettingsIconChip(icon: icon!),
              const SizedBox(width: Space.s3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: context.kt.bodyStrong),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: context.kt.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            ExcludeSemantics(
              child: Switch(
                value: value,
                onChanged: (next) {
                  triggerInteractionTapFeedback(context);
                  onChanged(next);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A radio-style choice row, used by every privacy picker. Flat — lives
/// inside a [SettingsSection]; the current choice tints its own row.
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
        color: selected ? colors.accentSubtle : null,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s3,
        ),
        child: Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              _SettingsIconChip(icon: icon!, selected: selected),
              const SizedBox(width: Space.s3),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: context.kt.bodyStrong),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: context.kt.caption.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
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
