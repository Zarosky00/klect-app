import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../notifications/notification_preferences.dart';
import '../notifications/notifications_screen.dart' show notificationStyle;
import 'settings_widgets.dart';

/// Which alerts you want to see.
///
/// KLECT keeps no per-type notification columns server-side, so these switches
/// are device preferences: they filter the Alerts tab and the tab badge. They
/// are stated as such rather than implying the server will stop sending.
class NotificationSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final muted = ref.watch(notificationPreferencesProvider);
    final controller = ref.read(notificationPreferencesProvider.notifier);

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Notifications', showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s4,
          Space.s5,
          Space.s12,
        ),
        children: <Widget>[
          Text(
            'These control what shows up in Alerts on this device. Nothing is '
            'deleted — switching a type back on brings its history with it.',
            style: context.kt.body.copyWith(color: colors.textSecondary),
          ),
          SettingsSection(
            header: 'Your work',
            children: <Widget>[
              for (final type in <NotificationType>[
                NotificationType.like,
                NotificationType.save,
                NotificationType.repost,
              ])
                _TypeToggle(type: type, muted: muted, controller: controller),
            ],
          ),
          SettingsSection(
            header: 'Conversation',
            children: <Widget>[
              for (final type in <NotificationType>[
                NotificationType.comment,
                NotificationType.reply,
                NotificationType.mention,
                NotificationType.message,
                NotificationType.call,
              ])
                _TypeToggle(type: type, muted: muted, controller: controller),
            ],
          ),
          SettingsSection(
            header: 'People',
            children: <Widget>[
              for (final type in <NotificationType>[
                NotificationType.follow,
                NotificationType.match,
              ])
                _TypeToggle(type: type, muted: muted, controller: controller),
            ],
          ),
          SettingsSection(
            header: 'KLECT',
            children: <Widget>[
              _TypeToggle(
                type: NotificationType.system,
                muted: muted,
                controller: controller,
              ),
            ],
          ),
          if (muted.isNotEmpty) ...<Widget>[
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
    );
  }
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({
    required this.type,
    required this.muted,
    required this.controller,
  });

  final NotificationType type;
  final Set<NotificationType> muted;
  final NotificationPreferences controller;

  @override
  Widget build(BuildContext context) {
    final copy = notificationTypeCopy[type];
    return SettingsToggleRow(
      icon: notificationStyle(context.kc, type).icon,
      title: copy?.title ?? type.wire,
      subtitle: copy?.subtitle,
      value: !muted.contains(type),
      onChanged: (enabled) => controller.setEnabled(type, enabled),
    );
  }
}
