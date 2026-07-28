import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/app_settings.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'settings_widgets.dart';

/// Theme and interaction preferences persisted across cold starts.
class AppearanceSettingsScreen extends ConsumerWidget {
  /// Creates the appearance screen.
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final settings = ref.watch(appSettingsProvider);
    final mode = settings.themeMode;
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
            'KLECT is dark-first \u2014 a private gallery at night, so your '
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
              SettingsChoiceRow(
                title: 'OLED',
                subtitle: 'True-black page backgrounds for OLED screens.',
                icon: Icons.contrast_rounded,
                selected: settings.oled,
                onTap: () => controller.setOled(true),
              ),
            ],
          ),
          SettingsSection(
            header: 'Typography',
            note: 'Bundled fonts work offline with multilingual fallbacks.',
            children: <Widget>[
              for (final pack in FontPack.values)
                SettingsChoiceRow(
                  title: switch (pack) {
                    FontPack.editorial => 'Editorial',
                    FontPack.modern => 'Modern',
                    FontPack.readable => 'Readable',
                  },
                  subtitle: switch (pack) {
                    FontPack.editorial => 'Fraunces headlines, gallery-like.',
                    FontPack.modern => 'Clean sans-serif throughout.',
                    FontPack.readable => 'Airier lines for long conversations.',
                  },
                  icon: switch (pack) {
                    FontPack.editorial => Icons.auto_stories_outlined,
                    FontPack.modern => Icons.text_fields_rounded,
                    FontPack.readable => Icons.menu_book_outlined,
                  },
                  selected: settings.fontPack == pack,
                  onTap: () => controller.setFontPack(pack),
                ),
              SettingsChoiceRow(
                title: 'Text size',
                subtitle: switch (settings.textScale) {
                  < 0.95 => 'Small · still follows your device scale',
                  > 1.1 => 'Large · still follows your device scale',
                  _ => 'Standard · follows your device scale',
                },
                icon: Icons.format_size_rounded,
                selected: false,
                onTap: () => controller.setTextScale(
                  settings.textScale < 0.95
                      ? 1
                      : settings.textScale > 1.1
                      ? 0.9
                      : 1.2,
                ),
              ),
            ],
          ),
          SettingsSection(
            header: 'Layout & motion',
            children: <Widget>[
              SettingsChoiceRow(
                title: 'Comfortable density',
                subtitle: 'More breathing room around collections and chats.',
                icon: Icons.space_bar_rounded,
                selected: settings.density == ContentDensity.comfortable,
                onTap: () => controller.setDensity(ContentDensity.comfortable),
              ),
              SettingsChoiceRow(
                title: 'Compact density',
                subtitle: 'See more activity without shrinking tap targets.',
                icon: Icons.view_agenda_outlined,
                selected: settings.density == ContentDensity.compact,
                onTap: () => controller.setDensity(ContentDensity.compact),
              ),
              SettingsChoiceRow(
                title: 'Motion',
                subtitle: switch (settings.motion) {
                  MotionPreference.system => 'Follow the device setting',
                  MotionPreference.full => 'Use full interface motion',
                  MotionPreference.reduced => 'Reduce non-essential motion',
                },
                icon: Icons.animation_rounded,
                selected: settings.motion != MotionPreference.system,
                onTap: () => controller.setMotion(switch (settings.motion) {
                  MotionPreference.system => MotionPreference.full,
                  MotionPreference.full => MotionPreference.reduced,
                  MotionPreference.reduced => MotionPreference.system,
                }),
              ),
              SettingsToggleRow(
                title: 'High contrast',
                subtitle: 'Stronger text while preserving status colours.',
                icon: Icons.tonality_rounded,
                value: settings.highContrast,
                onChanged: controller.setHighContrast,
              ),
            ],
          ),
          SettingsSection(
            header: 'Pulse & media',
            children: <Widget>[
              SettingsChoiceRow(
                title: 'Media-forward Pulse',
                subtitle: 'Collected Stories with larger visual moments.',
                icon: Icons.photo_library_outlined,
                selected:
                    settings.pulseLayout == PulseLayoutPreference.mediaForward,
                onTap: () => controller.setPulseLayout(
                  PulseLayoutPreference.mediaForward,
                ),
              ),
              SettingsChoiceRow(
                title: 'Balanced Pulse',
                subtitle: 'More conversation visible between media.',
                icon: Icons.view_stream_outlined,
                selected:
                    settings.pulseLayout == PulseLayoutPreference.balanced,
                onTap: () =>
                    controller.setPulseLayout(PulseLayoutPreference.balanced),
              ),
              SettingsToggleRow(
                title: 'Data saver',
                subtitle: 'Avoid eager media loading on mobile data.',
                icon: Icons.data_saver_on_rounded,
                value: settings.dataSaver,
                onChanged: controller.setDataSaver,
              ),
              SettingsToggleRow(
                title: 'Autoplay media',
                subtitle: 'Play eligible media while it is in view.',
                icon: Icons.play_circle_outline_rounded,
                value: settings.autoplayMedia,
                onChanged: (value) {
                  if (!settings.dataSaver) {
                    controller.setAutoplayMedia(value);
                  }
                },
              ),
            ],
          ),
          SettingsSection(
            header: 'Sound & touch',
            note: 'One familiar response for deliberate taps.',
            children: <Widget>[
              SettingsToggleRow(
                title: 'Interaction sounds',
                subtitle: 'Uses your Android device\u2019s native tap sound.',
                icon: Icons.touch_app_rounded,
                value: settings.interactionSoundsEnabled,
                onChanged: controller.setInteractionSoundsEnabled,
              ),
              SettingsToggleRow(
                title: 'Haptic feedback',
                subtitle:
                    'Optional light touch feedback. Off by default on new installs.',
                icon: Icons.vibration_rounded,
                value: settings.hapticsEnabled,
                onChanged: controller.setHapticsEnabled,
              ),
            ],
          ),
          const SizedBox(height: Space.s8),
          Text('Preview', style: context.kt.title3),
          const SizedBox(height: Space.s3),
          const _ActionColourLegend(),
          const SizedBox(height: Space.s5),
          KButton(
            label: 'Reset appearance',
            variant: KButtonVariant.secondary,
            icon: Icons.restart_alt_rounded,
            expand: true,
            onPressed: controller.resetAppearance,
          ),
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
