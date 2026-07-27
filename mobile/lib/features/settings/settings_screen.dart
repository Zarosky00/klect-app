import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/klect_api.dart';
import '../../core/app_version.dart';
import '../../core/models/models.dart';
import '../../core/offline/action_queue.dart';
import '../../core/settings/app_settings.dart';
import '../../core/updates/update_checker.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';
import '../profile/profile_queries.dart';
import '../shell/update_banner.dart';
import 'about_screen.dart';
import 'account_settings_screen.dart';
import 'delete_account_sheet.dart';
import 'notification_settings_screen.dart';
import 'settings_widgets.dart';

/// Settings hub: account, appearance, privacy, blocked accounts, notifications,
/// about, sign out, delete account.
///
/// `/settings/appearance`, `/settings/privacy` and `/settings/blocked` are real
/// routes so they deep-link; the three screens added here are pushed on the
/// root navigator instead, because `lib/router.dart` belongs to another agent
/// and needs no change for them to work.
class SettingsScreen extends ConsumerWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final profile = ref.watch(myProfileProvider).value;
    final queue = ref.watch(offlineQueueProvider);
    final themeMode = ref.watch(themeModeProvider);

    Future<void> push(Widget screen) => Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: (routeContext) => screen));

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Settings', showBack: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s4,
          Space.s5,
          Space.s12,
        ),
        children: <Widget>[
          if (profile != null)
            _ProfileHeroRow(
              profile: profile,
              avatarUrl: avatarUrlOf(api, profile.avatarPath),
              onTap: () => context.push('/u/${profile.username}'),
            ),
          SettingsSection(
            header: 'Account',
            children: <Widget>[
              SettingsRow(
                icon: Icons.badge_outlined,
                title: 'Account',
                subtitle: 'Name, handle, email, password',
                onTap: () => push(const AccountSettingsScreen()),
              ),
              SettingsRow(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'Which alerts reach you',
                onTap: () => push(const NotificationSettingsScreen()),
              ),
            ],
          ),
          SettingsSection(
            header: 'Privacy and safety',
            children: <Widget>[
              SettingsRow(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy',
                subtitle: 'Who sees you, who can message you',
                onTap: () => context.push('/settings/privacy'),
              ),
              SettingsRow(
                icon: Icons.block_outlined,
                title: 'Blocked and muted',
                subtitle: 'Blocking is bidirectional and immediate',
                onTap: () => context.push('/settings/blocked'),
              ),
            ],
          ),
          SettingsSection(
            header: 'App',
            children: <Widget>[
              SettingsRow(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                subtitle: 'Theme, sound and touch',
                value: switch (themeMode) {
                  ThemeMode.system => 'System',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                },
                onTap: () => context.push('/settings/appearance'),
              ),
              const _CheckForUpdatesRow(),
              SettingsRow(
                icon: Icons.info_outline_rounded,
                title: 'About KLECT',
                subtitle: 'Version, terms, privacy policy',
                onTap: () => push(const AboutScreen()),
              ),
            ],
          ),
          const SizedBox(height: Space.s5),
          ListenableBuilder(
            listenable: queue,
            builder: (context, _) => queue.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: Space.s5),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.cloud_sync_outlined,
                          size: Space.s5,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: Space.s2),
                        Expanded(
                          child: Text(
                            '${queue.length} action'
                            '${queue.length == 1 ? '' : 's'} waiting to sync.',
                            style: context.kt.caption.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          KButton(
            label: 'Sign out',
            variant: KButtonVariant.secondary,
            expand: true,
            onPressed: () async {
              final confirmed = await KConfirmDialog.show(
                context,
                title: 'Sign out?',
                message: 'Anything waiting to sync will be dropped.',
                confirmLabel: 'Sign out',
                destructive: true,
              );
              if (!confirmed) return;
              await ref.read(authControllerProvider.notifier).signOut();
            },
          ),
          const SizedBox(height: Space.s3),
          KButton(
            label: 'Delete account',
            variant: KButtonVariant.danger,
            expand: true,
            onPressed: profile == null
                ? null
                : () => DeleteAccountFlow.start(context, profile: profile),
          ),
        ],
      ),
    );
  }
}

/// The identity card at the top of Settings — who is signed in, one tap from
/// their public profile. A real hero surface (`surface.2` + `elevation.low`),
/// not another anonymous list row.
class _CheckForUpdatesRow extends ConsumerStatefulWidget {
  const _CheckForUpdatesRow();

  @override
  ConsumerState<_CheckForUpdatesRow> createState() =>
      _CheckForUpdatesRowState();
}

class _CheckForUpdatesRowState extends ConsumerState<_CheckForUpdatesRow> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await ref.read(updateCheckerProvider).checkNow();
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result.status) {
      case ManualUpdateStatus.updateAvailable:
        await UpdateSheet.show(context, result.update!);
        return;
      case ManualUpdateStatus.upToDate:
        KToast.success(context, 'Klect $kAppVersion is up to date');
        return;
      case ManualUpdateStatus.unavailable:
        KToast.error(
          context,
          'Could not check for updates. Try again when you are online.',
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
    icon: Icons.system_update_alt_rounded,
    title: 'Check for updates',
    subtitle: 'Android app · Version $kAppVersion',
    value: _checking ? 'Checking…' : null,
    onTap: () => unawaited(_check()),
  );
}

class _ProfileHeroRow extends StatelessWidget {
  const _ProfileHeroRow({
    required this.profile,
    required this.avatarUrl,
    required this.onTap,
  });

  final Profile profile;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: 'Open your profile',
      child: Container(
        padding: const EdgeInsets.all(Space.s4),
        decoration: BoxDecoration(
          color: colors.surface2,
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(color: colors.borderSubtle, width: Strokes.thin),
          boxShadow: KlectTheme.shadow(Elevation.low),
        ),
        child: Row(
          children: <Widget>[
            KAvatar(
              imageUrl: avatarUrl,
              name: profile.name,
              isVerified: profile.isVerified,
              size: Space.s16,
            ),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    profile.name,
                    style: context.kt.title2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.s05),
                  Text(
                    profile.handle,
                    style: context.kt.callout.copyWith(
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    'View profile',
                    style: context.kt.caption.copyWith(
                      color: colors.accentDefault,
                    ),
                  ),
                ],
              ),
            ),
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
