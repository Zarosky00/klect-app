import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../chat_models.dart';
import '../inbox_controller.dart';

/// Pick one or more conversations to forward a message into.
///
/// Reuses the live inbox — same rows, same order (pinned first, then most
/// recent) — because the places you forward to are exactly the places you
/// already talk. Multi-select, then one confirm.
abstract final class ForwardSheet {
  /// Opens the picker and resolves with the chosen conversations, or null.
  static Future<List<ChatInboxEntry>?> show(BuildContext context) =>
      KSheet.show<List<ChatInboxEntry>>(
        context: context,
        title: 'Forward to',
        maxHeightFraction: 0.85,
        builder: (_) => const _ForwardBody(),
      );
}

class _ForwardBody extends ConsumerStatefulWidget {
  const _ForwardBody();

  @override
  ConsumerState<_ForwardBody> createState() => _ForwardBodyState();
}

class _ForwardBodyState extends ConsumerState<_ForwardBody> {
  final Set<String> _selected = <String>{};

  void _toggle(String conversationId) {
    setState(() {
      if (!_selected.remove(conversationId)) _selected.add(conversationId);
    });
  }

  void _confirm(List<ChatInboxEntry> entries) {
    final picked = <ChatInboxEntry>[
      for (final entry in entries)
        if (_selected.contains(entry.id)) entry,
    ];
    Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatInboxProvider);
    final entries = state.entries;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: _buildList(state, entries)),
          const SizedBox(height: Space.s3),
          KButton(
            label: _selected.length > 1
                ? 'Forward to ${_selected.length} conversations'
                : 'Forward',
            icon: Icons.forward_rounded,
            expand: true,
            onPressed: _selected.isEmpty ? null : () => _confirm(entries),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ChatInboxState state, List<ChatInboxEntry> entries) {
    if (state.loading && entries.isEmpty) {
      return const KSkeletonList(rows: 4, showMedia: false);
    }
    if (entries.isEmpty) {
      return const KEmptyState(
        title: 'Nowhere to forward',
        message: 'Start a conversation first, then forward into it.',
        icon: Icons.forum_outlined,
        compact: true,
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _TargetRow(
          entry: entry,
          selected: _selected.contains(entry.id),
          onTap: () => _toggle(entry.id),
        );
      },
    );
  }
}

class _TargetRow extends ConsumerWidget {
  const _TargetRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final ChatInboxEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final conversation = entry.conversation;
    final other = conversation.otherMember;
    final avatarUrl = ref.watch(klectApiProvider).publicUrl(
          conversation.kind == ConversationKind.dm
              ? other?.avatarPath
              : conversation.avatarPath,
          bucket: StorageBucket.avatars,
        );

    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: selected
          ? '${conversation.displayTitle}, selected'
          : conversation.displayTitle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s2),
        child: Row(
          children: <Widget>[
            KAvatar(
              size: Space.s10,
              imageUrl: avatarUrl,
              name: conversation.displayTitle,
              isVerified: other?.isVerified ?? false,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(
                conversation.displayTitle,
                style: context.kt.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: Space.s3),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: Space.s6,
              color: selected ? colors.accentDefault : colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
