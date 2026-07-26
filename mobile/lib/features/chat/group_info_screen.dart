import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/api/klect_api.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import '../profile/person_row.dart';
import 'chat_api.dart';
import 'group_errors.dart';
import 'thread_controller.dart';
import 'widgets/group_avatar.dart';
import 'widgets/member_picker.dart';

/// The hard ceiling on active rows: the owner plus 64 members.
const int _maxActiveMembers = 65;

/// A group's home: title, description, and the member list with roles.
///
/// What the viewer can do follows their membership row, parsed long ago into
/// [ConversationMember.role]: admins add, remove and rename; the owner
/// promotes and demotes; everyone can leave. All of it is re-checked
/// server-side by the `0017` RPCs — this screen only hides what would be
/// refused anyway.
class GroupInfoScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const GroupInfoScreen({required this.conversationId, super.key});

  /// Route parameter.
  final String conversationId;

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  ChatThreadController get _thread =>
      ref.read(chatThreadProvider(widget.conversationId).notifier);

  ChatApi get _api => ref.read(chatApiProvider);

  // ────────────────────────────────────────────────────────────── actions ──

  /// Runs one management RPC, refetches the thread (members and conversation
  /// both live there), and reports the outcome as a toast.
  Future<bool> _run(
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
    } on KlectError catch (error) {
      if (mounted) KToast.error(context, groupErrorCopy(error));
      return false;
    }
    await _thread.refresh();
    if (mounted && success != null) KToast.success(context, success);
    return true;
  }

  Future<void> _editInfo(Conversation conversation) async {
    final edited = await _EditGroupSheet.show(
      context,
      title: conversation.title ?? '',
      description: conversation.description ?? '',
    );
    if (edited == null || !mounted) return;
    final titleChanged = edited.title != (conversation.title ?? '');
    final descriptionChanged =
        edited.description != (conversation.description ?? '');
    if (!titleChanged && !descriptionChanged) return;
    await _run(
      // Null keeps a value; an empty description clears it server-side.
      () => _api.updateGroupInfo(
        widget.conversationId,
        title: titleChanged ? edited.title : null,
        description: descriptionChanged ? edited.description : null,
      ),
      success: 'Group updated.',
    );
  }

  Future<void> _addMembers(List<ConversationMember> active) async {
    final capacity = _maxActiveMembers - active.length;
    final picked = await MemberPickerSheet.show(
      context,
      title: 'Add people',
      excludeIds: <String>{for (final member in active) member.userId},
      maxSelectable: capacity < 0 ? 0 : capacity,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      final joined = await _api.addGroupMembers(
        widget.conversationId,
        <String>[for (final profile in picked) profile.id],
      );
      await _thread.refresh();
      if (!mounted) return;
      KToast.success(
        context,
        joined == 0
            ? 'They were already here.'
            : 'Added $joined ${joined == 1 ? 'person' : 'people'}.',
      );
    } on KlectError catch (error) {
      if (mounted) KToast.error(context, groupErrorCopy(error));
    }
  }

  Future<void> _removeMember(ConversationMember member) async {
    final name = member.profile?.name ?? 'this member';
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Remove $name?',
      message: 'They leave the group immediately. '
          'An admin can always add them back.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => _api.removeGroupMember(widget.conversationId, member.userId),
      success: '$name was removed.',
    );
  }

  Future<void> _setRole(ConversationMember member, String role) async {
    final name = member.profile?.name ?? 'this member';
    if (role == 'owner') {
      final confirmed = await KConfirmDialog.show(
        context,
        title: 'Make $name the owner?',
        message: 'Ownership moves to them and you become an admin. '
            'Only they can hand it back.',
        confirmLabel: 'Transfer',
      );
      if (!confirmed || !mounted) return;
    }
    await _run(
      () => _api.setGroupMemberRole(widget.conversationId, member.userId, role),
      success: switch (role) {
        'owner' => '$name now owns this group.',
        'admin' => '$name is now an admin.',
        _ => '$name is no longer an admin.',
      },
    );
  }

  Future<void> _leave({required bool isOwner, required int othersCount}) async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Leave this group?',
      message: isOwner && othersCount > 0
          ? 'Ownership passes to the longest-standing admin — or member — '
              'and the conversation disappears from your inbox.'
          : 'The conversation disappears from your inbox. '
              'An admin can add you back later.',
      confirmLabel: 'Leave',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final me = ref.read(currentUserIdProvider);
    if (me == null) return;
    try {
      await _api.removeGroupMember(widget.conversationId, me);
    } on KlectError catch (error) {
      if (mounted) KToast.error(context, groupErrorCopy(error));
      return;
    }
    if (!mounted) return;
    KToast.success(context, 'You left the group.');
    // The thread below this screen belongs to a group we are no longer in.
    context.go(Routes.messages);
  }

  Future<void> _memberActions(
    ConversationMember member, {
    required bool viewerIsOwner,
    required bool viewerIsAdmin,
  }) async {
    final profile = member.profile;
    if (profile == null) return;
    await KSheet.show<void>(
      context: context,
      title: profile.name,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _InfoRow(
            icon: Icons.person_outline_rounded,
            label: 'View profile',
            onTap: () {
              Navigator.of(sheetContext).pop();
              context.push(KlectLinks.profilePath(profile.username));
            },
          ),
          if (viewerIsOwner && member.role == 'member')
            _InfoRow(
              icon: Icons.shield_outlined,
              label: 'Make admin',
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_setRole(member, 'admin'));
              },
            ),
          if (viewerIsOwner && member.role == 'admin')
            _InfoRow(
              icon: Icons.remove_moderator_outlined,
              label: 'Remove as admin',
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_setRole(member, 'member'));
              },
            ),
          if (viewerIsOwner)
            _InfoRow(
              icon: Icons.swap_horiz_rounded,
              label: 'Transfer ownership',
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_setRole(member, 'owner'));
              },
            ),
          if (viewerIsAdmin && member.role != 'owner')
            _InfoRow(
              icon: Icons.person_remove_outlined,
              label: 'Remove from group',
              destructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_removeMember(member));
              },
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────── build ──

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatThreadProvider(widget.conversationId));
    final viewerId = ref.watch(currentUserIdProvider);
    final conversation = state.conversation;

    if (conversation == null) {
      return KScaffold(
        appBar: const KFixedAppBar(title: 'Group info', showBack: true),
        body: state.loading
            ? const KSkeletonList(rows: 6, showMedia: false)
            : KErrorState(
                error: state.error,
                onRetry: () => unawaited(_thread.refresh()),
              ),
      );
    }
    if (conversation.kind != ConversationKind.group) {
      return const KScaffold(
        appBar: KFixedAppBar(title: 'Group info', showBack: true),
        body: KEmptyState(
          title: 'Not a group',
          message: 'Direct messages have a profile instead.',
          icon: Icons.person_outline_rounded,
        ),
      );
    }

    final active = <ConversationMember>[
      for (final member in state.members)
        if (member.isActive) member,
    ]..sort(_byRoleThenTenure);
    final viewer = _memberOf(active, viewerId);
    final viewerIsOwner = viewer?.role == 'owner';
    final viewerIsAdmin = viewerIsOwner || viewer?.role == 'admin';

    return KScaffold(
      appBar: KFixedAppBar(
        title: 'Group info',
        showBack: true,
        actions: <Widget>[
          if (viewerIsAdmin)
            KIconButton(
              icon: Icons.edit_outlined,
              semanticLabel: 'Edit group name and description',
              onPressed: () => unawaited(_editInfo(conversation)),
            ),
        ],
      ),
      onRefresh: _thread.refresh,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s4,
          Space.s4,
          Space.s10,
        ),
        children: <Widget>[
          _Header(conversation: conversation, memberCount: active.length),
          const SizedBox(height: Space.s6),
          _MembersHeader(
            count: active.length,
            onAdd: viewerIsAdmin && active.length < _maxActiveMembers
                ? () => unawaited(_addMembers(active))
                : null,
          ),
          const SizedBox(height: Space.s1),
          for (final member in active)
            _MemberRow(
              member: member,
              isSelf: member.userId == viewerId,
              // Only rows the viewer can actually act on get the sheet: the
              // owner manages everyone else; admins manage everyone but the
              // owner; nobody manages themselves (leaving lives below).
              onActions: member.userId != viewerId &&
                      (viewerIsOwner ||
                          (viewerIsAdmin && member.role != 'owner'))
                  ? () => unawaited(
                        _memberActions(
                          member,
                          viewerIsOwner: viewerIsOwner,
                          viewerIsAdmin: viewerIsAdmin,
                        ),
                      )
                  : null,
            ),
          const SizedBox(height: Space.s6),
          Divider(height: Strokes.hairline, color: context.kc.borderSubtle),
          const SizedBox(height: Space.s2),
          _InfoRow(
            icon: Icons.logout_rounded,
            label: 'Leave group',
            destructive: true,
            onTap: () => unawaited(
              _leave(
                isOwner: viewerIsOwner,
                othersCount: active.length - 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static ConversationMember? _memberOf(
    List<ConversationMember> members,
    String? userId,
  ) {
    for (final member in members) {
      if (member.userId == userId) return member;
    }
    return null;
  }

  static int _byRoleThenTenure(ConversationMember a, ConversationMember b) {
    final byRole = _rolePriority(a.role).compareTo(_rolePriority(b.role));
    if (byRole != 0) return byRole;
    final aJoined = a.joinedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bJoined = b.joinedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aJoined.compareTo(bJoined);
  }

  static int _rolePriority(String role) => switch (role) {
        'owner' => 0,
        'admin' => 1,
        _ => 2,
      };
}

// ─────────────────────────────────────────────────────────────── sections ──

class _Header extends ConsumerWidget {
  const _Header({required this.conversation, required this.memberCount});

  final Conversation conversation;
  final int memberCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final avatarUrl = ref.watch(klectApiProvider).publicUrl(
          conversation.avatarPath,
          bucket: StorageBucket.avatars,
        );
    final description = conversation.description;

    return Column(
      children: <Widget>[
        GroupAvatar(
          imageUrl: avatarUrl,
          name: conversation.displayTitle,
          size: Space.s20,
        ),
        const SizedBox(height: Space.s4),
        Text(
          conversation.displayTitle,
          style: context.kt.title1,
          textAlign: TextAlign.center,
        ),
        if (description != null && description.isNotEmpty) ...<Widget>[
          const SizedBox(height: Space.s2),
          Text(
            description,
            style: context.kt.body.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: Space.s2),
        Text(
          '$memberCount ${memberCount == 1 ? 'member' : 'members'}',
          style: context.kt.caption.copyWith(color: colors.textTertiary),
        ),
      ],
    );
  }
}

class _MembersHeader extends StatelessWidget {
  const _MembersHeader({required this.count, this.onAdd});

  final int count;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Members',
            style: context.kt.label.copyWith(
              color: context.kc.textSecondary,
            ),
          ),
        ),
        if (onAdd != null)
          KButton(
            label: 'Add',
            icon: Icons.person_add_alt_rounded,
            variant: KButtonVariant.ghost,
            size: KButtonSize.small,
            onPressed: onAdd,
          ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isSelf,
    this.onActions,
  });

  final ConversationMember member;
  final bool isSelf;
  final VoidCallback? onActions;

  static String? _roleLabel(String role) => switch (role) {
        'owner' => 'Owner',
        'admin' => 'Admin',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final profile = member.profile;
    if (profile == null) return const SizedBox.shrink();
    final roleLabel = _roleLabel(member.role);

    return PersonRow(
      profile: profile,
      dense: true,
      showFollow: false,
      subtitle: isSelf ? 'You · ${profile.handle}' : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (roleLabel != null) KChip(label: roleLabel, dense: true),
          if (onActions != null) ...<Widget>[
            const SizedBox(width: Space.s2),
            KIconButton(
              icon: Icons.more_horiz_rounded,
              semanticLabel: 'Manage ${profile.name}',
              onPressed: onActions,
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

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
              child: Text(label, style: context.kt.body.copyWith(color: tint)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── edit sheet ──

class _EditGroupSheet extends StatefulWidget {
  const _EditGroupSheet({required this.title, required this.description});

  final String title;
  final String description;

  /// Opens the sheet; resolves with the edited values, or null on dismiss.
  static Future<({String title, String description})?> show(
    BuildContext context, {
    required String title,
    required String description,
  }) =>
      KSheet.show<({String title, String description})>(
        context: context,
        title: 'Edit group',
        builder: (_) => _EditGroupSheet(title: title, description: description),
      );

  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.title);
  late final TextEditingController _description =
      TextEditingController(text: widget.description);
  bool _titleMissing = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleMissing = true);
      return;
    }
    Navigator.of(context)
        .pop((title: title, description: _description.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    // The sheet holds text fields; keep them above the keyboard.
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          KTextField(
            controller: _title,
            label: 'Group name',
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            errorText: _titleMissing ? 'Give the group a name first.' : null,
            onChanged: (_) {
              if (_titleMissing) setState(() => _titleMissing = false);
            },
          ),
          const SizedBox(height: Space.s4),
          KTextField(
            controller: _description,
            label: 'Description',
            hint: 'Optional — what belongs in here',
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: Space.s5),
          KButton(label: 'Save', expand: true, onPressed: _save),
        ],
      ),
    );
  }
}
