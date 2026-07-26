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
  const CommentActionBar({
    required this.comment,
    super.key,
    this.onReply,
  });

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
            onTap: () =>
                Navigator.of(sheetContext).pop(_ShareChoice.copy),
          ),
          _SheetOption(
            icon: Icons.ios_share_rounded,
            label: 'Share via system',
            detail: 'Hand it to any app on this phone.',
            onTap: () =>
                Navigator.of(sheetContext).pop(_ShareChoice.system),
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

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final state = ref.watch(interactionProvider(_entity));

    ref.listen<InteractionState>(interactionProvider(_entity),
        (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error) {
        KToast.error(context, error.message);
        _controller.clearError();
      }
    });

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
          semanticLabel: '${state.liked ? 'Unlike' : 'Like'} comment, '
              '${state.likeCount}',
          onTap: _controller.toggleLike,
        ),
        const SizedBox(width: Space.s2),
        KCountPill(
          icon: Icons.bookmark_border_rounded,
          activeIcon: Icons.bookmark_rounded,
          count: state.saveCount,
          active: state.saved,
          activeColor: colors.actionSave,
          showZero: false,
          iconSize: Space.s4,
          gap: Space.s1,
          semanticLabel: '${state.saved ? 'Unsave' : 'Save'} comment, '
              '${state.saveCount}',
          onTap: () => _controller.toggleSave(),
        ),
        const SizedBox(width: Space.s2),
        KCountPill(
          icon: Icons.repeat_rounded,
          activeIcon: Icons.repeat_on_rounded,
          count: state.repostCount,
          active: state.reposted,
          activeColor: colors.actionRepost,
          showZero: false,
          iconSize: Space.s4,
          gap: Space.s1,
          semanticLabel:
              '${state.reposted ? 'Undo repost of' : 'Repost'} comment, '
              '${state.repostCount}',
          onTap: () => unawaited(_repostChooser()),
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
        const SizedBox(width: Space.s2),
        KCountPill(
          icon: Icons.ios_share_rounded,
          count: 0,
          showZero: false,
          iconSize: Space.s4,
          gap: Space.s1,
          activeColor: colors.actionShare,
          semanticLabel: 'Share comment',
          onTap: () => unawaited(_share()),
        ),
      ],
    );
  }
}

/// What the comment share chooser resolved to.
enum _ShareChoice { copy, system }

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
