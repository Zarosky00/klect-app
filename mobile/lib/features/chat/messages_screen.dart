import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_error.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import 'chat_api.dart';
import 'chat_models.dart';
import 'group_errors.dart';
import 'inbox_controller.dart';
import 'widgets/conversation_tile.dart';

/// The inbox.
///
/// Live: a new message reorders the list under your thumb, an unread badge
/// clears the moment the other device reads it, and pin / archive / mute are
/// per-viewer flags on the membership row rather than shared state.
class MessagesScreen extends ConsumerStatefulWidget {
  /// Creates the inbox.
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  bool _showArchived = false;
  _InboxFilter _filter = _InboxFilter.all;
  String _query = '';

  ChatInboxController get _inbox => ref.read(chatInboxProvider.notifier);

  void _open(ChatInboxEntry entry) {
    _inbox.markReadLocally(entry.id);
    context.push('${Routes.messages}/${entry.id}');
  }

  Future<void> _delete(ChatInboxEntry entry) async {
    final isGroup = entry.conversation.kind == ConversationKind.group;
    final confirmed = await KConfirmDialog.show(
      context,
      title: isGroup ? 'Leave this group?' : 'Delete this conversation?',
      message: isGroup
          ? 'You leave ${entry.conversation.displayTitle} and it disappears '
                'from your inbox. An admin can add you back later.'
          : 'It disappears from your inbox. '
                '${entry.conversation.displayTitle} keeps their copy, and '
                'messaging again reopens the same thread.',
      confirmLabel: isGroup ? 'Leave' : 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    await _inbox.leave(entry.id);
  }

  Future<void> _joinGroup() async {
    final token = await _JoinGroupSheet.show(context);
    if (token == null || !mounted) return;
    try {
      final result = await ref.read(chatApiProvider).joinGroupInvite(token);
      await _inbox.refresh();
      if (!mounted) return;
      if (result.state == 'accepted') {
        KToast.success(context, 'You joined the group.');
        unawaited(context.push('${Routes.messages}/${result.conversationId}'));
      } else {
        KToast.success(context, 'Join request sent.');
        setState(() => _filter = _InboxFilter.requests);
      }
    } on KlectError catch (error) {
      if (mounted) KToast.error(context, groupErrorCopy(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatInboxProvider);
    final archivedCount = state.archived.length;
    final source = _showArchived ? state.archived : state.active;
    final entries = <ChatInboxEntry>[
      for (final entry in source)
        if (_matchesFilter(entry) && _matchesSearch(entry)) entry,
    ];

    ref.listen(chatInboxProvider.select((s) => s.error), (_, error) {
      if (error == null || !mounted) return;
      KToast.error(context, 'That did not stick. Try once more.');
      _inbox.clearError();
    });

    return KScaffold(
      appBar: KFixedAppBar(
        title: _showArchived ? 'Archived' : 'Messages',
        showBack: true,
        actions: <Widget>[
          if (archivedCount > 0 || _showArchived)
            KIconButton(
              icon: _showArchived
                  ? Icons.inbox_rounded
                  : Icons.archive_outlined,
              semanticLabel: _showArchived
                  ? 'Back to inbox'
                  : 'Archived conversations',
              onPressed: () => setState(() => _showArchived = !_showArchived),
            ),
          KIconButton(
            icon: Icons.group_add_outlined,
            semanticLabel: 'New group',
            onPressed: () => context.push('${Routes.messages}/new-group'),
          ),
          KIconButton(
            icon: Icons.add_link_rounded,
            semanticLabel: 'Join with invite code',
            onPressed: () => unawaited(_joinGroup()),
          ),
          KIconButton(
            icon: Icons.person_search_rounded,
            semanticLabel: 'Find collectors',
            onPressed: () => context.push(Routes.matches),
          ),
        ],
      ),
      onRefresh: _inbox.refresh,
      body: Column(
        children: <Widget>[
          if (!_showArchived)
            _InboxControls(
              filter: _filter,
              onFilterChanged: (filter) => setState(() => _filter = filter),
              onQueryChanged: (query) => setState(() => _query = query),
            ),
          Expanded(
            child: _Body(
              state: state,
              entries: entries,
              showArchived: _showArchived,
              filtered:
                  !_showArchived &&
                  (_filter != _InboxFilter.all || _query.trim().isNotEmpty),
              onOpen: _open,
              onDelete: (entry) => unawaited(_delete(entry)),
            ),
          ),
        ],
      ),
    );
  }

  bool _matchesFilter(ChatInboxEntry entry) => switch (_filter) {
    _InboxFilter.all => !entry.isRequest,
    _InboxFilter.unread => !entry.isRequest && entry.unreadCount > 0,
    _InboxFilter.people =>
      !entry.isRequest && entry.conversation.kind == ConversationKind.dm,
    _InboxFilter.groups =>
      !entry.isRequest && entry.conversation.kind == ConversationKind.group,
    _InboxFilter.requests => entry.isRequest,
  };

  bool _matchesSearch(ChatInboxEntry entry) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final conversation = entry.conversation;
    return conversation.displayTitle.toLowerCase().contains(query) ||
        (conversation.otherMember?.username.toLowerCase().contains(query) ??
            false) ||
        (conversation.lastMessagePreview?.toLowerCase().contains(query) ??
            false);
  }
}

class _JoinGroupSheet extends StatefulWidget {
  const _JoinGroupSheet();

  static Future<String?> show(BuildContext context) => KSheet.show<String>(
    context: context,
    title: 'Join a group',
    builder: (_) => const _JoinGroupSheet(),
  );

  @override
  State<_JoinGroupSheet> createState() => _JoinGroupSheetState();
}

class _JoinGroupSheetState extends State<_JoinGroupSheet> {
  final TextEditingController _code = TextEditingController();
  bool _missing = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _missing = true);
      return;
    }
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        'Paste the private code an admin shared with you.',
        style: context.kt.body.copyWith(color: context.kc.textSecondary),
      ),
      const SizedBox(height: Space.s4),
      KTextField(
        controller: _code,
        label: 'Invite code',
        hint: 'Paste code',
        autofocus: true,
        errorText: _missing ? 'Paste an invite code first.' : null,
        onChanged: (_) {
          if (_missing) setState(() => _missing = false);
        },
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: Space.s4),
      KButton(label: 'Continue', expand: true, onPressed: _submit),
    ],
  );
}

enum _InboxFilter { all, unread, people, groups, requests }

extension on _InboxFilter {
  String get label => switch (this) {
    _InboxFilter.all => 'All',
    _InboxFilter.unread => 'Unread',
    _InboxFilter.people => 'People',
    _InboxFilter.groups => 'Groups',
    _InboxFilter.requests => 'Requests',
  };
}

class _InboxControls extends StatelessWidget {
  const _InboxControls({
    required this.filter,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  final _InboxFilter filter;
  final ValueChanged<_InboxFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s4,
          Space.s2,
          Space.s4,
          Space.s2,
        ),
        child: KTextField(
          hint: 'Search conversations',
          prefixIcon: Icons.search_rounded,
          onChanged: onQueryChanged,
          textInputAction: TextInputAction.search,
        ),
      ),
      SizedBox(
        height: Space.s10,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.s4),
          itemCount: _InboxFilter.values.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.s2),
          itemBuilder: (context, index) {
            final candidate = _InboxFilter.values[index];
            return KChip(
              label: candidate.label,
              selected: candidate == filter,
              onTap: () => onFilterChanged(candidate),
            );
          },
        ),
      ),
      const SizedBox(height: Space.s2),
    ],
  );
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.state,
    required this.entries,
    required this.showArchived,
    required this.filtered,
    required this.onOpen,
    required this.onDelete,
  });

  final ChatInboxState state;
  final List<ChatInboxEntry> entries;
  final bool showArchived;
  final bool filtered;
  final void Function(ChatInboxEntry entry) onOpen;
  final void Function(ChatInboxEntry entry) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.loading && state.entries.isEmpty) {
      return const KSkeletonList(rows: 6, showMedia: false);
    }
    if (state.error != null && state.entries.isEmpty) {
      return KErrorState(
        error: state.error,
        onRetry: () =>
            unawaited(ref.read(chatInboxProvider.notifier).refresh()),
      );
    }
    if (entries.isEmpty) {
      return ListView(
        children: <Widget>[
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          filtered
              ? const KEmptyState(
                  title: 'No matches',
                  message: 'Try another filter or search.',
                  icon: Icons.filter_alt_off_rounded,
                )
              : showArchived
              ? const KEmptyState(
                  title: 'Nothing archived',
                  message: 'Conversations you tuck away land here.',
                  icon: Icons.archive_outlined,
                )
              : KEmptyState(
                  title: 'No conversations yet',
                  message:
                      'Find collectors whose taste overlaps yours, then '
                      'say something about a collection you both love.',
                  icon: Icons.forum_outlined,
                  actionLabel: 'Find collectors',
                  onAction: () => context.push(Routes.matches),
                  secondaryActionLabel: 'Search KLECT',
                  onSecondaryAction: () => context.push(Routes.search),
                ),
        ],
      );
    }

    final controller = ref.read(chatInboxProvider.notifier);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: Space.s20),
      itemCount: entries.length,
      separatorBuilder: (context, _) => Divider(
        height: Strokes.hairline,
        indent: Space.s16,
        color: context.kc.borderSubtle,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _Entrance(
          index: index,
          child: ConversationTile(
            key: ValueKey<String>(entry.id),
            entry: entry,
            onTap: () => onOpen(entry),
            onTogglePin: () => unawaited(controller.togglePin(entry.id)),
            onToggleMute: () => unawaited(controller.toggleMute(entry.id)),
            onToggleArchive: () =>
                unawaited(controller.toggleArchive(entry.id)),
            onDelete: () => onDelete(entry),
          ),
        );
      },
    );
  }
}

/// Staggered fade + rise, capped by [KMotion.staggerDelay] so a long inbox
/// never feels slow at the bottom.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (KMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: KDurations.base + KMotion.staggerDelay(index, grid: false),
      curve: Curves_.emphasized,
      builder: (context, t, inner) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * Space.s3),
          child: inner,
        ),
      ),
      child: child,
    );
  }
}
