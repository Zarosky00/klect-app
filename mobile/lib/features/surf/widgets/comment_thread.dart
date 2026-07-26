import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../data/comments_controller.dart';

/// One rendered line of the thread: a comment plus how far to indent it.
class _ThreadRow {
  const _ThreadRow(this.comment, this.depth);

  final CommentModel comment;
  final int depth;
}

/// Threaded comments for any entity, with an optimistic composer.
///
/// Replies nest to [CommentsController.maxDepth]; anything deeper renders at
/// the deepest indent rather than marching off the right edge of the sheet.
class CommentThread extends ConsumerStatefulWidget {
  /// Creates a thread.
  const CommentThread({
    required this.entity,
    required this.focusNode,
    super.key,
  });

  /// What is being commented on.
  final EntityRef entity;

  /// Focus node for the composer, so the action bar's comment pill can jump
  /// straight into typing.
  final FocusNode focusNode;

  @override
  ConsumerState<CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends ConsumerState<CommentThread> {
  final TextEditingController _draft = TextEditingController();
  CommentModel? _replyTo;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  List<_ThreadRow> _thread(List<CommentModel> comments) {
    final ids = <String>{for (final comment in comments) comment.id};
    final byParent = <String, List<CommentModel>>{};
    final roots = <CommentModel>[];
    for (final comment in comments) {
      final parent = comment.parentId;
      if (parent == null || !ids.contains(parent)) {
        roots.add(comment);
      } else {
        byParent.putIfAbsent(parent, () => <CommentModel>[]).add(comment);
      }
    }

    int byTime(CommentModel a, CommentModel b) =>
        (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));

    final rows = <_ThreadRow>[];
    void walk(List<CommentModel> level, int depth) {
      level.sort(byTime);
      for (final comment in level) {
        rows.add(_ThreadRow(comment, depth));
        final children = byParent[comment.id];
        if (children == null) continue;
        walk(
          children,
          depth < CommentsController.maxDepth - 1 ? depth + 1 : depth,
        );
      }
    }

    walk(roots, 0);
    return rows;
  }

  void _startReply(CommentModel comment) {
    setState(() => _replyTo = comment);
    widget.focusNode.requestFocus();
  }

  void _cancelReply() => setState(() => _replyTo = null);

  Future<void> _send() async {
    final body = _draft.text;
    if (body.trim().isEmpty) return;
    final parent = _replyTo;
    _draft.clear();
    setState(() => _replyTo = null);
    await ref.read(commentsProvider(widget.entity).notifier).post(
          body: body,
          parentId: parent?.id,
          parentDepth: parent?.depth ?? 0,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final state = ref.watch(commentsProvider(widget.entity));
    final meId = ref.watch(currentUserIdProvider);

    ref.listen<CommentsState>(commentsProvider(widget.entity),
        (previous, next) {
      final draft = next.failedDraft;
      if (draft == null || draft == previous?.failedDraft) return;
      // A failed comment must never lose the user's words.
      _draft.text = draft;
      ref.read(commentsProvider(widget.entity).notifier).draftRestored();
      final error = next.error;
      if (error != null) KToast.error(context, error.message);
    });

    final rows = _thread(state.comments);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (state.loading && state.comments.isEmpty)
          const KSkeletonList(rows: 2, showMedia: false)
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s6),
            child: Text(
              'No comments yet. Say the first thing.',
              textAlign: TextAlign.center,
              style: context.kt.callout.copyWith(color: colors.textTertiary),
            ),
          )
        else
          for (final row in rows)
            _CommentRow(
              key: ValueKey<String>(row.comment.id),
              row: row,
              isMine: meId != null && row.comment.authorId == meId,
              onReply: () => _startReply(row.comment),
              onDelete: () => unawaited(
                ref
                    .read(commentsProvider(widget.entity).notifier)
                    .remove(row.comment.id),
              ),
            ),
        const SizedBox(height: Space.s4),
        _Composer(
          controller: _draft,
          focusNode: widget.focusNode,
          replyTo: _replyTo,
          onCancelReply: _cancelReply,
          onSend: () => unawaited(_send()),
        ),
      ],
    );
  }
}

class _CommentRow extends ConsumerWidget {
  const _CommentRow({
    required this.row,
    required this.isMine,
    required this.onReply,
    required this.onDelete,
    super.key,
  });

  final _ThreadRow row;
  final bool isMine;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await KConfirmDialog.show(
      context,
      title: 'Delete this comment?',
      message: 'It disappears for everyone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) onDelete();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final comment = row.comment;
    final avatarUrl = ref.watch(klectApiProvider).publicUrl(
          comment.author?.avatarPath,
          bucket: StorageBucket.avatars,
        );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                comment.author?.name ?? 'Someone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.label,
              ),
            ),
            const SizedBox(width: Space.s2),
            Text(
              comment.isPending
                  ? 'sending…'
                  : timeago.format(
                      comment.createdAt ?? DateTime.now(),
                      locale: 'en_short',
                    ),
              style: text.micro.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: Space.s1),
        Text(comment.body, style: text.body),
        const SizedBox(height: Space.s1),
        Row(
          children: <Widget>[
            if (!comment.isPending)
              _CommentLike(commentId: comment.id, seedCount: comment.likeCount),
            const SizedBox(width: Space.s3),
            if (!comment.isPending)
              KPressable(
                onTap: onReply,
                enforceMinTapTarget: false,
                semanticLabel: 'Reply',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s1),
                  child: Text(
                    'Reply',
                    style: text.micro.copyWith(color: colors.textSecondary),
                  ),
                ),
              ),
            const Spacer(),
            if (isMine && !comment.isPending)
              KPressable(
                onTap: () => unawaited(_confirmDelete(context)),
                enforceMinTapTarget: false,
                semanticLabel: 'Delete comment',
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.s1),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: Space.s4,
                    color: colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    return Opacity(
      opacity: comment.isPending ? Opacities.pressed : 1,
      child: Padding(
        padding: EdgeInsets.only(
          left: row.depth * Space.s6,
          top: Space.s3,
          bottom: Space.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            KAvatar(
              imageUrl: avatarUrl,
              name: comment.author?.name,
              size: Space.s8,
              isVerified: comment.author?.isVerified ?? false,
            ),
            const SizedBox(width: Space.s3),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _CommentLike extends ConsumerWidget {
  const _CommentLike({required this.commentId, required this.seedCount});

  final String commentId;
  final int seedCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entity = EntityRef.comment(commentId);
    final state = ref.watch(interactionProvider(entity));
    return KCountPill(
      icon: Icons.favorite_border_rounded,
      activeIcon: Icons.favorite_rounded,
      count: state.hydrated ? state.likeCount : seedCount,
      active: state.liked,
      activeColor: context.kc.actionLike,
      showZero: false,
      iconSize: Space.s4,
      gap: Space.s1,
      semanticLabel: '${state.liked ? 'Unlike' : 'Like'} comment, '
          '${state.likeCount}',
      onTap: () =>
          unawaited(ref.read(interactionProvider(entity).notifier).toggleLike()),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.replyTo,
    required this.onCancelReply,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final CommentModel? replyTo;
  final VoidCallback onCancelReply;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final reply = replyTo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (reply != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: KChip(
                label: 'Replying to ${reply.author?.name ?? 'comment'}',
                icon: Icons.reply_rounded,
                selected: true,
                dense: true,
                onRemove: onCancelReply,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: KTextField(
                controller: controller,
                focusNode: focusNode,
                hint: reply == null ? 'Add a comment' : 'Write a reply',
                maxLines: 4,
                minLines: 1,
                maxLength: 1000,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: Space.s2),
            KIconButton(
              icon: Icons.send_rounded,
              semanticLabel: 'Post comment',
              color: colors.textOnAccent,
              background: colors.accentDefault,
              onPressed: onSend,
            ),
          ],
        ),
      ],
    );
  }
}
