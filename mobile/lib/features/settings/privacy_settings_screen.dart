import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../auth/auth_controller.dart';
import '../matches/matches_screen.dart';
import '../profile/fill_viewport.dart';
import 'settings_widgets.dart';

/// Who can see you, who can message you, and whether you join taste matching.
///
/// Each control writes straight to `profiles` and is applied optimistically;
/// a refused write rolls the switch back rather than lying about the state.
/// The server enforces all three regardless of what this screen shows.
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() =>
      _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState
    extends ConsumerState<PrivacySettingsScreen> {
  AccountVisibility? _visibility;
  AllowMessagesFrom? _messages;
  bool? _similarity;
  bool _busy = false;

  Future<void> _patch(
    Map<String, dynamic> patch,
    VoidCallback rollback,
  ) async {
    setState(() => _busy = true);
    try {
      await ref.read(klectApiProvider).updateMyProfile(patch);
      ref.invalidate(myProfileProvider);
    } on KlectError catch (error) {
      if (!mounted) return;
      setState(rollback);
      KToast.error(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setVisibility(AccountVisibility next, AccountVisibility previous) {
    setState(() => _visibility = next);
    _apply(
      <String, dynamic>{'account_visibility': next.wire},
      () => _visibility = previous,
    );
  }

  void _setMessages(AllowMessagesFrom next, AllowMessagesFrom previous) {
    setState(() => _messages = next);
    _apply(
      <String, dynamic>{'allow_messages_from': next.wire},
      () => _messages = previous,
    );
  }

  void _setSimilarity(bool next) {
    setState(() => _similarity = next);
    _apply(
      <String, dynamic>{'show_similarity': next},
      () => _similarity = !next,
    );
    ref.invalidate(matchesProvider);
  }

  // Fires the write without awaiting it — the switch has already moved.
  void _apply(Map<String, dynamic> patch, VoidCallback rollback) {
    _patch(patch, rollback).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final profile = ref.watch(myProfileProvider);

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Privacy', showBack: true),
      body: profile.when(
        loading: () => const FillViewport(
          child: KSkeletonList(rows: 5, showMedia: false),
        ),
        error: (error, _) => FillViewport(
          child: KErrorState(
            error: error,
            onRetry: () => ref.invalidate(myProfileProvider),
          ),
        ),
        data: (me) {
          if (me == null) {
            return const FillViewport(
              child: KEmptyState(
                title: 'Not signed in',
                message: 'Privacy settings belong to an account.',
                icon: Icons.lock_outline_rounded,
              ),
            );
          }
          final visibility = _visibility ?? me.accountVisibility;
          final messages = _messages ?? me.allowMessagesFrom;
          final similarity = _similarity ?? me.showSimilarity;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              Space.s4,
              Space.s5,
              Space.s12,
            ),
            children: <Widget>[
              Text(
                'Visibility inherits downwards: a private collection hides '
                'every shelf and item inside it, whatever they say themselves.',
                style: context.kt.body.copyWith(color: colors.textSecondary),
              ),
              SettingsSection(
                header: 'Who sees your account',
                children: <Widget>[
                  SettingsChoiceRow(
                    title: AccountVisibility.public.label,
                    subtitle: 'Anyone, including logged-out visitors and '
                        'search engines.',
                    icon: Icons.public_rounded,
                    selected: visibility == AccountVisibility.public,
                    onTap: () =>
                        _setVisibility(AccountVisibility.public, visibility),
                  ),
                  SettingsChoiceRow(
                    title: AccountVisibility.followers.label,
                    subtitle: 'Only accounts that follow you.',
                    icon: Icons.group_outlined,
                    selected: visibility == AccountVisibility.followers,
                    onTap: () => _setVisibility(
                      AccountVisibility.followers,
                      visibility,
                    ),
                  ),
                  SettingsChoiceRow(
                    title: AccountVisibility.private.label,
                    subtitle: 'Only you.',
                    icon: Icons.lock_outline_rounded,
                    selected: visibility == AccountVisibility.private,
                    onTap: () =>
                        _setVisibility(AccountVisibility.private, visibility),
                  ),
                ],
              ),
              SettingsSection(
                header: 'Who can message you',
                note: 'Enforced when the conversation is opened, not after.',
                children: <Widget>[
                  for (final option in AllowMessagesFrom.values)
                    SettingsChoiceRow(
                      title: option.label,
                      subtitle: _messageSubtitle(option),
                      icon: _messageIcon(option),
                      selected: messages == option,
                      onTap: () => _setMessages(option, messages),
                    ),
                ],
              ),
              SettingsSection(
                header: 'Taste matching',
                children: <Widget>[
                  SettingsToggleRow(
                    title: 'Appear in "Collectors like you"',
                    subtitle: 'Compares the tags on your shelves with other '
                        'collectors. Turning this off removes you from '
                        'matching in both directions.',
                    icon: Icons.auto_awesome_outlined,
                    value: similarity,
                    onChanged: _setSimilarity,
                  ),
                ],
              ),
              SettingsSection(
                header: 'People',
                children: <Widget>[
                  SettingsRow(
                    icon: Icons.block_outlined,
                    title: 'Blocked and muted',
                    subtitle: 'Blocking is bidirectional and immediate.',
                    onTap: () => context.push('/settings/blocked'),
                  ),
                ],
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(top: Space.s4),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(
                        width: Space.s4,
                        height: Space.s4,
                        child: CircularProgressIndicator(
                          strokeWidth: Strokes.thick,
                        ),
                      ),
                      const SizedBox(width: Space.s2),
                      Text(
                        'Saving…',
                        style: context.kt.caption
                            .copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _messageSubtitle(AllowMessagesFrom option) =>
      switch (option) {
        AllowMessagesFrom.everyone => 'Anyone can open a conversation.',
        AllowMessagesFrom.following => 'Only people you follow.',
        AllowMessagesFrom.matches => 'Only your taste matches.',
        AllowMessagesFrom.mutual => 'Only people you both follow.',
        AllowMessagesFrom.nobody => 'Nobody can start a new conversation.',
      };

  static IconData _messageIcon(AllowMessagesFrom option) => switch (option) {
        AllowMessagesFrom.everyone => Icons.public_rounded,
        AllowMessagesFrom.following => Icons.person_outline_rounded,
        AllowMessagesFrom.matches => Icons.auto_awesome_outlined,
        AllowMessagesFrom.mutual => Icons.group_outlined,
        AllowMessagesFrom.nobody => Icons.do_not_disturb_on_outlined,
      };
}
