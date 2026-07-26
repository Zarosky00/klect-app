import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'profile_queries.dart';

/// Everything you can do *to a person*, in one place.
///
/// Profile, matches, search, follower lists and notifications all reach the
/// same message / mute / block / report / share flows, so safety is never one
/// surface behind the rest of the product.
abstract final class UserActions {
  /// Opens (or creates) the DM with [userId] and routes to it.
  ///
  /// `start_dm` enforces the recipient's `allow_messages_from` server-side, so
  /// a refusal is a normal outcome, not a bug — it surfaces as a toast.
  static Future<void> message(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    try {
      final conversationId = await ref.read(klectApiProvider).startDm(userId);
      if (!context.mounted) return;
      unawaited(context.push('/messages/$conversationId'));
    } on KlectError catch (error) {
      if (!context.mounted) return;
      KToast.error(
        context,
        error.kind == KlectErrorKind.messagesBlocked
            ? 'This person is not accepting messages.'
            : error.message,
      );
    }
  }

  /// Blocks [profile] after a confirmation. Returns true when it went through.
  ///
  /// Blocking is bidirectional and immediate server-side: content, DMs and
  /// notifications stop in both directions.
  static Future<bool> block(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Block ${profile.name}?',
      message: 'You will not see each other, message each other, or appear in '
          "each other's feeds. You can undo this in Settings.",
      confirmLabel: 'Block',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return false;
    try {
      await ref.read(klectApiProvider).blockUser(profile.id);
      ref
        ..invalidate(blockedUsersProvider)
        ..invalidate(myFollowingIdsProvider);
      if (!context.mounted) return true;
      KToast.show(
        context,
        '${profile.name} is blocked.',
        kind: KToastKind.success,
        icon: Icons.block_rounded,
      );
      return true;
    } on KlectError catch (error) {
      if (context.mounted) KToast.error(context, error.message);
      return false;
    }
  }

  /// Lifts a block.
  static Future<void> unblock(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    try {
      await ref.read(klectApiProvider).unblockUser(profile.id);
      ref.invalidate(blockedUsersProvider);
      if (!context.mounted) return;
      KToast.success(context, '${profile.name} is unblocked.');
    } on KlectError catch (error) {
      if (context.mounted) KToast.error(context, error.message);
    }
  }

  /// Mutes [profile] — their content stops surfacing and they are not told.
  static Future<void> mute(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    try {
      await ref.read(klectApiProvider).muteUser(profile.id);
      ref.invalidate(mutedUsersProvider);
      if (!context.mounted) return;
      KToast.show(
        context,
        '${profile.name} is muted. They are not told.',
        kind: KToastKind.success,
        icon: Icons.volume_off_rounded,
      );
    } on KlectError catch (error) {
      if (context.mounted) KToast.error(context, error.message);
    }
  }

  /// Unmutes [profile].
  static Future<void> unmute(
    BuildContext context,
    WidgetRef ref,
    Profile profile,
  ) async {
    try {
      await ref.read(klectApiProvider).unmuteUser(profile.id);
      ref.invalidate(mutedUsersProvider);
      if (!context.mounted) return;
      KToast.success(context, '${profile.name} is unmuted.');
    } on KlectError catch (error) {
      if (context.mounted) KToast.error(context, error.message);
    }
  }

  /// Opens the report sheet for a person. Reporting twice says so, never errors.
  static Future<void> report(BuildContext context, Profile profile) =>
      KReportSheet.showForUser(
        context,
        userId: profile.id,
        subjectLabel: profile.handle,
      );

  /// Copies the canonical profile URL.
  static Future<void> copyLink(BuildContext context, Profile profile) async {
    await Clipboard.setData(
      ClipboardData(text: KlectLinks.profileUrl(profile.username)),
    );
    if (!context.mounted) return;
    KToast.show(
      context,
      'Link copied.',
      kind: KToastKind.success,
      icon: Icons.link_rounded,
    );
  }

  /// Opens the OS share sheet for a profile.
  static Future<void> share(Profile profile) => SharePlus.instance.share(
        ShareParams(
          text: '${profile.name} on KLECT\n'
              '${KlectLinks.profileUrl(profile.username)}',
          subject: profile.name,
        ),
      );

  /// The overflow sheet: everything rarer than follow and message.
  static Future<void> showOverflow(
    BuildContext context, {
    required Profile profile,
  }) =>
      KSheet.show<void>(
        context: context,
        title: profile.handle,
        builder: (sheetContext) => _UserOverflowBody(profile: profile),
      );
}

class _UserOverflowBody extends ConsumerWidget {
  const _UserOverflowBody({required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final isSelf = ref.watch(currentUserIdProvider) == profile.id;

    Future<void> close() async => Navigator.of(context).maybePop();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (!isSelf)
          _ActionRow(
            icon: Icons.forum_outlined,
            label: 'Message',
            onTap: () async {
              await close();
              if (!context.mounted) return;
              await UserActions.message(context, ref, profile.id);
            },
          ),
        _ActionRow(
          icon: Icons.link_rounded,
          label: 'Copy link',
          onTap: () async {
            await close();
            if (!context.mounted) return;
            await UserActions.copyLink(context, profile);
          },
        ),
        _ActionRow(
          icon: Icons.ios_share_rounded,
          label: 'Share profile',
          onTap: () async {
            await close();
            await UserActions.share(profile);
          },
        ),
        if (!isSelf) ...<Widget>[
          const SizedBox(height: Space.s2),
          Divider(color: colors.borderSubtle, height: Strokes.hairline),
          const SizedBox(height: Space.s2),
          _ActionRow(
            icon: Icons.volume_off_outlined,
            label: 'Mute',
            subtitle: 'Their content stops surfacing. They are not told.',
            onTap: () async {
              await close();
              if (!context.mounted) return;
              await UserActions.mute(context, ref, profile);
            },
          ),
          _ActionRow(
            icon: Icons.block_outlined,
            label: 'Block',
            subtitle: 'Bidirectional and immediate.',
            destructive: true,
            onTap: () async {
              await close();
              if (!context.mounted) return;
              await UserActions.block(context, ref, profile);
            },
          ),
          _ActionRow(
            icon: Icons.flag_outlined,
            label: 'Report',
            destructive: true,
            onTap: () async {
              await close();
              if (!context.mounted) return;
              await UserActions.report(context, profile);
            },
          ),
        ],
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool destructive;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final tint = destructive ? colors.semanticDanger : colors.textPrimary;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        child: Row(
          children: <Widget>[
            Icon(icon, size: Space.s5, color: tint),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: context.kt.body.copyWith(color: tint)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: context.kt.caption
                          .copyWith(color: colors.textTertiary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
