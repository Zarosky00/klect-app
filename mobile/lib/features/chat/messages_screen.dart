import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../router.dart';
import '../../ui/ui.dart';
import 'chat_models.dart';
import 'inbox_controller.dart';
import 'widgets/conversation_tile.dart';
import 'widgets/incoming_call_overlay.dart';

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

  ChatInboxController get _inbox => ref.read(chatInboxProvider.notifier);

  void _open(ChatInboxEntry entry) {
    _inbox.markReadLocally(entry.id);
    context.push('${Routes.messages}/${entry.id}');
  }

  Future<void> _delete(ChatInboxEntry entry) async {
    final isGroup = entry.conversation.kind == ConversationKind.group;
    final confirmed = await KConfirmDialog.show(
      context,
      title:
          isGroup ? 'Leave this group?' : 'Delete this conversation?',
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatInboxProvider);
    final archivedCount = state.archived.length;
    final entries = _showArchived ? state.archived : state.active;

    ref.listen(chatInboxProvider.select((s) => s.error), (_, error) {
      if (error == null || !mounted) return;
      KToast.error(context, 'That did not stick. Try once more.');
      _inbox.clearError();
    });

    return IncomingCallOverlay(
      child: KScaffold(
        appBar: KFixedAppBar(
          title: _showArchived ? 'Archived' : 'Messages',
          showBack: true,
          actions: <Widget>[
            if (archivedCount > 0 || _showArchived)
              KIconButton(
                icon: _showArchived
                    ? Icons.inbox_rounded
                    : Icons.archive_outlined,
                semanticLabel:
                    _showArchived ? 'Back to inbox' : 'Archived conversations',
                onPressed: () =>
                    setState(() => _showArchived = !_showArchived),
              ),
            KIconButton(
              icon: Icons.group_add_outlined,
              semanticLabel: 'New group',
              onPressed: () => context.push('${Routes.messages}/new-group'),
            ),
            KIconButton(
              icon: Icons.person_search_rounded,
              semanticLabel: 'Find collectors',
              onPressed: () => context.push(Routes.matches),
            ),
          ],
        ),
        onRefresh: _inbox.refresh,
        body: _Body(
          state: state,
          entries: entries,
          showArchived: _showArchived,
          onOpen: _open,
          onDelete: (entry) => unawaited(_delete(entry)),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.state,
    required this.entries,
    required this.showArchived,
    required this.onOpen,
    required this.onDelete,
  });

  final ChatInboxState state;
  final List<ChatInboxEntry> entries;
  final bool showArchived;
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
        onRetry: () => unawaited(ref.read(chatInboxProvider.notifier).refresh()),
      );
    }
    if (entries.isEmpty) {
      return ListView(
        children: <Widget>[
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          showArchived
              ? const KEmptyState(
                  title: 'Nothing archived',
                  message: 'Conversations you tuck away land here.',
                  icon: Icons.archive_outlined,
                )
              : KEmptyState(
                  title: 'No conversations yet',
                  message: 'Find collectors whose taste overlaps yours, then '
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
