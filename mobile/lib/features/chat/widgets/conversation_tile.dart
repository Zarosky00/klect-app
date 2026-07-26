import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/klect_api.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../chat_models.dart';
import 'swipe_actions.dart';

/// One row of the inbox.
///
/// At rest it is the conversation and nothing else. Mute, archive and delete
/// live behind a left swipe, and the same three are on the long press so the
/// gesture is never the only way in.
class ConversationTile extends ConsumerWidget {
  /// Creates an inbox row.
  const ConversationTile({
    required this.entry,
    required this.onTap,
    required this.onTogglePin,
    required this.onToggleMute,
    required this.onToggleArchive,
    required this.onDelete,
    super.key,
  });

  /// The conversation, as the viewer sees it.
  final ChatInboxEntry entry;

  /// Opens the thread.
  final VoidCallback onTap;

  /// Pins or unpins.
  final VoidCallback onTogglePin;

  /// Mutes or unmutes.
  final VoidCallback onToggleMute;

  /// Archives or un-archives.
  final VoidCallback onToggleArchive;

  /// Leaves the conversation.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final conversation = entry.conversation;
    final other = conversation.otherMember;
    final unread = entry.unreadCount;
    final avatarUrl = ref.watch(klectApiProvider).publicUrl(
          conversation.kind == ConversationKind.dm
              ? other?.avatarPath
              : conversation.avatarPath,
          bucket: StorageBucket.avatars,
        );

    return KSwipeActions(
      actions: <SwipeAction>[
        SwipeAction(
          icon: entry.isMuted
              ? Icons.notifications_active_outlined
              : Icons.notifications_off_outlined,
          label: entry.isMuted ? 'Unmute' : 'Mute',
          onPressed: onToggleMute,
        ),
        SwipeAction(
          icon: entry.isArchived
              ? Icons.unarchive_outlined
              : Icons.archive_outlined,
          label: entry.isArchived ? 'Restore' : 'Archive',
          onPressed: onToggleArchive,
        ),
        SwipeAction(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          destructive: true,
          onPressed: onDelete,
        ),
      ],
      child: KPressable(
        onTap: onTap,
        onLongPress: () => _openMenu(context),
        enforceMinTapTarget: false,
        semanticLabel: _semanticLabel,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s4,
            vertical: Space.s3,
          ),
          child: Row(
            children: <Widget>[
              KAvatar(
                size: Space.s12,
                imageUrl: avatarUrl,
                name: conversation.displayTitle,
                isVerified: other?.isVerified ?? false,
                showRing: unread > 0,
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (entry.pinned) ...<Widget>[
                          Icon(
                            Icons.push_pin_rounded,
                            size: Space.s4,
                            color: colors.accentDefault,
                          ),
                          const SizedBox(width: Space.s1),
                        ],
                        Flexible(
                          child: Text(
                            conversation.displayTitle,
                            style: unread > 0
                                ? text.bodyStrong
                                : text.body.copyWith(color: colors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.isMuted) ...<Widget>[
                          const SizedBox(width: Space.s1),
                          Icon(
                            Icons.notifications_off_rounded,
                            size: Space.s4,
                            color: colors.textTertiary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Space.s05),
                    Text(
                      conversation.lastMessagePreview ?? 'Say something',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.callout.copyWith(
                        color: unread > 0
                            ? colors.textSecondary
                            : colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s3),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _relative(conversation.lastMessageAt),
                    style: text.micro.copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: Space.s1),
                  if (unread > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: Space.s5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: Space.s15,
                        vertical: Space.s05,
                      ),
                      decoration: BoxDecoration(
                        color: entry.isMuted
                            ? colors.surface4
                            : colors.accentDefault,
                        borderRadius: BorderRadius.circular(Radii.full),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        textAlign: TextAlign.center,
                        style: text.count.copyWith(
                          color: entry.isMuted
                              ? colors.textSecondary
                              : colors.textOnAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _semanticLabel {
    final parts = <String>[
      entry.conversation.displayTitle,
      if (entry.conversation.lastMessagePreview != null)
        entry.conversation.lastMessagePreview!,
      if (entry.unreadCount > 0) '${entry.unreadCount} unread',
      if (entry.isMuted) 'muted',
      if (entry.pinned) 'pinned',
    ];
    return parts.join(', ');
  }

  Future<void> _openMenu(BuildContext context) => KSheet.show<void>(
        context: context,
        title: entry.conversation.displayTitle,
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _MenuRow(
              icon: entry.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded,
              label: entry.pinned ? 'Unpin' : 'Pin to top',
              onTap: () {
                Navigator.of(sheetContext).pop();
                onTogglePin();
              },
            ),
            _MenuRow(
              icon: entry.isMuted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
              label: entry.isMuted ? 'Unmute' : 'Mute for a week',
              onTap: () {
                Navigator.of(sheetContext).pop();
                onToggleMute();
              },
            ),
            _MenuRow(
              icon: entry.isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              label: entry.isArchived ? 'Move to inbox' : 'Archive',
              onTap: () {
                Navigator.of(sheetContext).pop();
                onToggleArchive();
              },
            ),
            _MenuRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete conversation',
              destructive: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                onDelete();
              },
            ),
          ],
        ),
      );

  static String _relative(DateTime? at) {
    if (at == null) return '';
    return timeago.format(at, locale: 'en_short');
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
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
            Text(label, style: context.kt.body.copyWith(color: tint)),
          ],
        ),
      ),
    );
  }
}
