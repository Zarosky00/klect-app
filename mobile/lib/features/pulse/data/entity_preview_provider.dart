import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';

/// Just enough of a collection / subcollection / item to render it inline in
/// the Pulse stream, in one cheap single-row read.
///
/// Deliberately **not** `get_closeup`: an attachment card needs a title, a
/// cover and a child count, and paying for a whole closeup payload per row
/// would make the stream crawl.
@immutable
class EntityPreview {
  /// Creates a preview.
  const EntityPreview({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.coverPath,
    this.blurhash,
    this.width,
    this.height,
    this.childCount = 0,
    this.childLabel = 'things',
  });

  /// Which level this is.
  final EntityType type;

  /// Entity id.
  final String id;

  /// Headline.
  final String title;

  /// Secondary line — a brand, a description, a shelf name.
  final String? subtitle;

  /// Cover storage path or absolute URL.
  final String? coverPath;

  /// Blurhash of the cover.
  final String? blurhash;

  /// Intrinsic cover width, when the source recorded one.
  final int? width;

  /// Intrinsic cover height.
  final int? height;

  /// Children beneath this entity.
  final int childCount;

  /// What the children are called.
  final String childLabel;
}

/// A preview of any entity, cached for the session so scrolling the stream
/// back and forth does not refetch.
final entityPreviewProvider =
    FutureProvider.family<EntityPreview?, EntityRef>(
  (ref, entity) async {
    final api = ref.watch(klectApiProvider);
    final store = ref.read(interactionSeedStoreProvider);

    switch (entity.type) {
      case EntityType.item:
        final item = await api.fetchItem(entity.id);
        if (item == null) return null;
        store.put(
          entity,
          InteractionState(
            likeCount: item.likeCount,
            saveCount: item.saveCount,
            repostCount: item.repostCount,
            commentCount: item.commentCount,
            viewCount: item.viewCount,
            hydrated: true,
          ),
        );
        return EntityPreview(
          type: EntityType.item,
          id: item.id,
          title: item.title,
          subtitle: item.brand ?? item.description,
          coverPath: item.coverPath,
          blurhash: item.coverBlurhash,
          width: item.coverWidth,
          height: item.coverHeight,
          childCount: item.mediaCount,
          childLabel: 'photos',
        );

      case EntityType.subcollection:
        final sub = await api.fetchSubcollection(entity.id);
        if (sub == null) return null;
        return EntityPreview(
          type: EntityType.subcollection,
          id: sub.id,
          title: sub.name,
          subtitle: sub.description,
          coverPath: sub.coverPath,
          blurhash: sub.coverBlurhash,
          childCount: sub.itemCount,
        );

      case EntityType.collection:
        final collection = await api.fetchCollection(entity.id);
        if (collection == null) return null;
        return EntityPreview(
          type: EntityType.collection,
          id: collection.id,
          title: collection.name,
          subtitle: collection.description,
          coverPath: collection.coverPath,
          blurhash: collection.coverBlurhash,
          childCount: collection.itemCount,
        );

      case EntityType.post:
      case EntityType.comment:
        return null;
    }
  },
  name: 'entityPreview',
);
