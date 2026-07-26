import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'settings_widgets.dart';

/// Theme: follow the system, or pin light/dark. The choice is persisted, so it
/// survives a cold start.
class AppearanceSettingsScreen extends ConsumerWidget {
  /// Creates the appearance screen.
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final mode = ref.watch(themeModeProvider);
    final controller = ref.read(appSettingsProvider.notifier);

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Appearance', showBack: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s5,
          vertical: Space.s4,
        ),
        children: <Widget>[
          Text(
            'KLECT is dark-first — a private gallery at night, so your '
            'photography is the only source of colour.',
            style: context.kt.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.s6),
          SettingsSection(
            children: <Widget>[
              SettingsChoiceRow(
                title: 'Follow the system',
                subtitle: 'Switches with your device.',
                icon: Icons.brightness_auto_rounded,
                selected: mode == ThemeMode.system,
                onTap: () => controller.setThemeMode(ThemeMode.system),
              ),
              SettingsChoiceRow(
                title: 'Always dark',
                subtitle: 'Editorial Noir, all day.',
                icon: Icons.dark_mode_rounded,
                selected: mode == ThemeMode.dark,
                onTap: () => controller.setThemeMode(ThemeMode.dark),
              ),
              SettingsChoiceRow(
                title: 'Always light',
                subtitle: 'The same system, brightened.',
                icon: Icons.light_mode_rounded,
                selected: mode == ThemeMode.light,
                onTap: () => controller.setThemeMode(ThemeMode.light),
              ),
            ],
          ),
          const SizedBox(height: Space.s8),
          Text('Preview', style: context.kt.title3),
          const SizedBox(height: Space.s3),
          const _ActionColourLegend(),
        ],
      ),
    );
  }
}

class _ActionColourLegend extends StatelessWidget {
  const _ActionColourLegend();

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
        boxShadow: KlectTheme.shadow(Elevation.low),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          KCountPill(
            icon: Icons.favorite_rounded,
            count: 128,
            active: true,
            activeColor: colors.actionLike,
            semanticLabel: 'Likes, 128',
          ),
          KCountPill(
            icon: Icons.bookmark_rounded,
            count: 42,
            active: true,
            activeColor: colors.actionSave,
            semanticLabel: 'Saves, 42',
          ),
          KCountPill(
            icon: Icons.repeat_rounded,
            count: 7,
            active: true,
            activeColor: colors.actionRepost,
            semanticLabel: 'Reposts, 7',
          ),
          KCountPill(
            icon: Icons.mode_comment_rounded,
            count: 19,
            active: true,
            activeColor: colors.actionComment,
            semanticLabel: 'Comments, 19',
          ),
        ],
      ),
    );
  }
}
