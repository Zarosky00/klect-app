import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/api_error.dart';
import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../data/pulse_entry_view.dart';
import '../widgets/comment_action_bar.dart';
import '../widgets/entity_attachment_card.dart';
import '../widgets/pulse_card.dart';
import '../widgets/pulse_media_peek.dart';
import '../widgets/pulse_target_card.dart';
import 'post_thread_controller.dart';
import 'thread_parts.dart';

/// **The post thread** — the X-anatomy destination a Pulse row opens
/// (`/post/:id`, 0021 `get_post_thread`).
///
/// Top to bottom: author header (avatar · name · @handle · follow), the
/// full-size body (short posts read at title scale, like X), the post's own
/// photos, the attached/quoted target card, a full timestamp, the stats row,
/// the action bar, then the discussion: Top/Newest sort, paged comments each
/// carrying the compact comment action bar, and a reply-first composer
/// pinned to the bottom of the screen.
class PostThreadScreen extends ConsumerStatefulWidget {
  /// Creates the screen for one post.
  const PostThreadScreen({
    required this.postId,
    super.key,
    this.highlightCommentId,
  });

  /// Route parameter.
  final String postId;

  /// Optional profile-activity deep link. The matching row receives a
  /// restrained highlight so the discussion opens with clear context.
  final String? highlightCommentId;

  @override
  ConsumerState<PostThreadScreen> createState() => _PostThreadScreenState();
}

class _PostThreadScreenState extends ConsumerState<PostThreadScreen> {
  final TextEditingController _draft = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  CommentModel? _replyTo;

  EntityRef get _entity => EntityRef.post(widget.postId);

  @override
  void initState() {
    super.initState();
    // The thread is the post's destination now, so it owns the view ping.
    // `record_view` dedupes per viewer per day server-side.
    unawaited(ref.read(interactionProvider(_entity).notifier).recordView());
  }

  @override
  void dispose() {
    _composerFocus.dispose();
    _draft.dispose();
    super.dispose();
  }

  PostThreadController get _controller =>
      ref.read(postThreadProvider(widget.postId).notifier);

  void _startReply(CommentModel comment) {
    setState(() => _replyTo = comment);
    _composerFocus.requestFocus();
  }

  Future<void> _send() async {
    final body = _draft.text;
    if (body.trim().isEmpty) return;
    final parent = _replyTo;
    _draft.clear();
    setState(() => _replyTo = null);
    await _controller.addComment(
      body: body,
      parentId: parent?.id,
      parentDepth: parent?.depth ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(postThreadProvider(widget.postId));

    ref.listen<PostThreadState>(postThreadProvider(widget.postId), (
      previous,
      next,
    ) {
      final draft = next.failedDraft;
      if (draft == null || draft == previous?.failedDraft) return;
      // A failed comment must never lose the user's words.
      _draft.text = draft;
      _controller.draftRestored();
      final error = next.commentError;
      if (error != null) KToast.error(context, error.message);
    });

    final post = state.post;
    return KScaffold(
      appBar: const KFixedAppBar(title: 'Post', showBack: true),
      onRefresh: post == null ? null : _controller.refresh,
      bottomBar: post == null
          ? null
          : _Composer(
              controller: _draft,
              focusNode: _composerFocus,
              replyTo: _replyTo,
              onCancelReply: () => setState(() => _replyTo = null),
              onSend: () => unawaited(_send()),
            ),
      body: post == null
          ? _fallback(state)
          : CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _PostBlock(
                    post: post,
                    onComment: _composerFocus.requestFocus,
                  ),
                ),
                ..._commentSlivers(state),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.viewInsetsOf(context).bottom + Space.s8,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _fallback(PostThreadState state) {
    final error = state.error;
    if (error != null) {
      if (error.kind == KlectErrorKind.notFound) {
        return KEmptyState(
          title: 'This post is gone',
          message: 'It was deleted — or is no longer visible to you.',
          icon: Icons.speaker_notes_off_outlined,
          actionLabel: 'Back to Pulse',
          onAction: () {
            if (context.canPop()) {
              context.pop();
            } else {
              GoRouter.of(context).go('/pulse');
            }
          },
        );
      }
      return KErrorState(
        error: error,
        onRetry: () => unawaited(_controller.load()),
      );
    }
    return const KSkeletonList(rows: 4);
  }

  List<Widget> _commentSlivers(PostThreadState state) {
    final meId = ref.watch(currentUserIdProvider);
    return <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Space.s4,
            Space.s4,
            Space.s4,
            Space.s1,
          ),
          child: Row(
            children: <Widget>[
              Text('Comments', style: context.kt.title3),
              const Spacer(),
              for (final sort in CommentSort.values) ...<Widget>[
                KChip(
                  label: sort.label,
                  selected: sort == state.sort,
                  dense: true,
                  onTap: state.loading
                      ? null
                      : () => unawaited(_controller.setSort(sort)),
                ),
                const SizedBox(width: Space.s2),
              ],
            ],
          ),
        ),
      ),
      if (state.loading && state.comments.isEmpty)
        const SliverToBoxAdapter(
          child: KSkeletonList(rows: 2, showMedia: false),
        )
      else if (state.comments.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s8),
            child: Text(
              'No comments yet. Say the first thing.',
              textAlign: TextAlign.center,
              style: context.kt.callout.copyWith(
                color: context.kc.textTertiary,
              ),
            ),
          ),
        )
      else
        SliverList.builder(
          itemCount: state.comments.length,
          itemBuilder: (context, index) {
            final comment = state.comments[index];
            return _ThreadCommentRow(
              key: ValueKey<String>(comment.id),
              comment: comment,
              highlighted: comment.id == widget.highlightCommentId,
              isMine: meId != null && comment.authorId == meId,
              onReply: () => _startReply(comment),
              onDelete: () => unawaited(_controller.removeComment(comment.id)),
            );
          },
        ),
      if (state.hasMore)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s2,
              Space.s4,
              Space.s0,
            ),
            child: KButton(
              label: state.loadingMore ? 'Loading…' : 'Show more comments',
              variant: KButtonVariant.ghost,
              size: KButtonSize.small,
              busy: state.loadingMore,
              onPressed: state.loadingMore
                  ? null
                  : () => unawaited(_controller.loadMore()),
            ),
          ),
        ),
    ];
  }
}

// ─────────────────────────────────────────────────────────── the post block ──

class _PostBlock extends ConsumerWidget {
  const _PostBlock({required this.post, required this.onComment});

  final PulseItem post;
  final VoidCallback onComment;

  /// Short, text-only posts read at title scale — X's full-post treatment.
  bool get _bigType {
    final body = post.text;
    return body != null && body.length <= 140 && post.media.isEmpty;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final author = post.author;
    final meId = ref.watch(currentUserIdProvider);
    final body = post.text;
    final target = post.target;
    final attachment = post.attachment;
    final actionEntity = post.entity;
    final firstMedia = post.media.isEmpty ? null : post.media.first;
    final quotePreview = actionEntity.type == EntityType.post
        ? PulseTarget(
            id: actionEntity.id,
            type: EntityType.post,
            body: body,
            coverPath: firstMedia?.storagePath,
            coverBlurhash: firstMedia?.blurhash,
            coverWidth: firstMedia?.width,
            coverHeight: firstMedia?.height,
            createdAt: post.sortAt,
            author: author,
          )
        : (target?.id == actionEntity.id ? target : null);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ThreadAuthorHeader(
            author: author,
            reposter: post.reposter,
            showFollow: author != null && author.id != meId,
          ),
          if (body != null && body.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.s3),
            Text(body, style: _bigType ? text.title3 : text.body),
          ],
          if (post.media.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.s3),
            // Inline and bounded, like the stream — the immersive treatment
            // belongs to Surf, not to a discussion page. Holding a photo
            // peeks it; holding the text does not.
            PostMediaGrid(
              media: post.media,
              maxHeight: PostMediaGrid.streamMaxHeight,
              peek: PulsePeekTarget(
                entity: actionEntity,
                title: body ?? author?.name,
                subtitle: author?.handle,
              ),
            ),
          ],
          if (target != null) ...<Widget>[
            const SizedBox(height: Space.s3),
            PulseTargetCard(target: target),
          ] else if (attachment != null) ...<Widget>[
            const SizedBox(height: Space.s3),
            EntityAttachmentCard(entity: attachment),
          ],
          if (post.sortAt != null) ...<Widget>[
            const SizedBox(height: Space.s3),
            Text(
              formatThreadTimestamp(post.sortAt!),
              style: text.caption.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: Space.s3),
          Divider(height: Strokes.hairline, color: colors.borderSubtle),
          ThreadStatsRow(entity: post.entity),
          Divider(height: Strokes.hairline, color: colors.borderSubtle),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s1),
            // Compact split targets: the full-size bar is wider than a
            // 390pt phone's content column.
            child: KActionBar(
              entity: actionEntity,
              seed: post.seed,
              live: true,
              compact: true,
              alignment: MainAxisAlignment.spaceBetween,
              shareTitle: body ?? author?.name,
              quotePreview: quotePreview,
              quoteMedia: actionEntity.type == EntityType.post
                  ? post.media
                  : const <ItemMedia>[],
              onComment: onComment,
            ),
          ),
          Divider(height: Strokes.hairline, color: colors.borderSubtle),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────── comment row ──

class _ThreadCommentRow extends ConsumerWidget {
  const _ThreadCommentRow({
    required this.comment,
    required this.isMine,
    required this.onReply,
    required this.onDelete,
    this.highlighted = false,
    super.key,
  });

  final CommentModel comment;
  final bool isMine;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final bool highlighted;

  /// Deepest indent rendered.
  static const int _maxIndent = 2;

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
    final author = comment.author;
    final avatarUrl = ref
        .watch(klectApiProvider)
        .publicUrl(author?.avatarPath, bucket: StorageBucket.avatars);
    final indent =
        (comment.depth > _maxIndent ? _maxIndent : comment.depth) * Space.s6;

    return Opacity(
      opacity: comment.isPending ? Opacities.pressed : 1,
      child: AnimatedContainer(
        duration: KMotion.duration(context, KDurations.medium),
        curve: Curves_.emphasized,
        padding: EdgeInsets.fromLTRB(
          Space.s4 + indent,
          Space.s3,
          Space.s4,
          Space.s2,
        ),
        decoration: BoxDecoration(
          color: highlighted ? colors.actionCommentSubtle : colors.surface1,
          border: Border(
            bottom: BorderSide(
              color: colors.borderSubtle,
              width: Strokes.hairline,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            KAvatar(
              imageUrl: avatarUrl,
              name: author?.name,
              size: Space.s8,
              isVerified: author?.isVerified ?? false,
              onTap: author == null || author.username.isEmpty
                  ? null
                  : () => context.push(KlectLinks.profilePath(author.username)),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          author?.name ?? 'Someone',
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
                      const Spacer(),
                      if (isMine && !comment.isPending)
                        KPressable(
                          onTap: () => unawaited(_confirmDelete(context)),
                          enforceMinTapTarget: false,
                          semanticLabel: 'Delete comment',
                          child: Padding(
                            padding: const EdgeInsets.all(Space.s1),
                            child: Icon(
                              Icons.delete_outline_rounded,
                              size: Space.s4,
                              color: colors.textTertiary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Space.s1),
                  Text(comment.body, style: text.body),
                  const SizedBox(height: Space.s1),
                  if (!comment.isPending)
                    CommentActionBar(comment: comment, onReply: onReply),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────── pinned composer ──

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

    return Container(
      decoration: BoxDecoration(
        color: colors.surface1,
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: Strokes.hairline),
        ),
      ),
      // The Scaffold's resizeToAvoidBottomInset lifts the whole bottom bar
      // above the keyboard, exactly like the chat composer.
      padding: const EdgeInsets.fromLTRB(
        Space.s4,
        Space.s2,
        Space.s4,
        Space.s2,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                    hint: reply == null ? 'Post your reply' : 'Write a reply',
                    maxLines: 4,
                    minLines: 1,
                    maxLength: 1000,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                const SizedBox(width: Space.s2),
                KIconButton(
                  icon: Icons.send_rounded,
                  semanticLabel: 'Post reply',
                  color: colors.textOnAccent,
                  background: colors.accentDefault,
                  onPressed: onSend,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
