import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/interactions/interactions.dart';
import '../core/links.dart';
import '../design/theme.dart';
import 'k_count_pill.dart';
import 'k_report_sheet.dart';
import 'k_toast.dart';

/// The one action bar: like · save · repost · comment · share.
///
/// Wired straight into the optimistic engine, so every tap lands instantly and
/// reconciles with the RPC's authoritative `{active, count}` when it returns.
/// Nothing here counts anything itself.
class KActionBar extends ConsumerStatefulWidget {
  /// Creates an action bar for one entity.
  const KActionBar({
    required this.entity,
    super.key,
    this.seed,
    this.onComment,
    this.shareTitle,
    this.live = false,
    this.compact = false,
    this.showViews = false,
    this.showShare = true,
    this.alignment = MainAxisAlignment.spaceBetween,
  });

  /// Which entity these actions apply to.
  final EntityRef entity;

  /// Authoritative state already known by the caller (a feed row, a closeup).
  /// Seeding avoids a flash of zeros before the first fetch.
  final InteractionState? seed;

  /// Opens the comment thread. Null renders the comment pill read-only.
  final VoidCallback? onComment;

  /// Title used in the share sheet.
  final String? shareTitle;

  /// Subscribe to realtime counter updates while this bar is on screen.
  final bool live;

  /// Drops the view count and tightens spacing.
  final bool compact;

  /// Shows the view count on the right.
  final bool showViews;

  /// Shows the share control.
  final bool showShare;

  /// Row alignment.
  final MainAxisAlignment alignment;

  @override
  ConsumerState<KActionBar> createState() => _KActionBarState();
}

class _KActionBarState extends ConsumerState<KActionBar> {
  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null) {
      // Written before the controller is first read, so `build()` picks it up
      // and the bar never renders zeros it will immediately replace.
      ref.read(interactionSeedStoreProvider).put(widget.entity, seed);
    }
  }

  @override
  void didUpdateWidget(KActionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seed = widget.seed;
    if (seed != null && seed != oldWidget.seed) {
      ref.read(interactionProvider(widget.entity).notifier).hydrate(seed);
    }
  }

  InteractionController get _controller =>
      ref.read(interactionProvider(widget.entity).notifier);

  Future<void> _share() async {
    final url = KlectLinks.urlFor(widget.entity.type, widget.entity.id);
    final title = widget.shareTitle;
    await SharePlus.instance.share(
      ShareParams(
        text: title == null ? url : '$title\n$url',
        subject: title,
      ),
    );
  }

  void _report() {
    KReportSheet.showForEntity(
      context,
      type: widget.entity.type,
      entityId: widget.entity.id,
      subjectLabel: widget.shareTitle,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.live) {
      ref.watch(entityLiveCountersProvider(widget.entity));
    }
    final state = ref.watch(interactionProvider(widget.entity));
    final colors = context.kc;

    ref.listen<InteractionState>(interactionProvider(widget.entity),
        (previous, next) {
      final error = next.error;
      if (error != null && error != previous?.error) {
        KToast.error(context, error.message);
        _controller.clearError();
      }
    });

    final gap = widget.compact ? Space.s3 : Space.s5;

    return Row(
      mainAxisAlignment: widget.alignment,
      children: <Widget>[
        KCountPill(
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          count: state.likeCount,
          active: state.liked,
          activeColor: colors.actionLike,
          semanticLabel: '${state.liked ? 'Unlike' : 'Like'}, '
              '${state.likeCount}',
          onTap: _controller.toggleLike,
        ),
        SizedBox(width: gap),
        KCountPill(
          icon: Icons.bookmark_border_rounded,
          activeIcon: Icons.bookmark_rounded,
          count: state.saveCount,
          active: state.saved,
          activeColor: colors.actionSave,
          semanticLabel: '${state.saved ? 'Unsave' : 'Save'}, '
              '${state.saveCount}',
          onTap: () => _controller.toggleSave(),
        ),
        SizedBox(width: gap),
        KCountPill(
          icon: Icons.repeat_rounded,
          activeIcon: Icons.repeat_on_rounded,
          count: state.repostCount,
          active: state.reposted,
          activeColor: colors.actionRepost,
          semanticLabel: '${state.reposted ? 'Undo repost' : 'Repost'}, '
              '${state.repostCount}',
          onTap: () => _controller.toggleRepost(),
        ),
        SizedBox(width: gap),
        KCountPill(
          icon: Icons.mode_comment_outlined,
          activeIcon: Icons.mode_comment_rounded,
          count: state.commentCount,
          activeColor: colors.actionComment,
          semanticLabel: 'Comments, ${state.commentCount}',
          onTap: widget.onComment,
        ),
        if (widget.showViews && !widget.compact) ...<Widget>[
          SizedBox(width: gap),
          KCountPill(
            icon: Icons.visibility_outlined,
            count: state.viewCount,
            semanticLabel: 'Views, ${state.viewCount}',
          ),
        ],
        if (widget.showShare) ...<Widget>[
          SizedBox(width: gap),
          KCountPill(
            icon: Icons.ios_share_rounded,
            count: 0,
            showZero: false,
            activeColor: colors.actionShare,
            semanticLabel: 'Share',
            onTap: _share,
            onLongPress: _report,
          ),
        ],
      ],
    );
  }
}
