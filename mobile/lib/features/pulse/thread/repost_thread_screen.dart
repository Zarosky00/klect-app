import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/interactions/interactions.dart';
import '../../../core/links.dart';
import '../../../core/models/models.dart';
import '../../../core/supabase.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../surf/data/closeup_providers.dart';
import '../../surf/data/comments_controller.dart';
import '../../surf/widgets/comment_thread.dart';
import '../widgets/pulse_target_card.dart';
import 'thread_parts.dart';

/// What a Pulse row already knows about a repost, handed to the page through
/// the route's `extra` so the first frame paints from the envelope instead of
/// a skeleton. A deep link without it loads the same data itself.
@immutable
class RepostThreadArgs {
  /// Creates the hand-off.
  const RepostThreadArgs({
    this.target,
    this.reposter,
    this.repostedAt,
    this.seed,
    this.focusComposer = false,
  });

  /// The embedded collection / shelf / thing.
  final PulseTarget? target;

  /// Who reposted it into the viewer's Pulse.
  final Profile? reposter;

  /// When it was reposted.
  final DateTime? repostedAt;

  /// The row's authoritative counters, so the stats never flash zeros.
  final InteractionState? seed;

  /// Opens with the comment composer focused (the row's comment pill).
  final bool focusComposer;
}

/// **The repost page** (`/repost/:type/:id`) — what the *sides* of a Pulse
/// repost row open.
///
/// It reads like a quote's thread: who reposted it, the owner with a follow
/// control, the reposted card, a full timestamp, the stats row, the action
/// bar and the discussion with a pinned composer. Everything social on it is
/// the Surf entity's own — the same likes, saves, reposts, views and
/// comments its Surf closeup shows, through the same optimistic engine.
///
/// The embedded card is the way into Surf: tap opens the closeup, double tap
/// the immersive viewer, and holding a photo peeks it.
class RepostThreadScreen extends ConsumerStatefulWidget {
  /// Creates the page for one reposted entity.
  const RepostThreadScreen({required this.entity, super.key, this.args});

  /// The reposted collection, shelf or thing.
  final EntityRef entity;

  /// Optional hand-off from the Pulse row.
  final RepostThreadArgs? args;

  @override
  ConsumerState<RepostThreadScreen> createState() => _RepostThreadScreenState();
}

class _RepostThreadScreenState extends ConsumerState<RepostThreadScreen> {
  final CommentDraftController _draft = CommentDraftController();
  final FocusNode _composerFocus = FocusNode();
  Timer? _focusTimer;

  EntityRef get _entity => widget.entity;

  @override
  void initState() {
    super.initState();
    final seed = widget.args?.seed;
    if (seed != null) {
      ref.read(interactionSeedStoreProvider).put(_entity, seed);
    }
    // Opening the repost is looking at the thing itself; `record_view` is
    // deduped per viewer per day server-side.
    unawaited(ref.read(interactionProvider(_entity).notifier).recordView());
    if (widget.args?.focusComposer ?? false) {
      // After the route transition, so the keyboard does not fight it.
      _focusTimer = Timer(KDurations.medium, () {
        if (mounted) _composerFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _composerFocus.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _draft.text.text;
    if (body.trim().isEmpty) return;
    final parent = _draft.replyTo;
    _draft.clearAccepted();
    await ref
        .read(commentsProvider(_entity).notifier)
        .post(
          body: body,
          parentId: parent?.id,
          parentDepth: parent?.depth ?? 0,
        );
  }

  Future<void> _refresh() async {
    ref.invalidate(closeupProvider(_entity));
    if (widget.args?.target == null) {
      ref.invalidate(pulseTargetProvider(_entity));
    }
    await ref.read(commentsProvider(_entity).notifier).load();
  }

  void _openInSurf() =>
      unawaited(context.push(KlectLinks.closeupPath(_entity.type, _entity.id)));

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      GoRouter.of(context).go('/pulse');
    }
  }

  static String _typeLabel(EntityType type) => switch (type) {
    EntityType.collection => 'Collection',
    EntityType.subcollection => 'Shelf',
    EntityType.item => 'Thing',
    EntityType.post => 'Post',
    EntityType.comment => 'Comment',
  };

  @override
  Widget build(BuildContext context) {
    final entity = _entity;
    // Surf's own payload: authoritative counters and the owner.
    final closeup = ref.watch(closeupProvider(entity)).value;
    ref.listen<AsyncValue<Closeup>>(closeupProvider(entity), (previous, next) {
      final data = next.value;
      if (data == null) return;
      // Beat the Pulse row's older snapshot with the Surf truth.
      ref.read(interactionProvider(entity).notifier).hydrateFromCloseup(data);
    });

    final passed = widget.args?.target;
    final loaded = passed == null
        ? ref.watch(pulseTargetProvider(entity))
        : null;
    final target = passed ?? loaded?.value;
    final ready = target != null && !target.unavailable;
    final reposter = widget.args?.reposter;

    return KScaffold(
      appBar: KFixedAppBar(
        title: reposter != null ? 'Repost' : _typeLabel(entity.type),
        showBack: true,
        actions: <Widget>[
          if (ready)
            KIconButton(
              icon: Icons.north_east_rounded,
              semanticLabel: 'Open in Surf',
              onPressed: _openInSurf,
            ),
        ],
      ),
      onRefresh: ready ? _refresh : null,
      // Scaffold only shrinks the body for the keyboard and leaves its
      // bottom bar under the IME, so the composer lifts itself instead.
      resizeToAvoidBottomInset: false,
      bottomBar: !ready
          ? null
          : KKeyboardInset(
              child: ListenableBuilder(
                listenable: _draft,
                builder: (context, _) => CommentComposer(
                  controller: _draft.text,
                  focusNode: _composerFocus,
                  replyTo: _draft.replyTo,
                  onCancelReply: _draft.cancelReply,
                  onSend: () => unawaited(_send()),
                ),
              ),
            ),
      body: !ready
          ? _fallback(target, loaded)
          : CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _RepostBlock(
                    entity: entity,
                    target: target,
                    owner: _ownerOf(target, closeup),
                    reposter: reposter,
                    repostedAt: widget.args?.repostedAt,
                    seed: widget.args?.seed,
                    onComment: _composerFocus.requestFocus,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.s4,
                      Space.s5,
                      Space.s4,
                      Space.s2,
                    ),
                    child: Text('Comments', style: context.kt.title3),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                    child: CommentThread(
                      entity: entity,
                      focusNode: _composerFocus,
                      draftController: _draft,
                      showComposer: false,
                    ),
                  ),
                ),
                // The body already ends above the lifted composer.
                const SliverToBoxAdapter(child: SizedBox(height: Space.s8)),
              ],
            ),
    );
  }

  /// The envelope's author first (it is what the row showed); the closeup's
  /// owner when the envelope had none.
  Profile? _ownerOf(PulseTarget target, Closeup? closeup) {
    final author = target.author;
    if (author != null) return author;
    final owner = closeup?.owner;
    if (owner == null || owner.id.isEmpty) return null;
    return owner;
  }

  Widget _fallback(PulseTarget? target, AsyncValue<PulseTarget>? loaded) {
    if (target != null && target.unavailable) {
      return KEmptyState(
        title: 'This is no longer available',
        message: 'It was deleted — or is no longer visible to you.',
        icon: Icons.visibility_off_outlined,
        actionLabel: 'Back to Pulse',
        onAction: _back,
      );
    }
    if (loaded != null && loaded.hasError) {
      return KErrorState(
        error: loaded.error,
        onRetry: () => ref.invalidate(pulseTargetProvider(_entity)),
      );
    }
    return const KSkeletonList(rows: 3);
  }
}

class _RepostBlock extends ConsumerWidget {
  const _RepostBlock({
    required this.entity,
    required this.target,
    required this.owner,
    required this.onComment,
    this.reposter,
    this.repostedAt,
    this.seed,
  });

  final EntityRef entity;
  final PulseTarget target;
  final Profile? owner;
  final Profile? reposter;
  final DateTime? repostedAt;
  final InteractionState? seed;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final meId = ref.watch(currentUserIdProvider);
    final owner = this.owner;
    final when = repostedAt ?? target.createdAt;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ThreadAuthorHeader(
            author: owner,
            reposter: reposter,
            showFollow:
                owner != null && owner.id.isNotEmpty && owner.id != meId,
          ),
          const SizedBox(height: Space.s3),
          PulseTargetCard(target: target),
          const SizedBox(height: Space.s2),
          Row(
            children: <Widget>[
              Icon(
                Icons.touch_app_outlined,
                size: Space.s3,
                color: colors.textTertiary,
              ),
              const SizedBox(width: Space.s1),
              Flexible(
                child: Text(
                  'Tap the card to open it in Surf · hold a photo for '
                  'quick actions',
                  maxLines: 2,
                  style: text.micro.copyWith(color: colors.textTertiary),
                ),
              ),
            ],
          ),
          if (when != null) ...<Widget>[
            const SizedBox(height: Space.s3),
            Text(
              reposter != null
                  ? 'Reposted · ${formatThreadTimestamp(when)}'
                  : formatThreadTimestamp(when),
              style: text.caption.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: Space.s3),
          Divider(height: Strokes.hairline, color: colors.borderSubtle),
          ThreadStatsRow(entity: entity),
          Divider(height: Strokes.hairline, color: colors.borderSubtle),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.s1),
            // Compact split targets: the full-size bar is wider than a
            // 390pt phone's content column.
            child: KActionBar(
              entity: entity,
              seed: seed,
              live: true,
              compact: true,
              alignment: MainAxisAlignment.spaceBetween,
              shareTitle: target.title,
              quotePreview: target,
              onComment: onComment,
            ),
          ),
          Divider(height: Strokes.hairline, color: colors.borderSubtle),
        ],
      ),
    );
  }
}
