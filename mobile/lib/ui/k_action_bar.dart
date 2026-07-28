import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/interactions/interactions.dart';
import '../core/models/models.dart';
import '../design/theme.dart';
import '../features/pulse/engagement/engagement_sheet.dart';
import '../features/pulse/widgets/pulse_composer.dart';
import 'k_count_pill.dart';
import 'k_pressable.dart';
import 'k_report_sheet.dart';
import 'k_share_sheet.dart';
import 'k_sheet.dart';
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
    this.quotePreview,
    this.quoteMedia = const <ItemMedia>[],
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

  /// Already-loaded representation of this entity for an immediate quote.
  final PulseTarget? quotePreview;

  /// Original post media shown inside the immutable quote preview.
  final List<ItemMedia> quoteMedia;

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

  Future<void> _share() => KShareSheet.show(
    context,
    entityType: widget.entity.type,
    entityId: widget.entity.id,
    title: widget.shareTitle,
  );

  void _report() {
    KReportSheet.showForEntity(
      context,
      type: widget.entity.type,
      entityId: widget.entity.id,
      subjectLabel: widget.shareTitle,
    );
  }

  Future<void> _showEngagement(SocialEngagementTab tab) =>
      SocialEngagementSheet.show(
        context,
        entity: widget.entity,
        initialTab: tab,
      );

  /// The X-style repost chooser: Repost / Quote / Undo repost.
  ///
  /// A bare repost is the idempotent `toggle_repost`; Quote opens the Pulse
  /// composer with this entity embedded as the subject (`create_post` with
  /// `entity_type = 'post'` for posts, an entity share card otherwise).
  /// Comments cannot be quoted as posts — for them the chooser is
  /// Repost / Undo only.
  Future<void> _repostChooser() async {
    final reposted = ref.read(interactionProvider(widget.entity)).reposted;
    final quotable = widget.entity.type != EntityType.comment;
    final choice = await KSheet.show<_RepostChoice>(
      context: context,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _RepostOption(
            icon: reposted ? Icons.undo_rounded : Icons.repeat_rounded,
            label: reposted ? 'Undo repost' : 'Repost',
            detail: reposted
                ? 'Take it back out of your followers’ Pulse.'
                : 'Put this in front of your followers as-is.',
            onTap: () => Navigator.of(sheetContext).pop(_RepostChoice.repost),
          ),
          if (quotable)
            _RepostOption(
              icon: Icons.format_quote_rounded,
              label: 'Quote',
              detail: 'Say something about it in a post of your own.',
              onTap: () => Navigator.of(sheetContext).pop(_RepostChoice.quote),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _RepostChoice.repost:
        unawaited(_controller.toggleRepost());
      case _RepostChoice.quote:
        final entry = await PulseComposer.show(
          context,
          subject: PulseComposerSubject(
            entity: widget.entity,
            preview: widget.quotePreview,
            media: widget.quoteMedia,
          ),
        );
        if (entry != null && mounted) {
          KToast.success(context, 'Shared to Pulse');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.live) {
      ref.watch(entityLiveCountersProvider(widget.entity));
    }
    final state = ref.watch(interactionProvider(widget.entity));
    final colors = context.kc;

    final gap = widget.compact ? Space.s15 : Space.s5;

    return Row(
      mainAxisAlignment: widget.alignment,
      children: <Widget>[
        KCountPill(
          icon: Icons.favorite_border_rounded,
          activeIcon: Icons.favorite_rounded,
          count: state.likeCount,
          active: state.liked,
          activeColor: colors.actionLike,
          iconSemanticLabel: state.liked ? 'Unlike' : 'Like',
          countSemanticLabel: '${state.likeCount} likes, view accounts',
          denseSplitTargets: widget.compact,
          onIconTap: _controller.toggleLike,
          onCountTap: state.likeCount > 0
              ? () => unawaited(_showEngagement(SocialEngagementTab.like))
              : null,
        ),
        SizedBox(width: gap),
        KCountPill(
          icon: Icons.bookmark_border_rounded,
          activeIcon: Icons.bookmark_rounded,
          count: state.saveCount,
          active: state.saved,
          activeColor: colors.actionSave,
          semanticLabel:
              '${state.saved ? 'Unsave' : 'Save'}, '
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
          // The engagement RPC is authoritative and may know about quotes
          // that an older cached card did not carry yet. Keep this count hit
          // target visible even when the local seed says zero.
          showZero: true,
          iconSemanticLabel:
              '${state.reposted ? 'Undo repost' : 'Repost'} or quote',
          countSemanticLabel:
              '${state.repostCount} reposts and ${state.quoteCount} quotes, '
              'view activity',
          denseSplitTargets: widget.compact,
          onIconTap: () => unawaited(_repostChooser()),
          onCountTap: () =>
              unawaited(_showEngagement(SocialEngagementTab.repost)),
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

/// What the repost chooser resolved to.
enum _RepostChoice { repost, quote }

/// One row of the repost chooser sheet.
class _RepostOption extends StatelessWidget {
  const _RepostOption({
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
