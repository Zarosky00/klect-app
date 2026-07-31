import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../chat_models.dart';

/// The emoji offered without opening a full picker.
///
/// Six is the most a thumb reaches comfortably in one row at 44 pt each; the
/// long tail is not worth the extra surface in a messaging thread.
const List<String> kQuickReactions = <String>[
  '❤️',
  '😂',
  '🔥',
  '👏',
  '😮',
  '🙏',
];

/// Everything you can do to one message, one long-press away.
///
/// "Hidden but easily accessible": a bubble shows only the message. React,
/// reply, edit, delete, copy and report all live behind the long press, and
/// the single most common one — a reaction — is also on the double tap.
abstract final class MessageActionsSheet {
  /// Opens the sheet for [message].
  static Future<void> show(
    BuildContext context, {
    required ChatMessage message,
    required bool isMine,
    required String? viewerId,
    required void Function(String emoji) onReact,
    required VoidCallback onReply,
    required VoidCallback onEdit,
    required VoidCallback onDeleteForEveryone,
    required VoidCallback onDeleteForMe,
    VoidCallback? onForward,
  }) => KSheet.show<void>(
    context: context,
    showHandle: true,
    builder: (_) => _Body(
      message: message,
      isMine: isMine,
      viewerId: viewerId,
      onReact: onReact,
      onReply: onReply,
      onEdit: onEdit,
      onDeleteForEveryone: onDeleteForEveryone,
      onDeleteForMe: onDeleteForMe,
      onForward: onForward,
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.message,
    required this.isMine,
    required this.viewerId,
    required this.onReact,
    required this.onReply,
    required this.onEdit,
    required this.onDeleteForEveryone,
    required this.onDeleteForMe,
    this.onForward,
  });

  final ChatMessage message;
  final bool isMine;
  final String? viewerId;
  final void Function(String emoji) onReact;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDeleteForEveryone;
  final VoidCallback onDeleteForMe;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    if (message.isTombstone) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[_deleteForMeRow(context)],
      );
    }
    final canCopy = message.hasText;
    final canEdit = isMine && message.hasText && !message.pending;
    final authorId = message.authorId;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _QuickReactions(
          message: message,
          viewerId: viewerId,
          onReact: (emoji) {
            Navigator.of(context).pop();
            onReact(emoji);
          },
        ),
        const SizedBox(height: Space.s4),
        _ActionRow(
          icon: Icons.reply_rounded,
          label: 'Reply',
          onTap: () {
            Navigator.of(context).pop();
            onReply();
          },
        ),
        if (onForward != null)
          _ActionRow(
            icon: Icons.forward_rounded,
            label: 'Forward',
            onTap: () {
              Navigator.of(context).pop();
              onForward!();
            },
          ),
        if (canCopy)
          _ActionRow(
            icon: Icons.content_copy_rounded,
            label: 'Copy text',
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: message.message.body ?? ''),
              );
              if (!context.mounted) return;
              Navigator.of(context).pop();
              KToast.success(context, 'Copied');
            },
          ),
        if (canEdit)
          _ActionRow(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onTap: () {
              Navigator.of(context).pop();
              onEdit();
            },
          ),
        if (isMine && !message.pending && !message.failed)
          _ActionRow(
            icon: Icons.delete_outline_rounded,
            label: 'Delete for everyone',
            destructive: true,
            onTap: () async {
              final confirmed = await KConfirmDialog.show(
                context,
                title: 'Delete for everyone?',
                message: 'This leaves a deleted-message marker for everyone.',
                confirmLabel: 'Delete for everyone',
                destructive: true,
              );
              if (!confirmed || !context.mounted) return;
              Navigator.of(context).pop();
              onDeleteForEveryone();
            },
          ),
        _deleteForMeRow(context),
        if (!isMine && authorId != null)
          _ActionRow(
            icon: Icons.flag_outlined,
            label: 'Report',
            destructive: true,
            onTap: () {
              final navigator = Navigator.of(context);
              final label = message.message.author?.name ?? 'this message';
              navigator.pop();
              // `messages` is not an `entity_type`, so a message is reported
              // through its author — which is what moderation acts on anyway.
              unawaited(
                reportMessageAuthor(
                  context,
                  authorId: authorId,
                  subjectLabel: label,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _deleteForMeRow(BuildContext context) => _ActionRow(
    icon: Icons.delete_sweep_outlined,
    label: 'Delete for me',
    destructive: true,
    onTap: () async {
      final confirmed = await KConfirmDialog.show(
        context,
        title: 'Delete for you?',
        message: 'This message disappears only from your account.',
        confirmLabel: 'Delete for me',
        destructive: true,
      );
      if (!confirmed || !context.mounted) return;
      Navigator.of(context).pop();
      onDeleteForMe();
    },
  );
}

class _QuickReactions extends StatelessWidget {
  const _QuickReactions({
    required this.message,
    required this.viewerId,
    required this.onReact,
  });

  final ChatMessage message;
  final String? viewerId;
  final void Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        for (final emoji in kQuickReactions)
          KPressable(
            onTap: () => onReact(emoji),
            semanticLabel: 'React with $emoji',
            child: AnimatedContainer(
              duration: KMotion.duration(context, KDurations.fast),
              curve: Curves_.emphasized,
              width: Layout.tapTargetMin,
              height: Layout.tapTargetMin,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: message.reactedWith(emoji, viewerId)
                    ? colors.accentSubtle
                    : colors.surface2,
                border: Border.all(
                  color: message.reactedWith(emoji, viewerId)
                      ? colors.accentDefault
                      : colors.borderSubtle,
                  width: Strokes.thin,
                ),
              ),
              child: Text(emoji, style: context.kt.title3),
            ),
          ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
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

/// Reports an entity type that has no `entity_type` of its own by reporting
/// its author. Exposed so the conversation screen can offer the same action
/// from its overflow menu.
Future<void> reportMessageAuthor(
  BuildContext context, {
  required String authorId,
  String? subjectLabel,
}) => KReportSheet.showForUser(
  context,
  userId: authorId,
  subjectLabel: subjectLabel,
);

/// Convenience so a caller can report an [EntityType] directly from chat.
Future<void> reportSharedEntity(
  BuildContext context, {
  required EntityType type,
  required String entityId,
}) => KReportSheet.showForEntity(context, type: type, entityId: entityId);
