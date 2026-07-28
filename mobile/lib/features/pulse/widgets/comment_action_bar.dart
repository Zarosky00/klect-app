import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';

/// The compact action bar under a comment:
/// like · save · repost · reply · share.
///
/// Comments became full social citizens in 0021 (`save_count` /
/// `repost_count` columns + counter-trigger branches), so this bar wires the
/// same `toggle_like` / `toggle_save` / `toggle_repost` RPCs with
/// `entity_type = 'comment'` into the same optimistic engine every other bar
/// uses. Two deliberate differences from [KActionBar]:
///
///  * the repost chooser offers **Repost / Undo only** — a comment cannot be
///    quoted as a post (`create_post` refuses non-post quote targets);
///  * share is **copy link + system share only** — comments are not
///    `entity_share`-able into chat, so there is no send-to-a-friend row.
class CommentActionBar extends ConsumerStatefulWidget {
  /// Creates the bar for one comment.
  const CommentActionBar({required this.comment, super.key, this.onReply});

  /// The comment, whose counts seed the optimistic engine.
  final CommentModel comment;

  /// Starts a reply to this comment. Null hides the reply control.
  final VoidCallback? onReply;

  @override
  ConsumerState<CommentActionBar> createState() => _CommentActionBarState();
}

class _CommentActionBarState extends ConsumerState<CommentActionBar> {
  EntityRef get _entity => EntityRef.comment(widget.comment.id);

  InteractionController get _controller =>
      ref.read(interactionProvider(_entity).notifier);

  @override
  void initState() {
    super.initState();
    ref
        .read(interactionSeedStoreProvider)
        .put(_entity, InteractionState.fromComment(widget.comment));
  }

  /// Repost / Undo only — comments cannot be quoted as posts.
  Future<void> _repostChooser() async {
    final reposted = ref.read(interactionProvider(_entity)).reposted;
    final confirmed = await KSheet.show<bool>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SheetOption(
            icon: reposted ? Icons.undo_rounded : Icons.repeat_rounded,
            label: reposted ? 'Undo repost' : 'Repost',
            detail: reposted
                ? 'Take this comment back out of your followers’ Pulse.'
                : 'Put this comment in front of your followers.',
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    unawaited(_controller.toggleRepost());
  }

  /// Copy link + system share only — no conversation picker for comments.
  Future<void> _share() async {
    final url = KlectLinks.urlFor(EntityType.comment, widget.comment.id);
    final title = widget.comment.body;
    final choice = await KSheet.show<_ShareChoice>(
      context: context,
      title: 'Share',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SheetOption(
            icon: Icons.link_rounded,
            label: 'Copy link',
            detail: 'The same link the web app uses.',
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.copy),
          ),
          _SheetOption(
            icon: Icons.ios_share_rounded,
            label: 'Share via system',
            detail: 'Hand it to any app on this phone.',
            onTap: () => Navigator.of(sheetContext).pop(_ShareChoice.system),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _ShareChoice.copy:
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        KToast.show(
          context,
          'Link copied.',
          kind: KToastKind.success,
          icon: Icons.link_rounded,
        );
      case _ShareChoice.system:
        await SharePlus.instance.share(
          ShareParams(
            text: title.isEmpty ? url : '$title\n$url',
            subject: title.isEmpty ? null : title,
          ),
        );
    }
  }

  Future<void> _moreChooser() async {
    final state = ref.read(interactionProvider(_entity));
    final choice = await KSheet.show<_CommentMoreChoice>(
      context: context,
      title: 'Comment options',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SheetOption(
            icon: state.saved
                ? Icons.bookmark_remove_rounded
                : Icons.bookmark_add_outlined,
            label: state.saved ? 'Remove from saved' : 'Save comment',
            detail: state.saved
                ? 'Take it out of your saved comments.'
                : 'Keep it private in your saved comments.',
            onTap: () =>
                Navigator.of(sheetContext).pop(_CommentMoreChoice.save),
          ),
          _SheetOption(
            icon: state.reposted ? Icons.undo_rounded : Icons.repeat_rounded,
            label: state.reposted ? 'Undo repost' : 'Repost',
            detail: state.reposted
                ? 'Remove it from your followers’ Pulse.'
                : 'Share it into your followers’ Pulse.',
            onTap: () =>
                Navigator.of(sheetContext).pop(_CommentMoreChoice.repost),
          ),
          _SheetOption(
            icon: Icons.ios_share_rounded,
            label: 'Share',
            detail: 'Copy a link or use another app.',
            onTap: () =>
                Navigator.of(sheetContext).pop(_CommentMoreChoice.share),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _CommentMoreChoice.save:
        unawaited(_controller.toggleSave());
        break;
      case _CommentMoreChoice.repost:
        unawaited(_repostChooser());
        break;
      case _CommentMoreChoice.share:
        unawaited(_share());
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final state = ref.watch(interactionProvider(_entity));

    return Row(
      children: <Widget>[
        KCountPill(
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          count: state.likeCount,
          active: state.liked,
          activeColor: colors.actionLike,
          showZero: false,
          iconSize: Space.s4,
          gap: Space.s1,
          semanticLabel:
              '${state.liked ? 'Unlike' : 'Like'} comment, '
              '${state.likeCount}',
          onTap: _controller.toggleLike,
        ),
        if (widget.onReply != null) ...<Widget>[
          const SizedBox(width: Space.s2),
          KCountPill(
            icon: Icons.mode_comment_outlined,
            count: state.commentCount,
            activeColor: colors.actionComment,
            showZero: false,
            iconSize: Space.s4,
            gap: Space.s1,
            semanticLabel: 'Reply, ${state.commentCount} replies',
            onTap: widget.onReply,
          ),
        ],
        const Spacer(),
        KCountPill(
          icon: Icons.more_horiz_rounded,
          count: 0,
          showZero: false,
          iconSize: Space.s4,
          gap: Space.s1,
          activeColor: colors.textSecondary,
          semanticLabel: 'More comment options',
          onTap: () => unawaited(_moreChooser()),
        ),
      ],
    );
  }
}

/// What the comment share chooser resolved to.
enum _ShareChoice { copy, system }

enum _CommentMoreChoice { save, repost, share }

/// One row of a comment chooser sheet.
class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return KPressable(
      onTap: onTap,
      enforceMinTapTarget: false,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s3),
        child: Row(
          children: <Widget>[
            Container(
              width: Space.s10,
              height: Space.s10,
              decoration: BoxDecoration(
                color: colors.accentSubtle,
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Icon(icon, size: Space.s5, color: colors.actionRepost),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(label, style: context.kt.bodyStrong),
                  Text(
                    detail,
                    style: context.kt.caption.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
