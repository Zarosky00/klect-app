import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../design/motion.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import 'profile_queries.dart';

/// One tile in a library grid, carrying the full gesture contract.
///
/// | gesture | result |
/// |---|---|
/// | single tap | the Closeup, opened with no double-tap penalty |
/// | double tap | the immersive fullscreen viewer |
/// | long press | the quick-action peek |
///
/// Collections, subcollections and items all render through this one widget —
/// the three levels are symmetric, so their affordances are too. Shelves show
/// their name because a shelf without a name is unusable; an item shows the
/// photo and nothing else, exactly as `DESIGN_SYSTEM.md` §4 asks.
class EntityTile extends ConsumerStatefulWidget {
  /// Creates a tile.
  const EntityTile({required this.card, super.key, this.index = 0});

  /// What to render.
  final ProfileEntityCard card;

  /// Position in the grid, for the entry stagger.
  final int index;

  @override
  ConsumerState<EntityTile> createState() => _EntityTileState();
}

class _EntityTileState extends ConsumerState<EntityTile> {
  @override
  void initState() {
    super.initState();
    // Seeded before the notifier is first read, so counts never flash zero.
    ref
        .read(interactionSeedStoreProvider)
        .put(widget.card.entity, widget.card.interactionSeed);
  }

  void _openCloseup() {
    final card = widget.card;
    context.push(KlectLinks.closeupPath(card.entityType, card.id));
  }

  void _escalateToImmersive() {
    final card = widget.card;
    context.pushReplacement(
      KlectLinks.immersivePath(card.entityType, card.id),
    );
  }

  void _settle() {
    // The single tap is definitive now — count the impression. `record_view`
    // is deduped per viewer per day server-side, so this is safe to fire.
    unawaited(
      ref.read(interactionProvider(widget.card.entity).notifier).recordView(),
    );
  }

  /// An empty shelf has no closeup worth opening and nothing to view
  /// fullscreen: a tap goes straight to the shelf, where the owner adds things.
  void _openShelf() {
    final card = widget.card;
    context.push(KlectLinks.pathFor(card.entityType, card.id));
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final isShelf = card.entityType != EntityType.item;
    final empty = isShelf && card.isEmptyShelf;

    if (empty) {
      return KGestureRegion(
        onTap: _openShelf,
        onLongPress: () => EntityPeekSheet.show(context, card: card),
        semanticLabel: '${card.title}, empty ${card.entityType.wire}, '
            'only you can see it',
        child: _StaggeredEntry(
          index: widget.index,
          child: _EmptyShelfFace(card: card),
        ),
      );
    }

    return KGestureRegion(
      onTap: _openCloseup,
      onDoubleTap: _escalateToImmersive,
      onTapSettled: _settle,
      onLongPress: () => EntityPeekSheet.show(context, card: card),
      semanticLabel: '${card.title}, ${card.entityType.wire}',
      child: _StaggeredEntry(
        index: widget.index,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Radii.lg),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              KBlurhashImage(
                url: api.publicUrl(card.coverPath),
                blurhash: card.blurhash,
                borderRadius: BorderRadius.circular(Radii.lg),
                semanticLabel: card.title,
                memCacheWidth: _decodeWidth(context),
              ),
              if (isShelf)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        colors.bgBase.withValues(alpha: 0),
                        colors.surfaceScrim,
                      ],
                    ),
                  ),
                ),
              if (isShelf)
                Positioned(
                  left: Space.s3,
                  right: Space.s3,
                  bottom: Space.s3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        card.title,
                        style: context.kt.display3
                            .copyWith(color: colors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _shelfSubtitle(card),
                        style: context.kt.caption
                            .copyWith(color: colors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              if (!isShelf && card.childCount > 1)
                Positioned(
                  top: Space.s2,
                  right: Space.s2,
                  child: _StackBadge(count: card.childCount),
                ),
            ],
          ),
        ),
      ),
    );
  }

  int _decodeWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = Layout.masonryColumns(width);
    return (width / columns * MediaQuery.devicePixelRatioOf(context)).round();
  }

  static String _shelfSubtitle(ProfileEntityCard card) =>
      '${formatCount(card.childCount)} '
      'item${card.childCount == 1 ? '' : 's'}';
}

/// The face of a shelf or group with nothing on it: an open slot inviting the
/// owner to fill it, marked as private because visitors cannot see it yet.
class _EmptyShelfFace extends StatelessWidget {
  const _EmptyShelfFace({required this.card});

  final ProfileEntityCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface1,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: colors.borderDefault, width: Strokes.thin),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: Container(
              width: Space.s12,
              height: Space.s12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accentSubtle,
                border: Border.all(
                  color: colors.accentRing,
                  width: Strokes.hairline,
                ),
              ),
              child: Icon(
                Icons.add_rounded,
                size: Space.s6,
                color: colors.accentHover,
              ),
            ),
          ),
          Positioned(
            top: Space.s2,
            right: Space.s2,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s15,
                vertical: Space.s05,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceScrim,
                borderRadius: BorderRadius.circular(Radii.full),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.lock_outline_rounded,
                    size: Space.s3,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: Space.s1),
                  Text(
                    'Only you',
                    style: context.kt.micro
                        .copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: Space.s3,
            right: Space.s3,
            bottom: Space.s3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  card.title,
                  style:
                      context.kt.display3.copyWith(color: colors.textPrimary),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Empty · tap to add things',
                  style: context.kt.caption
                      .copyWith(color: colors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A fade-and-rise entry, staggered by grid position and capped so the bottom
/// of a long list never feels slow.
class _StaggeredEntry extends StatefulWidget {
  const _StaggeredEntry({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredEntry> createState() => _StaggeredEntryState();
}

class _StaggeredEntryState extends State<_StaggeredEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.medium,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(
      KMotion.staggerDelay(widget.index),
      () {
        if (mounted) _controller.forward();
      },
    ).ignore();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (KMotion.reduced(context)) return widget.child;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves_.emphasized,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}

class _StackBadge extends StatelessWidget {
  const _StackBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s15,
        vertical: Space.s05,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceScrim,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.filter_none_rounded,
            size: Space.s3,
            color: colors.textPrimary,
          ),
          const SizedBox(width: Space.s1),
          Text(
            formatCount(count),
            style: context.kt.micro.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

/// The long-press peek: quick actions without leaving the grid.
abstract final class EntityPeekSheet {
  /// Opens the peek for [card].
  static Future<void> show(
    BuildContext context, {
    required ProfileEntityCard card,
  }) =>
      KSheet.show<void>(
        context: context,
        title: card.title,
        builder: (sheetContext) => _EntityPeekBody(card: card),
      );
}

class _EntityPeekBody extends ConsumerWidget {
  const _EntityPeekBody({required this.card});

  final ProfileEntityCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: Space.s16,
              child: KBlurhashImage(
                url: api.publicUrl(card.coverPath),
                blurhash: card.blurhash,
                aspectRatio: Aspect.cover,
                borderRadius: BorderRadius.circular(Radii.md),
                memCacheWidth: Space.s16.round() * 3,
              ),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _levelLabel(card.entityType).toUpperCase(),
                    style: context.kt.micro
                        .copyWith(color: colors.textTertiary),
                  ),
                  const SizedBox(height: Space.s05),
                  Text(
                    card.title,
                    style: context.kt.title3,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (card.subtitle != null)
                    Text(
                      card.subtitle!,
                      style: context.kt.caption
                          .copyWith(color: colors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s5),
        if (card.isEmptyShelf) ...<Widget>[
          // Nothing to like or discuss yet, and nobody else can see it.
          Text(
            'Only you can see this until you add something to it.',
            style: context.kt.caption.copyWith(color: colors.textSecondary),
          ),
          if (card.entityType == EntityType.collection) ...<Widget>[
            const SizedBox(height: Space.s4),
            KButton(
              label: 'Add an item',
              expand: true,
              icon: Icons.add_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                context.push('/create/item?collection=${card.id}');
              },
            ),
          ],
        ] else
          KActionBar(
            entity: card.entity,
            seed: card.interactionSeed,
            shareTitle: card.title,
            live: true,
            showViews: true,
          ),
        const SizedBox(height: Space.s5),
        KButton(
          label: card.isEmptyShelf ? 'Open shelf' : 'Open',
          expand: true,
          variant: KButtonVariant.secondary,
          trailingIcon: Icons.arrow_forward_rounded,
          onPressed: () {
            Navigator.of(context).pop();
            context.push(KlectLinks.pathFor(card.entityType, card.id));
          },
        ),
      ],
    );
  }

  static String _levelLabel(EntityType type) => switch (type) {
        EntityType.collection => 'Collection',
        EntityType.subcollection => 'Subcollection',
        EntityType.item => 'Item',
        EntityType.post => 'Post',
        EntityType.comment => 'Comment',
      };
}
