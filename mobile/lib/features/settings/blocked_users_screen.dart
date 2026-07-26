import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../profile/fill_viewport.dart';
import '../profile/person_row.dart';
import '../profile/profile_queries.dart';
import '../profile/user_actions.dart';

/// Which list is on screen.
enum _RestrictionTab { blocked, muted }

/// Everyone you have blocked or muted, and a way back from both.
///
/// Blocking is bidirectional and immediate — content, DMs and notifications
/// stop in both directions. Muting is one-way and silent: they are never told.
class BlockedUsersScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const BlockedUsersScreen({super.key});

  @override
  ConsumerState<BlockedUsersScreen> createState() =>
      _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends ConsumerState<BlockedUsersScreen> {
  _RestrictionTab _tab = _RestrictionTab.blocked;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final blocked = _tab == _RestrictionTab.blocked;
    final people = blocked
        ? ref.watch(blockedUsersProvider)
        : ref.watch(mutedUsersProvider);

    return KScaffold(
      appBar: const KFixedAppBar(title: 'Blocked and muted', showBack: true),
      onRefresh: () async {
        ref
          ..invalidate(blockedUsersProvider)
          ..invalidate(mutedUsersProvider);
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              Space.s3,
              Space.s5,
              Space.s2,
            ),
            child: Row(
              children: <Widget>[
                KChip(
                  label: 'Blocked',
                  icon: Icons.block_outlined,
                  selected: blocked,
                  onTap: () =>
                      setState(() => _tab = _RestrictionTab.blocked),
                ),
                const SizedBox(width: Space.s2),
                KChip(
                  label: 'Muted',
                  icon: Icons.volume_off_outlined,
                  selected: !blocked,
                  onTap: () => setState(() => _tab = _RestrictionTab.muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s5,
              Space.s1,
              Space.s5,
              Space.s3,
            ),
            child: Text(
              blocked
                  ? 'You will not see each other anywhere, and neither of you '
                      'can start a conversation.'
                  : 'Their content stops surfacing for you. They are never '
                      'told, and messages still arrive.',
              style: context.kt.caption.copyWith(color: colors.textTertiary),
            ),
          ),
          Expanded(
            child: people.when(
              loading: () => const FillViewport(
                child: KSkeletonList(rows: 5, showMedia: false),
              ),
              error: (error, _) => FillViewport(
                child: KErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(
                    blocked ? blockedUsersProvider : mutedUsersProvider,
                  ),
                ),
              ),
              data: (list) => list.isEmpty
                  ? FillViewport(
                      child: KEmptyState(
                        title: blocked ? 'Nobody blocked' : 'Nobody muted',
                        message: blocked
                            ? 'Block someone from their profile overflow and '
                                'they will show up here.'
                            : 'Mute is the quiet option — nothing is '
                                'announced and nothing is lost.',
                        icon: blocked
                            ? Icons.block_outlined
                            : Icons.volume_off_outlined,
                        compact: true,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        Space.s5,
                        Space.s0,
                        Space.s5,
                        Space.s12,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, index) => _RestrictionRow(
                        profile: list[index],
                        blocked: blocked,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestrictionRow extends ConsumerWidget {
  const _RestrictionRow({required this.profile, required this.blocked});

  final Profile profile;
  final bool blocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PersonRow(
        profile: profile,
        dense: true,
        showFollow: false,
        trailing: KButton(
          label: blocked ? 'Unblock' : 'Unmute',
          size: KButtonSize.small,
          variant: KButtonVariant.secondary,
          onPressed: () => blocked
              ? UserActions.unblock(context, ref, profile)
              : UserActions.unmute(context, ref, profile),
        ),
      );
}
