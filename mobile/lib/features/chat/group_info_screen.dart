import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'chat_models.dart';
import 'group_errors.dart';
import 'thread_controller.dart';
import 'widgets/group_avatar.dart';
import 'widgets/group_avatar_editor.dart';
import 'widgets/member_picker.dart';

/// The hard ceiling on active rows: the owner plus 64 members.
///
/// This is the server's number — `add_group_members` counts active rows and
/// raises `group_full` past 65 — so add-member capacity is this minus the
/// active member count and never more. The member *list* renders any group
/// size the server can hold (13.2, 13.4); it is only the add affordance that
/// is bounded, because offering an add the RPC would refuse is a bug.
const int _maxActiveMembers = 256;

/// Which role changes one viewer may offer for one target member.
///
/// This mirrors `set_group_member_role` in
/// `20260728120000_notifications_calls_messages_overhaul.sql` clause for
/// clause, so the sheet can never offer a change the RPC refuses (13.5, 13.6):
///
/// - `p_role = 'owner'` needs caller role `owner` → [canTransferOwnership].
/// - `p_role in ('admin','member')` needs `is_conversation_admin` — the owner
///   *or* an admin → [canPromoteToAdmin] and [canDemoteToMember].
/// - a target whose role is `owner` raises `not_owner` → every flag is false.
@immutable
class GroupRoleAffordances {
  /// Resolves the affordances for one (viewer, target) pair.
  ///
  /// [viewerRole] is null when the viewer holds no active membership row, which
  /// the RPC refuses with `not_member`; that yields no affordances at all.
  const GroupRoleAffordances({
    required this.viewerRole,
    required this.targetRole,
    required this.isSelf,
  });

  /// The viewer's `conversation_members.role`, or null when they are not in
  /// the group.
  final String? viewerRole;

  /// The target member's `conversation_members.role`.
  final String targetRole;

  /// Whether the target row is the viewer's own.
  final bool isSelf;

  /// Any role the client does not recognise reads as `member` — the least
  /// privileged of the three, and the same fallback `_MemberRow` badges with.
  static String _rank(String? role) =>
      role == 'owner' || role == 'admin' ? role! : 'member';

  bool get _viewerIsOwner => viewerRole == 'owner';

  bool get _viewerIsAdmin => _viewerIsOwner || viewerRole == 'admin';

  /// The owner is never a target, and nobody manages their own row here —
  /// stepping down is a transfer and leaving lives at the bottom of the screen.
  bool get _targetIsManageable => !isSelf && _rank(targetRole) != 'owner';

  /// Promotion of a `member` to `admin`, open to admins as well as the owner.
  bool get canPromoteToAdmin =>
      _viewerIsAdmin && _targetIsManageable && _rank(targetRole) == 'member';

  /// Demotion of an `admin` to `member`, open to admins as well as the owner.
  bool get canDemoteToMember =>
      _viewerIsAdmin && _targetIsManageable && _rank(targetRole) == 'admin';

  /// Ownership transfer stays owner-only.
  bool get canTransferOwnership => _viewerIsOwner && _targetIsManageable;

  /// Removal follows `remove_group_member`: admin or owner, never the owner.
  bool get canRemove => _viewerIsAdmin && _targetIsManageable;

  /// Whether any management action is available, and therefore whether the
  /// member row should carry a manage affordance at all.
  bool get any =>
      canPromoteToAdmin ||
      canDemoteToMember ||
      canTransferOwnership ||
      canRemove;
}

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
  String _memberQuery = '';

  ChatThreadController get _thread =>
      ref.read(chatThreadProvider(widget.conversationId).notifier);

  ChatApi get _api => ref.read(chatApiProvider);

  // ────────────────────────────────────────────────────────────── actions ──

  /// Runs one management RPC, refetches the thread (members and conversation
  /// both live there), and reports the outcome as a toast.
  Future<bool> _run(Future<void> Function() action, {String? success}) async {
    try {
      await action().timeout(const Duration(seconds: 10));
      await _thread.refresh().timeout(const Duration(seconds: 2));
    } on Object catch (error) {
      if (mounted) KToast.error(context, chatErrorCopy(error));
      return false;
    }
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

  Future<void> _replaceAvatar() async {
    final image = await GroupAvatarEditor.pick(context);
    if (image == null || !mounted) return;
    await _run(() async {
      final path = await _api.uploadGroupAvatar(image);
      await _api.updateGroupInfo(widget.conversationId, avatarPath: path);
    }, success: 'Group photo updated.');
  }

  Future<void> _removeAvatar() async {
    await _run(
      () => _api.clearGroupAvatar(widget.conversationId),
      success: 'Group photo removed.',
    );
  }

  Future<void> _avatarActions(Conversation conversation) async {
    await KSheet.show<void>(
      context: context,
      title: 'Group photo',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _InfoRow(
            icon: Icons.photo_camera_outlined,
            label: conversation.avatarPath == null
                ? 'Add group photo'
                : 'Replace group photo',
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_replaceAvatar());
            },
          ),
          if (conversation.avatarPath != null)
            _InfoRow(
              icon: Icons.delete_outline_rounded,
              label: 'Remove group photo',
              destructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_removeAvatar());
              },
            ),
        ],
      ),
    );
  }

  /// Opens the picker with capacity set to the ceiling minus the active member
  /// count, counting pending join requests because the server counts every row
  /// whose `left_at` is null — a capacity that ignored them would offer an add
  /// that `add_group_members` refuses with `group_full`.
  Future<void> _addMembers(
    List<ConversationMember> accepted,
    List<ConversationMember> pending,
  ) async {
    final capacity = _maxActiveMembers - accepted.length - pending.length;
    final picked = await MemberPickerSheet.show(
      context,
      title: 'Add people',
      excludeIds: <String>{
        for (final member in accepted) member.userId,
        for (final member in pending) member.userId,
      },
      maxSelectable: capacity < 0 ? 0 : capacity,
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      final joined = await _api.addGroupMembers(widget.conversationId, <String>[
        for (final profile in picked) profile.id,
      ]);
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
      message:
          'They leave the group immediately. '
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
        message:
            'Ownership moves to them and you become an admin. '
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

  Future<void> _setPolicy(
    Conversation conversation,
    _GroupPolicyField field,
  ) async {
    final current = switch (field) {
      _GroupPolicyField.editInfo => conversation.groupPolicy.editInfo,
      _GroupPolicyField.addMembers => conversation.groupPolicy.addMembers,
      _GroupPolicyField.sendMessages => conversation.groupPolicy.sendMessages,
    };
    final selected = await KSheet.show<GroupPermissionScope>(
      context: context,
      title: field.title,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final scope in GroupPermissionScope.values)
            _InfoRow(
              icon: scope == current
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              label: scope.label,
              onTap: () => Navigator.of(sheetContext).pop(scope),
            ),
        ],
      ),
    );
    if (selected == null || selected == current || !mounted) return;
    final next = switch (field) {
      _GroupPolicyField.editInfo => conversation.groupPolicy.copyWith(
        editInfo: selected,
      ),
      _GroupPolicyField.addMembers => conversation.groupPolicy.copyWith(
        addMembers: selected,
      ),
      _GroupPolicyField.sendMessages => conversation.groupPolicy.copyWith(
        sendMessages: selected,
      ),
    };
    await _run(() async {
      await _api.setGroupPolicy(widget.conversationId, next);
    }, success: '${field.title} updated.');
  }

  Future<void> _setJoinApproval(bool required) async {
    await _run(
      () async {
        await _api.setGroupJoinApproval(
          widget.conversationId,
          required: required,
        );
      },
      success: required
          ? 'New joins now need approval.'
          : 'Invite-link joins are now immediate.',
    );
  }

  Future<void> _showInvite(Conversation conversation) async {
    await KSheet.show<void>(
      context: context,
      title: 'Group invite',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            conversation.inviteTokenPrefix == null
                ? 'Create a private invite code. Rotating it immediately '
                      'invalidates the previous code.'
                : 'An invite is active. Its full code is only shown when it '
                      'is created or rotated.',
            style: context.kt.body.copyWith(color: context.kc.textSecondary),
          ),
          const SizedBox(height: Space.s4),
          KButton(
            label: conversation.inviteTokenPrefix == null
                ? 'Create and copy invite'
                : 'Rotate and copy invite',
            icon: Icons.link_rounded,
            expand: true,
            onPressed: () async {
              Navigator.of(sheetContext).pop();
              try {
                final token = await _api.rotateGroupInvite(
                  widget.conversationId,
                );
                await Clipboard.setData(ClipboardData(text: token));
                await _thread.refresh();
                if (mounted) {
                  KToast.success(context, 'New private invite copied.');
                }
              } on KlectError catch (error) {
                if (mounted) KToast.error(context, groupErrorCopy(error));
              }
            },
          ),
          if (conversation.inviteTokenPrefix != null) ...<Widget>[
            const SizedBox(height: Space.s2),
            KButton(
              label: 'Revoke invite',
              icon: Icons.link_off_rounded,
              variant: KButtonVariant.secondary,
              expand: true,
              onPressed: () async {
                Navigator.of(sheetContext).pop();
                await _run(
                  () => _api.revokeGroupInvite(widget.conversationId),
                  success: 'Invite revoked.',
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _reviewJoin(
    ConversationMember member, {
    required bool accept,
  }) async {
    final name = member.profile?.name ?? 'This person';
    await _run(
      () => _api.reviewGroupJoinRequest(
        widget.conversationId,
        member.userId,
        accept: accept,
      ),
      success: accept ? '$name joined the group.' : '$name was declined.',
    );
  }

  Future<void> _notificationSettings(ConversationMember viewer) async {
    final selected = await KSheet.show<String>(
      context: context,
      title: 'Notifications',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final option in const <(String, String, IconData)>[
            ('all', 'All messages', Icons.notifications_active_outlined),
            ('mentions', 'Mentions only', Icons.alternate_email_rounded),
            ('none', 'Muted', Icons.notifications_off_outlined),
          ])
            _InfoRow(
              icon: option.$1 == viewer.notificationLevel
                  ? Icons.check_circle_rounded
                  : option.$3,
              label: option.$2,
              onTap: () => Navigator.of(sheetContext).pop(option.$1),
            ),
        ],
      ),
    );
    if (selected == null || selected == viewer.notificationLevel) return;
    await _run(
      () => _api.setNotificationLevel(widget.conversationId, selected),
      success: 'Notification preference updated.',
    );
  }

  Future<void> _deleteGroup() async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Delete this group?',
      message:
          'The conversation, messages, calls and memberships are permanently '
          'removed for everyone. This cannot be undone.',
      confirmLabel: 'Delete group',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _api.deleteGroup(widget.conversationId);
    } on KlectError catch (error) {
      if (mounted) KToast.error(context, groupErrorCopy(error));
      return;
    }
    if (!mounted) return;
    KToast.success(context, 'Group deleted.');
    context.go(Routes.messages);
  }

  void _openSharedMedia(Conversation conversation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _GroupMediaScreen(
          conversationId: widget.conversationId,
          title: conversation.displayTitle,
        ),
      ),
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
    required GroupRoleAffordances affordances,
  }) async {
    final profile = member.profile;
    // The row only carries a manage control when [GroupRoleAffordances.any] is
    // true, so this guard is unreachable through the UI; it stands so that no
    // future caller can open a sheet whose only content is "View profile".
    if (profile == null || !affordances.any) return;
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
          if (affordances.canPromoteToAdmin)
            _InfoRow(
              icon: Icons.shield_outlined,
              label: 'Make admin',
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_setRole(member, 'admin'));
              },
            ),
          if (affordances.canDemoteToMember)
            _InfoRow(
              icon: Icons.remove_moderator_outlined,
              label: 'Remove as admin',
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_setRole(member, 'member'));
              },
            ),
          if (affordances.canTransferOwnership)
            _InfoRow(
              icon: Icons.swap_horiz_rounded,
              label: 'Transfer ownership',
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_setRole(member, 'owner'));
              },
            ),
          if (affordances.canRemove)
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

    // 13.1: the body is never blank. Until the conversation row is in hand the
    // screen renders a loading indicator, and it keeps rendering one when the
    // fetch resolved with neither a row nor an error — only a real failure
    // trades the indicator for the retryable error state.
    if (conversation == null) {
      final error = state.error;
      return KScaffold(
        appBar: const KFixedAppBar(title: 'Group info', showBack: true),
        body: error == null
            ? const KSkeletonList(rows: 6, showMedia: false)
            : KErrorState(
                error: error,
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

    final accepted = <ConversationMember>[
      for (final member in state.members)
        if (member.isActive && member.requestState == 'accepted') member,
    ]..sort(_byRoleThenTenure);
    final pending = <ConversationMember>[
      for (final member in state.members)
        if (member.isActive && member.requestState == 'pending') member,
    ]..sort(_byRoleThenTenure);
    // Every row the server counts towards the ceiling, pending ones included.
    final activeRows = accepted.length + pending.length;
    final viewer = _memberOf(accepted, viewerId);
    String? groupOwnerId;
    for (final member in accepted) {
      if (member.role == 'owner') {
        groupOwnerId = member.userId;
        break;
      }
    }
    groupOwnerId ??= conversation.createdBy;
    // Ownership transfer, join approval, the three policy scopes and deletion
    // stay owner-only (13.6); role management is resolved per row by
    // [GroupRoleAffordances], which admits admins too (13.5).
    final viewerIsOwner = viewer?.role == 'owner';
    final canEditInfo = conversation.groupPolicy.editInfo.allows(viewer?.role);
    final canAddMembers = conversation.groupPolicy.addMembers.allows(
      viewer?.role,
    );
    final query = _memberQuery.trim().toLowerCase();
    final visibleMembers = query.isEmpty
        ? accepted
        : <ConversationMember>[
            for (final member in accepted)
              if ((member.profile?.name.toLowerCase().contains(query) ??
                      false) ||
                  (member.profile?.username.toLowerCase().contains(query) ??
                      false))
                member,
          ];

    return KScaffold(
      appBar: KFixedAppBar(
        title: 'Group info',
        showBack: true,
        actions: <Widget>[
          if (canEditInfo)
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
          _Header(
            conversation: conversation,
            memberCount: accepted.length,
            onAvatarTap: canEditInfo
                ? () => unawaited(_avatarActions(conversation))
                : null,
          ),
          const SizedBox(height: Space.s6),
          Text(
            'Group controls',
            style: context.kt.label.copyWith(color: context.kc.textSecondary),
          ),
          const SizedBox(height: Space.s1),
          // 13.8: an account holding no membership row has no notification
          // level to set, so the row is absent rather than present and inert.
          // An inert row still swallows the tap and still occupies a slot in
          // the assistive-technology focus order, which reads as an affordance
          // that is there but broken.
          if (viewer case final viewerMember?)
            _InfoRow(
              icon: Icons.notifications_outlined,
              label: 'Notifications',
              detail: switch (viewerMember.notificationLevel) {
                'mentions' => 'Mentions only',
                'none' => 'Muted',
                _ => 'All messages',
              },
              onTap: () => unawaited(_notificationSettings(viewerMember)),
            ),
          _InfoRow(
            icon: Icons.photo_library_outlined,
            label: 'Shared media',
            detail: 'Photos from this conversation',
            onTap: () => _openSharedMedia(conversation),
          ),
          if (groupOwnerId != null)
            _InfoRow(
              icon: Icons.flag_outlined,
              label: 'Report group',
              destructive: true,
              onTap: () => unawaited(
                KReportSheet.showForGroup(
                  context,
                  conversationId: conversation.id,
                  reportedUserId: groupOwnerId!,
                  subjectLabel: conversation.displayTitle,
                ),
              ),
            ),
          if (canAddMembers)
            _InfoRow(
              icon: Icons.link_rounded,
              label: 'Invite link',
              detail: conversation.inviteTokenPrefix == null
                  ? 'No active invite'
                  : 'Active · ${conversation.inviteTokenPrefix}…',
              onTap: () => unawaited(_showInvite(conversation)),
            ),
          if (viewerIsOwner) ...<Widget>[
            _InfoRow(
              icon: Icons.how_to_reg_outlined,
              label: 'Approve new members',
              detail: conversation.joinApprovalRequired ? 'On' : 'Off',
              onTap: () => unawaited(
                _setJoinApproval(!conversation.joinApprovalRequired),
              ),
            ),
            _InfoRow(
              icon: Icons.edit_note_rounded,
              label: 'Who can edit group info',
              detail: conversation.groupPolicy.editInfo.label,
              onTap: () => unawaited(
                _setPolicy(conversation, _GroupPolicyField.editInfo),
              ),
            ),
            _InfoRow(
              icon: Icons.group_add_outlined,
              label: 'Who can add members',
              detail: conversation.groupPolicy.addMembers.label,
              onTap: () => unawaited(
                _setPolicy(conversation, _GroupPolicyField.addMembers),
              ),
            ),
            _InfoRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Who can send messages',
              detail: conversation.groupPolicy.sendMessages.label,
              onTap: () => unawaited(
                _setPolicy(conversation, _GroupPolicyField.sendMessages),
              ),
            ),
          ],
          if (canAddMembers && pending.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.s6),
            Text(
              'Join requests · ${pending.length}',
              style: context.kt.label.copyWith(color: context.kc.textSecondary),
            ),
            const SizedBox(height: Space.s1),
            for (final member in pending)
              _JoinRequestRow(
                member: member,
                onAccept: () => unawaited(_reviewJoin(member, accept: true)),
                onDecline: () => unawaited(_reviewJoin(member, accept: false)),
              ),
          ],
          const SizedBox(height: Space.s6),
          _MembersHeader(
            count: accepted.length,
            onAdd: canAddMembers && activeRows < _maxActiveMembers
                ? () => unawaited(_addMembers(accepted, pending))
                : null,
          ),
          if (accepted.length > 5) ...<Widget>[
            const SizedBox(height: Space.s2),
            KTextField(
              hint: 'Search members',
              prefixIcon: Icons.search_rounded,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _memberQuery = value),
            ),
          ],
          const SizedBox(height: Space.s1),
          for (final member in visibleMembers)
            _MemberRow(
              member: member,
              isSelf: member.userId == viewerId,
              // Only rows the viewer can actually act on get the sheet, and
              // the same rule decides what the sheet contains — so no row can
              // open onto an empty sheet or an action the RPC would refuse.
              affordances: GroupRoleAffordances(
                viewerRole: viewer?.role,
                targetRole: member.role,
                isSelf: member.userId == viewerId,
              ),
              onActions: (GroupRoleAffordances affordances) =>
                  unawaited(_memberActions(member, affordances: affordances)),
            ),
          const SizedBox(height: Space.s6),
          Divider(height: Strokes.hairline, color: context.kc.borderSubtle),
          const SizedBox(height: Space.s2),
          _InfoRow(
            icon: Icons.logout_rounded,
            label: 'Leave group',
            destructive: true,
            onTap: () => unawaited(
              _leave(isOwner: viewerIsOwner, othersCount: accepted.length - 1),
            ),
          ),
          if (viewerIsOwner)
            _InfoRow(
              icon: Icons.delete_forever_outlined,
              label: 'Delete group for everyone',
              destructive: true,
              onTap: () => unawaited(_deleteGroup()),
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

enum _GroupPolicyField { editInfo, addMembers, sendMessages }

extension on _GroupPolicyField {
  String get title => switch (this) {
    _GroupPolicyField.editInfo => 'Edit group info',
    _GroupPolicyField.addMembers => 'Add members',
    _GroupPolicyField.sendMessages => 'Send messages',
  };
}

class _JoinRequestRow extends StatelessWidget {
  const _JoinRequestRow({
    required this.member,
    required this.onAccept,
    required this.onDecline,
  });

  final ConversationMember member;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final profile = member.profile;
    if (profile == null) return const SizedBox.shrink();
    return PersonRow(
      profile: profile,
      dense: true,
      showFollow: false,
      subtitle: 'Wants to join',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          KIconButton(
            icon: Icons.close_rounded,
            semanticLabel: 'Decline ${profile.name}',
            onPressed: onDecline,
          ),
          KIconButton(
            icon: Icons.check_rounded,
            semanticLabel: 'Accept ${profile.name}',
            onPressed: onAccept,
          ),
        ],
      ),
    );
  }
}

class _GroupMediaScreen extends ConsumerStatefulWidget {
  const _GroupMediaScreen({required this.conversationId, required this.title});

  final String conversationId;
  final String title;

  @override
  ConsumerState<_GroupMediaScreen> createState() => _GroupMediaScreenState();
}

class _GroupMediaScreenState extends ConsumerState<_GroupMediaScreen> {
  late Future<List<ChatAttachment>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(chatApiProvider).fetchSharedMedia(widget.conversationId);
  }

  void _retry() {
    setState(() {
      _future = ref
          .read(chatApiProvider)
          .fetchSharedMedia(widget.conversationId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(chatApiProvider);
    return KScaffold(
      appBar: KFixedAppBar(
        title: 'Shared media - ${widget.title}',
        showBack: true,
      ),
      body: FutureBuilder<List<ChatAttachment>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const KSkeletonList(rows: 6);
          }
          if (snapshot.hasError) {
            return KErrorState(error: snapshot.error, onRetry: _retry);
          }
          final media = snapshot.data ?? const <ChatAttachment>[];
          if (media.isEmpty) {
            return const KEmptyState(
              title: 'No shared photos yet',
              message: 'Photos sent in this conversation will collect here.',
              icon: Icons.photo_library_outlined,
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(Space.s2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: Space.s05,
              mainAxisSpacing: Space.s05,
            ),
            itemCount: media.length,
            itemBuilder: (context, index) =>
                _PrivateMediaTile(api: api, attachment: media[index]),
          );
        },
      ),
    );
  }
}

class _PrivateMediaTile extends StatefulWidget {
  const _PrivateMediaTile({required this.api, required this.attachment});

  final ChatApi api;
  final ChatAttachment attachment;

  @override
  State<_PrivateMediaTile> createState() => _PrivateMediaTileState();
}

class _PrivateMediaTileState extends State<_PrivateMediaTile> {
  late final Future<String> _url = widget.api.signedUrl(
    widget.attachment.storagePath,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _url,
    builder: (context, snapshot) {
      if (!snapshot.hasData) {
        return ColoredBox(color: context.kc.surface2);
      }
      return KBlurhashImage(
        url: snapshot.data,
        blurhash: widget.attachment.blurhash,
        aspectRatio: 1,
        borderRadius: BorderRadius.circular(Radii.xs),
        semanticLabel: 'Shared photo',
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────── sections ──

class _Header extends ConsumerWidget {
  const _Header({
    required this.conversation,
    required this.memberCount,
    this.onAvatarTap,
  });

  final Conversation conversation;
  final int memberCount;

  /// Non-null only for a viewer whose Member_Role satisfies the `edit_info`
  /// scope. Null means the avatar renders as a plain image with no gesture
  /// wrapper at all (13.8).
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(conversation.avatarPath, bucket: StorageBucket.avatars);
    final description = conversation.description;
    final avatar = GroupAvatar(
      imageUrl: avatarUrl,
      name: conversation.displayTitle,
      size: Space.s20,
    );

    return Column(
      children: <Widget>[
        // 13.8: the whole edit affordance — the press target and its badge —
        // exists only when the viewer's role satisfies `edit_info`. A
        // `KPressable` with a null `onTap` still hit-tests opaque, so it would
        // silently swallow taps over the avatar; the fix is not to build it.
        if (onAvatarTap case final onAvatarTap?)
          KPressable(
            semanticLabel: 'Change group photo',
            onTap: onAvatarTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                avatar,
                Positioned(
                  right: -Space.s1,
                  bottom: -Space.s1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.accentDefault,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.surface1,
                        width: Strokes.thick,
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(Space.s15),
                      child: Icon(
                        Icons.edit_outlined,
                        size: Space.s4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          avatar,
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
            style: context.kt.label.copyWith(color: context.kc.textSecondary),
          ),
        ),
        // 13.8: withheld by absence, never by a disabled button. A disabled
        // button still reads as "Add" to a screen reader and still occupies a
        // focus stop, which promises something the RPC would refuse.
        if (onAdd case final onAdd?)
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
    required this.affordances,
    required this.onActions,
  });

  final ConversationMember member;
  final bool isSelf;

  /// What this viewer may do to this member — decides both whether the manage
  /// control exists and what the sheet behind it offers.
  final GroupRoleAffordances affordances;

  final void Function(GroupRoleAffordances affordances) onActions;

  /// Every member carries exactly one badge, so the list reads as a roster
  /// rather than a list with two decorated rows (13.2). An unknown wire role
  /// lands on `Member`, the least privileged label, which is also how the
  /// server treats it.
  static String _roleLabel(String role) => switch (role) {
    'owner' => 'Owner',
    'admin' => 'Admin',
    _ => 'Member',
  };

  @override
  Widget build(BuildContext context) {
    final profile = member.profile;
    if (profile == null) return const SizedBox.shrink();
    final role = member.role;

    return PersonRow(
      profile: profile,
      dense: true,
      showFollow: false,
      subtitle: isSelf ? 'You · ${profile.handle}' : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          KChip(
            label: _roleLabel(role),
            dense: true,
            // The two roles that carry authority take the accent; a plain
            // member reads as metadata.
            selected: role == 'owner' || role == 'admin',
          ),
          if (affordances.any) ...<Widget>[
            const SizedBox(width: Space.s2),
            KIconButton(
              icon: Icons.more_horiz_rounded,
              semanticLabel: 'Manage ${profile.name}',
              onPressed: () => onActions(affordances),
            ),
          ],
        ],
      ),
    );
  }
}

/// One tappable settings line.
///
/// [onTap] is deliberately non-nullable (13.8). A row is either an affordance
/// the viewer's role satisfies — in which case it acts — or it is not built at
/// all. There is no third state: an inert row would still absorb its own hit
/// test and would still be announced, so the type system is what keeps a
/// caller from reaching for one.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.detail,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final String? detail;

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
                  if (detail case final detail?)
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.kt.caption.copyWith(
                        color: colors.textTertiary,
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
  }) => KSheet.show<({String title, String description})>(
    context: context,
    title: 'Edit group',
    builder: (_) => _EditGroupSheet(title: title, description: description),
  );

  @override
  State<_EditGroupSheet> createState() => _EditGroupSheetState();
}

class _EditGroupSheetState extends State<_EditGroupSheet> {
  late final TextEditingController _title = TextEditingController(
    text: widget.title,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.description,
  );
  String? _titleError;
  String? _descriptionError;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final description = _description.text.trim();
    final titleLength = title.characters.length;
    final descriptionLength = description.characters.length;
    if (titleLength < 1 || titleLength > 60 || descriptionLength > 500) {
      setState(() {
        _titleError = titleLength < 1
            ? 'A group title is required.'
            : titleLength > 60
            ? 'Group titles can have at most 60 characters.'
            : null;
        _descriptionError = descriptionLength > 500
            ? 'Descriptions can have at most 500 characters.'
            : null;
      });
      return;
    }
    Navigator.of(context).pop((title: title, description: description));
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
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            errorText: _titleError,
            onChanged: (_) {
              if (_titleError != null) setState(() => _titleError = null);
            },
          ),
          const SizedBox(height: Space.s4),
          KTextField(
            controller: _description,
            label: 'Description',
            hint: 'Optional — what belongs in here',
            maxLines: 3,
            minLines: 2,
            maxLength: 500,
            errorText: _descriptionError,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_descriptionError != null) {
                setState(() => _descriptionError = null);
              }
            },
          ),
          const SizedBox(height: Space.s5),
          KButton(label: 'Save', expand: true, onPressed: _save),
        ],
      ),
    );
  }
}
