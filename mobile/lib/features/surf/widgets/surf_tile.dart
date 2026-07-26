import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../design/motion.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import 'entity_gesture_card.dart';

/// The hero tag shared by a Surf tile's cover and its Closeup cover.
///
/// Namespaced so it can never collide with a hero another feature puts on the
/// same entity — two live heroes with one tag is a crash, not a glitch.
String surfCoverHeroTag(EntityType type, String id) =>
    'surf:cover:${type.wire}:$id';

/// One tile of the masonry grid.
///
/// At rest it is **the photo and nothing else**. The owner chip, the counts and
/// the entity-type badge fade in when the scroll settles (or while the peek is
/// open), per `docs/DESIGN_SYSTEM.md` §4 — "hidden but easily accessible".
///
/// Collection and subcollection tiles additionally show a stacked-card edge and
/// a child count, so a mixed feed reads as mixed without shouting about it.
class SurfTile extends ConsumerWidget {
  /// Creates a tile.
  const SurfTile({
    required this.card,
    required this.revealed,
    super.key,
    this.decodeWidth,
    this.staggerIndex = -1,
  });

  /// The feed row.
  final SurfCard card;

  /// Whether the quiet chrome is currently shown. Driven by scroll idleness,
  /// so a fling paints photos only.
  final ValueListenable<bool> revealed;

  /// Decode width cap in device pixels — memory stays flat on a long scroll.
  final int? decodeWidth;

  /// Position in the freshly-arrived page, or `-1` for "do not animate".
  /// Tiles built during a fling must appear instantly.
  final int staggerIndex;

  bool get _isStacked =>
      card.entityType == EntityType.collection ||
      card.entityType == EntityType.subcollection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.watch(klectApiProvider);
    final entity = EntityRef.ofCard(card);
    final coverUrl = api.publicUrl(card.coverPath);

    final tile = _TileSurface(
      card: card,
      coverUrl: coverUrl,
      decodeWidth: decodeWidth,
      stacked: _isStacked,
      revealed: revealed,
      avatarUrl: api.publicUrl(
        card.avatarPath,
        bucket: StorageBucket.avatars,
      ),
      entity: entity,
    );

    return _TileEntrance(
      staggerIndex: staggerIndex,
      child: KEntityGestureCard(
        entity: entity,
        title: card.title,
        subtitle: card.subtitle ?? '@${card.username}',
        imageUrl: coverUrl,
        blurhash: card.coverBlurhash,
        aspectRatio: card.tileAspect,
        child: tile,
      ),
    );
  }
}

class _TileSurface extends StatelessWidget {
  const _TileSurface({
    required this.card,
    required this.coverUrl,
    required this.decodeWidth,
    required this.stacked,
    required this.revealed,
    required this.avatarUrl,
    required this.entity,
  });

  final SurfCard card;
  final String? coverUrl;
  final int? decodeWidth;
  final bool stacked;
  final ValueListenable<bool> revealed;
  final String? avatarUrl;
  final EntityRef entity;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    final radius = BorderRadius.circular(Radii.lg);

    final photo = KBlurhashImage(
      url: coverUrl,
      blurhash: card.coverBlurhash,
      borderRadius: radius,
      semanticLabel: card.title,
      heroTag: surfCoverHeroTag(card.entityType, card.entityId),
      memCacheWidth: decodeWidth,
    );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (stacked) _StackedEdges(radius: radius),
        // The stacked edges live *inside* the reserved box, so the tile's
        // geometry is identical whatever the entity type — the grid can never
        // reflow because one card turned out to be a collection.
        Padding(
          padding: EdgeInsets.only(top: stacked ? Space.s3 : Space.s0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: colors.borderSubtle,
                width: Strokes.hairline,
              ),
            ),
            child: photo,
          ),
        ),
        Positioned.fill(
          top: stacked ? Space.s3 : Space.s0,
          child: _TileChrome(
            card: card,
            entity: entity,
            avatarUrl: avatarUrl,
            revealed: revealed,
            radius: radius,
          ),
        ),
      ],
    );
  }
}

/// Two thin sheets peeking out above the photo: the visual grammar for "this
/// card contains other cards".
class _StackedEdges extends StatelessWidget {
  const _StackedEdges({required this.radius});

  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Stack(
      children: <Widget>[
        Positioned(
          left: Space.s4,
          right: Space.s4,
          top: Space.s0,
          height: Space.s4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface2,
              borderRadius: radius,
              border: Border.all(
                color: colors.borderSubtle,
                width: Strokes.hairline,
              ),
            ),
          ),
        ),
        Positioned(
          left: Space.s2,
          right: Space.s2,
          top: Space.s15,
          height: Space.s4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surface3,
              borderRadius: radius,
              border: Border.all(
                color: colors.borderSubtle,
                width: Strokes.hairline,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TileChrome extends ConsumerWidget {
  const _TileChrome({
    required this.card,
    required this.entity,
    required this.avatarUrl,
    required this.revealed,
    required this.radius,
  });

  final SurfCard card;
  final EntityRef entity;
  final String? avatarUrl;
  final ValueListenable<bool> revealed;
  final BorderRadius radius;

  IconData get _typeIcon => switch (card.entityType) {
        EntityType.collection => Icons.collections_bookmark_rounded,
        EntityType.subcollection => Icons.layers_rounded,
        EntityType.item => Icons.photo_library_rounded,
        EntityType.post => Icons.bolt_rounded,
        EntityType.comment => Icons.mode_comment_rounded,
      };

  bool get _showBadge =>
      card.childCount > 0 &&
      (card.entityType != EntityType.item || card.childCount > 1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final text = context.kt;
    final social = ref.watch(interactionProvider(entity));

    return ValueListenableBuilder<bool>(
      valueListenable: revealed,
      builder: (context, visible, child) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: KMotion.duration(context, KDurations.base),
          curve: KCurves.standard,
          child: child,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  colors.surfaceScrim.withValues(alpha: 0),
                  colors.surfaceScrim,
                ],
              ),
            ),
          ),
          if (_showBadge)
            Positioned(
              top: Space.s2,
              right: Space.s2,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s2,
                  vertical: Space.s05,
                ),
                decoration: BoxDecoration(
                  color: colors.surfaceGlass,
                  borderRadius: BorderRadius.circular(Radii.full),
                  border: Border.all(
                    color: colors.borderSubtle,
                    width: Strokes.hairline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      _typeIcon,
                      size: Space.s3,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: Space.s1),
                    Text(
                      formatCount(card.childCount),
                      style: text.micro.copyWith(color: colors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: Space.s2,
            right: Space.s2,
            bottom: Space.s2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (card.title != null)
                  Text(
                    card.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.label.copyWith(color: colors.textPrimary),
                  ),
                const SizedBox(height: Space.s15),
                Row(
                  children: <Widget>[
                    KAvatar(
                      imageUrl: avatarUrl,
                      name: card.ownerName,
                      size: Space.s5,
                      isVerified: card.isVerified,
                    ),
                    const SizedBox(width: Space.s15),
                    Expanded(
                      child: Text(
                        card.ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.caption
                            .copyWith(color: colors.textSecondary),
                      ),
                    ),
                    KCountPill(
                      icon: Icons.favorite_border_rounded,
                      activeIcon: Icons.favorite_rounded,
                      count: social.likeCount,
                      active: social.liked,
                      activeColor: colors.actionLike,
                      showZero: false,
                      iconSize: Space.s4,
                      gap: Space.s1,
                      semanticLabel: 'Likes, ${social.likeCount}',
                    ),
                    const SizedBox(width: Space.s2),
                    KCountPill(
                      icon: Icons.bookmark_border_rounded,
                      activeIcon: Icons.bookmark_rounded,
                      count: social.saveCount,
                      active: social.saved,
                      activeColor: colors.actionSave,
                      showZero: false,
                      iconSize: Space.s4,
                      gap: Space.s1,
                      semanticLabel: 'Saves, ${social.saveCount}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Staggered fade + rise, capped at [Stagger.max] and skipped entirely for
/// tiles that arrive mid-fling.
class _TileEntrance extends StatefulWidget {
  const _TileEntrance({required this.child, required this.staggerIndex});

  final Widget child;
  final int staggerIndex;

  @override
  State<_TileEntrance> createState() => _TileEntranceState();
}

class _TileEntranceState extends State<_TileEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: KDurations.base,
    value: widget.staggerIndex < 0 ? 1 : 0,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.staggerIndex < 0) return;
    final delay = KMotion.staggerDelay(widget.staggerIndex);
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = KMotion.duration(context, KDurations.base);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.staggerIndex < 0) return widget.child;
    final reduced = KMotion.reduced(context);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: reduced ? KCurves.linear : KCurves.emphasized,
    );
    final faded = FadeTransition(opacity: curved, child: widget.child);
    if (reduced) return faded;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.06),
        end: Offset.zero,
      ).animate(curved),
      child: faded,
    );
  }
}
