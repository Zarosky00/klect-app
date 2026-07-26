import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';
import '../../../design/theme.dart';
import '../../../ui/ui.dart';
import '../../create/widgets/entity_visual.dart';
import 'library_chrome.dart';
import 'quick_actions_sheet.dart';

/// A shelf tile: square cover, serif name, structural counts.
///
/// Carries the full gesture contract — tap drills in, double tap escalates to
/// the immersive viewer, long press opens the peek — with no double-tap delay,
/// because [KGestureRegion] resolves the ambiguity itself.
class CollectionCard extends ConsumerWidget {
  /// Creates a shelf tile.
  const CollectionCard({
    required this.collection,
    super.key,
    this.isOwner = false,
    this.ownerActions = const <QuickOwnerAction>[],
  });

  /// The row to render.
  final CollectionModel collection;

  /// Unlocks the owner rows inside the peek.
  final bool isOwner;

  /// Owner rows offered by the peek.
  final List<QuickOwnerAction> ownerActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final accent = EntityVisual.accent(context, collection.accentColor);

    return KGestureRegion(
      semanticLabel: collection.name,
      onTap: () => LibraryNavigation.open(
        context,
        EntityType.collection,
        collection.id,
      ),
      onDoubleTap: () => LibraryNavigation.immersive(
        context,
        EntityType.collection,
        collection.id,
      ),
      onLongPress: () => QuickActionsSheet.show(
        context,
        entity: EntityRef.collection(collection.id),
        title: collection.name,
        isOwner: isOwner,
        ownerActions: ownerActions,
        seed: InteractionState(
          likeCount: collection.likeCount,
          saveCount: collection.saveCount,
          repostCount: collection.repostCount,
          commentCount: collection.commentCount,
          viewCount: collection.viewCount,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface2,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      border: Border.all(
                        color: colors.borderSubtle,
                        width: Strokes.thin,
                      ),
                    ),
                    child: collection.coverPath == null
                        ? Center(
                            child: Icon(
                              Icons.collections_bookmark_rounded,
                              size: Space.s8,
                              color: accent,
                            ),
                          )
                        : KBlurhashImage(
                            url: api.publicUrl(collection.coverPath),
                            blurhash: collection.coverBlurhash,
                            fit: BoxFit.cover,
                            heroTag: LibraryHero.cover(
                              EntityType.collection,
                              collection.id,
                            ),
                            borderRadius:
                                BorderRadius.circular(Radii.lg),
                            semanticLabel: '${collection.name} cover',
                          ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: Space.s3,
                  child: Container(
                    width: Space.s1,
                    height: Space.s6,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(Radii.full),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: Space.s2,
                  top: Space.s2,
                  child: VisibilityBadge(
                    visibility: collection.visibility,
                    dense: true,
                  ),
                ),
                if (collection.isPinned)
                  Positioned(
                    left: Space.s2,
                    bottom: Space.s2,
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: Space.s4,
                      color: colors.textPrimary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          Text(
            collection.name,
            style: context.kt.title3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          MetaLine(
            parts: <String>[
              plural(collection.subcollectionCount, 'group'),
              plural(collection.itemCount, 'item'),
            ],
          ),
        ],
      ),
    );
  }
}

/// A group tile for the rail inside a collection.
class SubcollectionCard extends ConsumerWidget {
  /// Creates a group tile.
  const SubcollectionCard({
    required this.subcollection,
    super.key,
    this.isOwner = false,
    this.ownerActions = const <QuickOwnerAction>[],
    this.width = Space.s24 + Space.s8,
    this.selected = false,
  });

  /// The row to render.
  final SubcollectionModel subcollection;

  /// Unlocks the owner rows inside the peek.
  final bool isOwner;

  /// Owner rows offered by the peek.
  final List<QuickOwnerAction> ownerActions;

  /// Rail tile width.
  final double width;

  /// Highlights the tile when it is the active filter.
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);

    return SizedBox(
      width: width,
      child: KGestureRegion(
        semanticLabel: subcollection.name,
        onTap: () => LibraryNavigation.open(
          context,
          EntityType.subcollection,
          subcollection.id,
        ),
        onDoubleTap: () => LibraryNavigation.immersive(
          context,
          EntityType.subcollection,
          subcollection.id,
        ),
        onLongPress: () => QuickActionsSheet.show(
          context,
          entity: EntityRef.subcollection(subcollection.id),
          title: subcollection.name,
          isOwner: isOwner,
          ownerActions: ownerActions,
          seed: InteractionState(
            likeCount: subcollection.likeCount,
            saveCount: subcollection.saveCount,
            repostCount: subcollection.repostCount,
            commentCount: subcollection.commentCount,
            viewCount: subcollection.viewCount,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Stack(
              children: <Widget>[
                Container(
                  width: width,
                  height: width,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colors.surface2,
                    borderRadius: BorderRadius.circular(Radii.md),
                    border: Border.all(
                      color: selected
                          ? colors.accentDefault
                          : colors.borderSubtle,
                      width: selected ? Strokes.thick : Strokes.thin,
                    ),
                  ),
                  child: subcollection.coverPath == null
                      ? Icon(
                          Icons.folder_rounded,
                          size: Space.s7,
                          color: colors.textTertiary,
                        )
                      : KBlurhashImage(
                          url: api.publicUrl(subcollection.coverPath),
                          blurhash: subcollection.coverBlurhash,
                          fit: BoxFit.cover,
                          heroTag: LibraryHero.cover(
                            EntityType.subcollection,
                            subcollection.id,
                          ),
                          borderRadius: BorderRadius.circular(Radii.md),
                          semanticLabel: '${subcollection.name} cover',
                        ),
                ),
                Positioned(
                  right: Space.s1,
                  top: Space.s1,
                  child: VisibilityBadge(
                    visibility: subcollection.visibility,
                    dense: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.s15),
            Text(
              subcollection.name,
              style: context.kt.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            MetaLine(
              parts: <String>[plural(subcollection.itemCount, 'item')],
              style: context.kt.micro.copyWith(color: colors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// An item tile for the grid inside a collection or subcollection.
class ItemTile extends ConsumerWidget {
  /// Creates an item tile.
  const ItemTile({
    required this.item,
    super.key,
    this.isOwner = false,
    this.ownerActions = const <QuickOwnerAction>[],
    this.showSubtitle = true,
  });

  /// The row to render.
  final ItemModel item;

  /// Unlocks the owner rows inside the peek.
  final bool isOwner;

  /// Owner rows offered by the peek.
  final List<QuickOwnerAction> ownerActions;

  /// Shows the brand line under the title.
  final bool showSubtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);

    return KGestureRegion(
      semanticLabel: item.title,
      onTap: () => LibraryNavigation.open(context, EntityType.item, item.id),
      onDoubleTap: () =>
          LibraryNavigation.immersive(context, EntityType.item, item.id),
      onLongPress: () => QuickActionsSheet.show(
        context,
        entity: EntityRef.item(item.id),
        title: item.title,
        isOwner: isOwner,
        ownerActions: ownerActions,
        seed: InteractionState(
          likeCount: item.likeCount,
          saveCount: item.saveCount,
          repostCount: item.repostCount,
          commentCount: item.commentCount,
          viewCount: item.viewCount,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.md),
                    child: KBlurhashImage(
                      url: api.publicUrl(item.coverPath),
                      blurhash: item.coverBlurhash,
                      fit: BoxFit.cover,
                      heroTag: LibraryHero.cover(EntityType.item, item.id),
                      borderRadius: BorderRadius.circular(Radii.md),
                      semanticLabel: item.title,
                    ),
                  ),
                ),
                if (item.mediaCount > 1)
                  Positioned(
                    right: Space.s2,
                    top: Space.s2,
                    child: _CountChip(
                      icon: Icons.photo_library_rounded,
                      label: '${item.mediaCount}',
                    ),
                  ),
                if (item.isFavorite)
                  Positioned(
                    left: Space.s2,
                    top: Space.s2,
                    child: Icon(
                      Icons.star_rounded,
                      size: Space.s4,
                      color: colors.accentDefault,
                    ),
                  ),
                Positioned(
                  right: Space.s2,
                  bottom: Space.s2,
                  child: VisibilityBadge(
                    visibility: item.visibility,
                    dense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s15),
          Text(
            item.title,
            style: context.kt.callout,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (showSubtitle && (item.brand ?? '').isNotEmpty)
            MetaLine(
              parts: <String>[item.brand!],
              style: context.kt.micro.copyWith(color: colors.textTertiary),
            ),
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.kc;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s15,
        vertical: Space.sPx,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceScrim,
        borderRadius: BorderRadius.circular(Radii.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: Space.s3, color: colors.textPrimary),
          const SizedBox(width: Space.s1),
          Text(
            label,
            style: context.kt.count.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
