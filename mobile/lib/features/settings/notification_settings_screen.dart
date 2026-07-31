import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../notifications/notification_category.dart';
import '../notifications/notification_preferences.dart';
import '../profile/fill_viewport.dart';
import 'settings_widgets.dart';

/// Which alerts you want to see.
///
/// These are account preferences, not device preferences: they live in
/// `user_preferences.notifications`, so signing in elsewhere renders the same
/// switches and the push fanout honours the same flags.
///
/// One switch per [NotificationCategory], in the Glossary order the enum itself
/// declares, so the rail chips, the preference keys and these rows can never
/// disagree about order or naming. The list renders only from a resolved
/// [NotificationPreferenceSet], never from an optimistic default, so no switch
/// accepts input before the account's own state is on screen (Requirement 5.7).
class NotificationSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final preferences = ref.watch(notificationPreferencesProvider);
    final controller = ref.read(notificationPreferencesProvider.notifier);

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Notifications', showBack: true),
      body: preferences.when(
        loading: () => const FillViewport(
          child: KSkeletonList(rows: 6, showMedia: false),
        ),
        error: (_, _) => FillViewport(
          child: KErrorState(
            message: 'Your notification settings could not be loaded.',
            onRetry: () => ref.invalidate(notificationPreferencesProvider),
          ),
        ),
        data: (resolved) => ListView(
          padding: const EdgeInsets.fromLTRB(
            Space.s5,
            Space.s4,
            Space.s5,
            Space.s12,
          ),
          children: <Widget>[
            Text(
              'These control what reaches you on every device you sign in on. '
              'Nothing is deleted — switching a category back on brings its '
              'history with it.',
              style: context.kt.body.copyWith(color: colors.textSecondary),
            ),
            SettingsSection(
              header: 'Categories',
              children: <Widget>[
                for (final category in NotificationCategory.values)
                  _CategoryToggle(
                    category: category,
                    preferences: resolved,
                    controller: controller,
                  ),
              ],
            ),
            if (resolved.hasDisabled) ...<Widget>[
              const SizedBox(height: Space.s6),
              KButton(
                label: 'Turn everything back on',
                variant: KButtonVariant.secondary,
                expand: true,
                onPressed: controller.enableAll,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryToggle extends StatelessWidget {
  const _CategoryToggle({
    required this.category,
    required this.preferences,
    required this.controller,
  });

  final NotificationCategory category;
  final NotificationPreferenceSet preferences;
  final NotificationPreferencesService controller;

  @override
  Widget build(BuildContext context) {
    final copy = notificationCategoryCopy[category];
    return SettingsToggleRow(
      icon: category.style(context.kc).glyph,
      title: copy?.title ?? category.label,
      subtitle: copy?.subtitle,
      value: preferences.isEnabled(category),
      onChanged: (enabled) => controller.setEnabled(category, enabled),
    );
  }
}
