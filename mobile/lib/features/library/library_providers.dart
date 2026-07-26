import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/klect_api.dart';
import '../../core/interactions/interactions.dart';
import '../../core/models/models.dart';
import '../../core/supabase.dart';

/// A collection, everything under it, and what the viewer may do with it.
@immutable
class CollectionDetail {
  /// Creates a detail payload.
  const CollectionDetail({
    required this.closeup,
    required this.collection,
    required this.subcollections,
    required this.items,
  });

  /// The `get_closeup` payload — owner, live counters, viewer state.
  final Closeup closeup;

  /// The full collection row (visibility, accent, cover).
  final CollectionModel collection;

  /// Child subcollections in `position` order.
  final List<SubcollectionModel> subcollections;

  /// Every item on the shelf, in `position` order.
  final List<ItemModel> items;

  /// Owner-only affordances hang off this and nothing else.
  bool get isOwner => closeup.viewer.isOwner;

  /// The polymorphic key for the interaction engine.
  EntityRef get entity => EntityRef.collection(collection.id);
}

/// A subcollection and its items.
@immutable
class SubcollectionDetail {
  /// Creates a detail payload.
  const SubcollectionDetail({
    required this.closeup,
    required this.subcollection,
    required this.items,
    this.parent,
  });

  /// The `get_closeup` payload.
  final Closeup closeup;

  /// The full subcollection row.
  final SubcollectionModel subcollection;

  /// Items in `position` order.
  final List<ItemModel> items;

  /// The owning collection, for the breadcrumb and the move sheet.
  final CollectionModel? parent;

  /// Owner-only affordances hang off this and nothing else.
  bool get isOwner => closeup.viewer.isOwner;

  /// The polymorphic key for the interaction engine.
  EntityRef get entity => EntityRef.subcollection(subcollection.id);
}

/// An item, its photos and its trail.
@immutable
class ItemDetail {
  /// Creates a detail payload.
  const ItemDetail({
    required this.closeup,
    required this.item,
    required this.media,
    this.siblingSubcollections = const <SubcollectionModel>[],
  });

  /// The `get_closeup` payload — includes `breadcrumb` and `siblings`.
  final Closeup closeup;

  /// The full item row.
  final ItemModel item;

  /// Photos in `position` order. Position 0 is the cover.
  final List<ItemMedia> media;

  /// Every subcollection of the owning collection — the move sheet's options.
  /// Only populated for the owner; a visitor has no use for it.
  final List<SubcollectionModel> siblingSubcollections;

  /// Owner-only affordances hang off this and nothing else.
  bool get isOwner => closeup.viewer.isOwner;

  /// The polymorphic key for the interaction engine.
  EntityRef get entity => EntityRef.item(item.id);

  /// `Anime · JJK`.
  CloseupBreadcrumb? get breadcrumb => closeup.breadcrumb;
}

/// The signed-in user's own shelves, pinned first.
final myCollectionsProvider = FutureProvider<List<CollectionModel>>(
  (ref) async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const <CollectionModel>[];
    return ref.watch(klectApiProvider).fetchCollections(userId);
  },
  name: 'myCollections',
);

/// Any user's shelves — the profile grid reads this.
final userCollectionsProvider =
    FutureProvider.family<List<CollectionModel>, String>(
  (ref, userId) => ref.watch(klectApiProvider).fetchCollections(userId),
  name: 'userCollections',
);

/// The subcollections of one collection, in `position` order.
final subcollectionsOfProvider =
    FutureProvider.family<List<SubcollectionModel>, String>(
  (ref, collectionId) =>
      ref.watch(klectApiProvider).fetchSubcollections(collectionId),
  name: 'subcollectionsOf',
);

/// Everything the collection screen renders.
final collectionDetailProvider =
    FutureProvider.family<CollectionDetail, String>(
  (ref, collectionId) async {
    final api = ref.watch(klectApiProvider);
    final results = await Future.wait(<Future<Object?>>[
      api.getCloseup(EntityType.collection, collectionId),
      api.fetchSubcollections(collectionId),
      api.fetchItems(collectionId: collectionId, limit: 200),
    ]);
    final closeup = results[0]! as Closeup;
    final subcollections = results[1]! as List<SubcollectionModel>;
    final items = results[2]! as List<ItemModel>;

    ref.read(interactionSeedStoreProvider).put(
          EntityRef.collection(collectionId),
          InteractionState.fromCloseup(closeup),
        );

    return CollectionDetail(
      closeup: closeup,
      collection: closeup.collection ??
          CollectionModel(id: collectionId, name: closeup.title),
      subcollections: _ordered(
        subcollections,
        (s) => s.position,
        (s) => s.createdAt,
      ),
      items: _ordered(items, (i) => i.position, (i) => i.createdAt),
    );
  },
  name: 'collectionDetail',
);

/// Everything the subcollection screen renders.
final subcollectionDetailProvider =
    FutureProvider.family<SubcollectionDetail, String>(
  (ref, subcollectionId) async {
    final api = ref.watch(klectApiProvider);
    final results = await Future.wait(<Future<Object?>>[
      api.getCloseup(EntityType.subcollection, subcollectionId),
      api.fetchItems(subcollectionId: subcollectionId, limit: 200),
    ]);
    final closeup = results[0]! as Closeup;
    final items = results[1]! as List<ItemModel>;

    final subcollection = closeup.subcollection ??
        SubcollectionModel(id: subcollectionId, name: closeup.title);
    final parentId =
        closeup.breadcrumb?.collection?.id ?? subcollection.collectionId;
    final parent = parentId == null ? null : await api.fetchCollection(parentId);

    ref.read(interactionSeedStoreProvider).put(
          EntityRef.subcollection(subcollectionId),
          InteractionState.fromCloseup(closeup),
        );

    return SubcollectionDetail(
      closeup: closeup,
      subcollection: subcollection,
      items: _ordered(items, (i) => i.position, (i) => i.createdAt),
      parent: parent,
    );
  },
  name: 'subcollectionDetail',
);

/// Everything the item screen renders.
final itemDetailProvider = FutureProvider.family<ItemDetail, String>(
  (ref, itemId) async {
    final api = ref.watch(klectApiProvider);
    final closeup = await api.getCloseup(EntityType.item, itemId);
    final item = closeup.item ?? ItemModel(id: itemId, title: closeup.title);

    ref.read(interactionSeedStoreProvider).put(
          EntityRef.item(itemId),
          InteractionState.fromCloseup(closeup),
        );

    final collectionId =
        closeup.breadcrumb?.collection?.id ?? item.collectionId;
    final siblings = closeup.viewer.isOwner && collectionId != null
        ? await api.fetchSubcollections(collectionId)
        : const <SubcollectionModel>[];

    return ItemDetail(
      closeup: closeup,
      item: item,
      media: closeup.media.isNotEmpty
          ? closeup.media
          : await api.fetchItemMedia(itemId),
      siblingSubcollections: siblings,
    );
  },
  name: 'itemDetail',
);

/// `position` is not unique — every freshly-created row starts at 0 — so ties
/// are broken by age to keep the order stable between rebuilds.
List<T> _ordered<T>(
  List<T> rows,
  int Function(T) position,
  DateTime? Function(T) created,
) {
  final sorted = rows.toList();
  sorted.sort((a, b) {
    final byPosition = position(a).compareTo(position(b));
    if (byPosition != 0) return byPosition;
    final ca = created(a);
    final cb = created(b);
    if (ca == null || cb == null) return 0;
    return ca.compareTo(cb);
  });
  return List<T>.unmodifiable(sorted);
}

/// Cache invalidation after a write.
///
/// Every mutation in `features/library/` and `features/create/` funnels through
/// here, so no screen can forget to refresh a level of the hierarchy that its
/// change touched.
extension LibraryRefresh on WidgetRef {
  /// Refreshes every level a mutation may have touched.
  void refreshLibrary({
    String? collectionId,
    String? subcollectionId,
    String? itemId,
  }) {
    invalidate(myCollectionsProvider);
    if (collectionId != null) {
      invalidate(collectionDetailProvider(collectionId));
      invalidate(subcollectionsOfProvider(collectionId));
    }
    if (subcollectionId != null) {
      invalidate(subcollectionDetailProvider(subcollectionId));
    }
    if (itemId != null) {
      invalidate(itemDetailProvider(itemId));
    }
  }
}
