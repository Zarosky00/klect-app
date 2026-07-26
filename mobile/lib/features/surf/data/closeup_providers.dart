import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/klect_api.dart';
import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';

/// One photo the Closeup pager and the Immersive viewer can show.
///
/// An item closeup has real `item_media` rows; the other two levels fall back
/// to their own cover followed by their children's, so paging through a
/// collection still feels like a gallery.
class ImmersiveMedia {
  /// Creates a photo reference.
  const ImmersiveMedia({
    required this.path,
    this.blurhash,
    this.altText,
    this.width,
    this.height,
  });

  /// Storage path or absolute URL — always resolve it with
  /// [KlectApi.publicUrl].
  final String path;

  /// Blurhash placeholder.
  final String? blurhash;

  /// Accessibility text. Screen readers read it alongside "photo N of M".
  final String? altText;

  /// Intrinsic pixel width, when known.
  final int? width;

  /// Intrinsic pixel height, when known.
  final int? height;

  /// Aspect ratio, or null when the source did not record dimensions.
  double? get aspect {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }
}

/// Every photo of a closeup, in the order the viewer should page through them.
///
/// Index 0 is always the entity's **own** cover, which is what the Surf tile
/// showed — that is what makes the shared-element hero land on the right
/// picture.
List<ImmersiveMedia> immersiveMediaOf(Closeup closeup) {
  if (closeup.media.isNotEmpty) {
    return <ImmersiveMedia>[
      for (final media in closeup.media)
        ImmersiveMedia(
          path: media.storagePath,
          blurhash: media.blurhash,
          altText: media.altText ?? closeup.title,
          width: media.width,
          height: media.height,
        ),
    ];
  }

  final own = switch (closeup.entityType) {
    EntityType.collection => closeup.collection?.coverPath,
    EntityType.subcollection => closeup.subcollection?.coverPath,
    _ => null,
  };
  final ownHash = switch (closeup.entityType) {
    EntityType.collection => closeup.collection?.coverBlurhash,
    EntityType.subcollection => closeup.subcollection?.coverBlurhash,
    _ => null,
  };

  final seen = <String>{};
  final out = <ImmersiveMedia>[];
  void add(ImmersiveMedia media) {
    if (media.path.isEmpty) return;
    if (!seen.add(media.path)) return;
    out.add(media);
  }

  if (own != null) {
    add(ImmersiveMedia(path: own, blurhash: ownHash, altText: closeup.title));
  }
  for (final sub in closeup.subcollections) {
    final path = sub.coverPath;
    if (path == null) continue;
    add(
      ImmersiveMedia(
        path: path,
        blurhash: sub.coverBlurhash,
        altText: sub.name,
      ),
    );
  }
  for (final item in closeup.items) {
    final path = item.coverPath;
    if (path == null) continue;
    add(
      ImmersiveMedia(
        path: path,
        blurhash: item.coverBlurhash,
        altText: item.title,
        width: item.coverWidth,
        height: item.coverHeight,
      ),
    );
  }
  return out;
}

/// A post's own photos (`post_media`, 0018) as pager-ready media.
///
/// `get_closeup` predates first-class post photos, so post closeups and the
/// immersive viewer fetch them through this companion provider and fall back
/// to the payload's own media when the entity is not a post.
final postMediaProvider =
    FutureProvider.autoDispose.family<List<ImmersiveMedia>, String>(
  (ref, postId) async {
    final media = await ref.watch(klectApiProvider).fetchPostMedia(postId);
    return <ImmersiveMedia>[
      for (final m in media)
        ImmersiveMedia(
          path: m.storagePath,
          blurhash: m.blurhash,
          altText: m.altText,
          width: m.width,
          height: m.height,
        ),
    ];
  },
  name: 'postMedia',
);

/// The `get_closeup` payload for one entity.
///
/// Auto-disposing so a long browsing session does not accumulate payloads, but
/// the Closeup → Immersive escalation keeps it alive: the immersive route is
/// built (and starts watching) before the closeup route is disposed, so the
/// same fetch serves both.
///
/// Fetching also seeds the optimistic engine with the authoritative
/// `{viewer, counts}` block, so the action bar renders the truth on its very
/// first frame instead of flashing zeros.
final closeupProvider =
    FutureProvider.autoDispose.family<Closeup, EntityRef>(
  (ref, entity) async {
    final closeup =
        await ref.watch(klectApiProvider).getCloseup(entity.type, entity.id);
    ref
        .read(interactionSeedStoreProvider)
        .put(entity, InteractionState.fromCloseup(closeup));
    return closeup;
  },
  name: 'closeup',
);
