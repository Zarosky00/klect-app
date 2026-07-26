import 'catalog.dart';
import 'enums.dart';
import 'json.dart';
import 'post.dart';
import 'profile.dart';

/// The five live counters every entity carries.
class CloseupCounts {
  /// Creates a counter block.
  const CloseupCounts({
    this.like = 0,
    this.save = 0,
    this.repost = 0,
    this.comment = 0,
    this.view = 0,
  });

  /// Parses the `counts` block of `get_closeup`.
  factory CloseupCounts.fromJson(Map<String, dynamic> json) => CloseupCounts(
        like: asInt(json['like']),
        save: asInt(json['save']),
        repost: asInt(json['repost']),
        comment: asInt(json['comment']),
        view: asInt(json['view']),
      );

  /// Trigger-maintained like count.
  final int like;

  /// Trigger-maintained save count.
  final int save;

  /// Trigger-maintained repost count.
  final int repost;

  /// Trigger-maintained comment count.
  final int comment;

  /// Trigger-maintained view count.
  final int view;
}

/// What the current viewer has done to this entity.
class CloseupViewer {
  /// Creates a viewer block.
  const CloseupViewer({
    this.liked = false,
    this.saved = false,
    this.reposted = false,
    this.follows = false,
    this.isOwner = false,
  });

  /// Parses the `viewer` block of `get_closeup`. All fields are null for
  /// anonymous visitors, which reads as "has done nothing".
  factory CloseupViewer.fromJson(Map<String, dynamic> json) => CloseupViewer(
        liked: asBool(json['liked']),
        saved: asBool(json['saved']),
        reposted: asBool(json['reposted']),
        follows: asBool(json['follows']),
        isOwner: asBool(json['is_owner']),
      );

  /// Viewer has liked it.
  final bool liked;

  /// Viewer has saved it.
  final bool saved;

  /// Viewer has reposted it.
  final bool reposted;

  /// Viewer follows the owner.
  final bool follows;

  /// Viewer owns it — unlocks edit/delete affordances.
  final bool isOwner;
}

/// A minimal `{id, name, slug}` reference, used by breadcrumbs.
class EntityRefLite {
  /// Creates a lightweight reference.
  const EntityRefLite({required this.id, required this.name, this.slug});

  /// Parses `{id, name, slug}`.
  factory EntityRefLite.fromJson(Map<String, dynamic> json) => EntityRefLite(
        id: asString(json['id']),
        name: asString(json['name']),
        slug: asStringOrNull(json['slug']),
      );

  /// Entity id.
  final String id;

  /// Display name.
  final String name;

  /// URL slug.
  final String? slug;
}

/// `Anime > JJK` — the trail above the entity being shown.
class CloseupBreadcrumb {
  /// Creates a breadcrumb.
  const CloseupBreadcrumb({this.collection, this.subcollection});

  /// Parses the `breadcrumb` block.
  factory CloseupBreadcrumb.fromJson(Map<String, dynamic> json) {
    final collection = asMap(json['collection']);
    final subcollection = asMap(json['subcollection']);
    return CloseupBreadcrumb(
      collection: collection.isEmpty ? null : EntityRefLite.fromJson(collection),
      subcollection: subcollection.isEmpty
          ? null
          : EntityRefLite.fromJson(subcollection),
    );
  }

  /// The owning collection.
  final EntityRefLite? collection;

  /// The owning subcollection — null when the closeup *is* a subcollection.
  final EntityRefLite? subcollection;

  /// Rendered trail, e.g. `Anime · JJK`.
  List<EntityRefLite> get trail => <EntityRefLite>[
        ?collection,
        ?subcollection,
      ];
}

/// A sibling or child item card inside a closeup.
class CloseupItemRef {
  /// Creates an item reference.
  const CloseupItemRef({
    required this.id,
    required this.title,
    this.coverPath,
    this.coverBlurhash,
    this.coverWidth,
    this.coverHeight,
    this.likeCount = 0,
    this.saveCount = 0,
    this.commentCount = 0,
    this.mediaCount = 0,
    this.position = 0,
    this.subcollectionId,
  });

  /// Parses an entry of `siblings[]` or `items[]`.
  factory CloseupItemRef.fromJson(Map<String, dynamic> json) => CloseupItemRef(
        id: asString(json['id']),
        title: asString(json['title']),
        coverPath: asStringOrNull(json['cover_path']),
        coverBlurhash: asStringOrNull(json['cover_blurhash']),
        coverWidth: asIntOrNull(json['cover_width']),
        coverHeight: asIntOrNull(json['cover_height']),
        likeCount: asInt(json['like_count']),
        saveCount: asInt(json['save_count']),
        commentCount: asInt(json['comment_count']),
        mediaCount: asInt(json['media_count']),
        position: asInt(json['position']),
        subcollectionId: asStringOrNull(json['subcollection_id']),
      );

  /// Item id.
  final String id;

  /// Item title.
  final String title;

  /// Cover storage path.
  final String? coverPath;

  /// Blurhash of the cover.
  final String? coverBlurhash;

  /// Intrinsic cover width.
  final int? coverWidth;

  /// Intrinsic cover height.
  final int? coverHeight;

  /// Live like count.
  final int likeCount;

  /// Live save count.
  final int saveCount;

  /// Live comment count.
  final int commentCount;

  /// Number of photos.
  final int mediaCount;

  /// Sort order.
  final int position;

  /// Parent subcollection, present on collection closeups.
  final String? subcollectionId;

  /// Aspect ratio, or null when unknown.
  double? get aspect {
    final w = coverWidth;
    final h = coverHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }
}

/// A child subcollection card inside a collection closeup.
class CloseupSubcollectionRef {
  /// Creates a subcollection reference.
  const CloseupSubcollectionRef({
    required this.id,
    required this.name,
    this.slug,
    this.coverPath,
    this.coverBlurhash,
    this.itemCount = 0,
    this.position = 0,
  });

  /// Parses an entry of `subcollections[]`.
  factory CloseupSubcollectionRef.fromJson(Map<String, dynamic> json) =>
      CloseupSubcollectionRef(
        id: asString(json['id']),
        name: asString(json['name']),
        slug: asStringOrNull(json['slug']),
        coverPath: asStringOrNull(json['cover_path']),
        coverBlurhash: asStringOrNull(json['cover_blurhash']),
        itemCount: asInt(json['item_count']),
        position: asInt(json['position']),
      );

  /// Subcollection id.
  final String id;

  /// Display name.
  final String name;

  /// URL slug.
  final String? slug;

  /// Cover storage path.
  final String? coverPath;

  /// Blurhash of the cover.
  final String? coverBlurhash;

  /// How many items it holds.
  final int itemCount;

  /// Sort order.
  final int position;
}

/// The payload of `get_closeup` — the single-tap detail sheet.
///
/// One class covers all four shapes; the type-specific blocks are nullable and
/// [entityType] tells you which are populated:
///
/// | type | populated |
/// |---|---|
/// | `item` | [item], [media], [breadcrumb], [siblings] |
/// | `subcollection` | [subcollection], [breadcrumb], [items] |
/// | `collection` | [collection], [subcollections], [items] |
/// | `post` | [post] |
class Closeup {
  /// Creates a closeup payload.
  const Closeup({
    required this.entityType,
    required this.entityId,
    required this.owner,
    required this.counts,
    required this.viewer,
    this.tags = const <String>[],
    this.item,
    this.media = const <ItemMedia>[],
    this.breadcrumb,
    this.siblings = const <CloseupItemRef>[],
    this.subcollection,
    this.items = const <CloseupItemRef>[],
    this.collection,
    this.subcollections = const <CloseupSubcollectionRef>[],
    this.post,
  });

  /// Parses the whole `get_closeup` payload.
  factory Closeup.fromJson(Map<String, dynamic> json) {
    final breadcrumb = asMap(json['breadcrumb']);
    final item = asMap(json['item']);
    final subcollection = asMap(json['subcollection']);
    final collection = asMap(json['collection']);
    final post = asMap(json['post']);
    return Closeup(
      entityType: EntityType.parse(json['entity_type']),
      entityId: asString(json['entity_id']),
      owner: Profile.fromJson(asMap(json['owner'])),
      counts: CloseupCounts.fromJson(asMap(json['counts'])),
      viewer: CloseupViewer.fromJson(asMap(json['viewer'])),
      tags: asStringList(json['tags']),
      item: item.isEmpty ? null : ItemModel.fromJson(item),
      media: <ItemMedia>[
        for (final m in asMapList(json['media'])) ItemMedia.fromJson(m),
      ]..sort((a, b) => a.position.compareTo(b.position)),
      breadcrumb:
          breadcrumb.isEmpty ? null : CloseupBreadcrumb.fromJson(breadcrumb),
      siblings: <CloseupItemRef>[
        for (final s in asMapList(json['siblings'])) CloseupItemRef.fromJson(s),
      ],
      subcollection: subcollection.isEmpty
          ? null
          : SubcollectionModel.fromJson(subcollection),
      items: <CloseupItemRef>[
        for (final i in asMapList(json['items'])) CloseupItemRef.fromJson(i),
      ],
      collection:
          collection.isEmpty ? null : CollectionModel.fromJson(collection),
      subcollections: <CloseupSubcollectionRef>[
        for (final s in asMapList(json['subcollections']))
          CloseupSubcollectionRef.fromJson(s),
      ],
      post: post.isEmpty ? null : PostModel.fromJson(post),
    );
  }

  /// Which level this closeup shows.
  final EntityType entityType;

  /// The entity's id.
  final String entityId;

  /// The owning profile (partial projection — counts + avatar + bio).
  final Profile owner;

  /// Authoritative counters at fetch time.
  final CloseupCounts counts;

  /// What the viewer has already done.
  final CloseupViewer viewer;

  /// Tag slugs attached to this entity.
  final List<String> tags;

  /// Item body — only for `entity_type = 'item'`.
  final ItemModel? item;

  /// Every photo of the item, ordered by `position`.
  final List<ItemMedia> media;

  /// Parent trail. Absent on collection closeups (they *are* the root).
  final CloseupBreadcrumb? breadcrumb;

  /// Other items in the same subcollection.
  final List<CloseupItemRef> siblings;

  /// Subcollection body — only for `entity_type = 'subcollection'`.
  final SubcollectionModel? subcollection;

  /// Child items, for subcollection and collection closeups.
  final List<CloseupItemRef> items;

  /// Collection body — only for `entity_type = 'collection'`.
  final CollectionModel? collection;

  /// Child subcollections, for collection closeups.
  final List<CloseupSubcollectionRef> subcollections;

  /// Post body — only for `entity_type = 'post'`.
  final PostModel? post;

  /// Headline for the sheet, whichever level this is.
  String get title => switch (entityType) {
        EntityType.item => item?.title ?? '',
        EntityType.subcollection => subcollection?.name ?? '',
        EntityType.collection => collection?.name ?? '',
        EntityType.post => post?.body ?? '',
        EntityType.comment => '',
      };

  /// Long-form body text for the sheet, if the level has one.
  String? get description => switch (entityType) {
        EntityType.item => item?.description,
        EntityType.subcollection => subcollection?.description,
        EntityType.collection => collection?.description,
        EntityType.post => post?.body,
        EntityType.comment => null,
      };

  /// The images the immersive viewer should page through. Item closeups have
  /// real media rows; the other levels fall back to their child covers.
  List<String> get immersivePaths => <String>[
        if (media.isNotEmpty)
          for (final m in media) m.storagePath
        else ...<String>[
          for (final i in items)
            if (i.coverPath != null) i.coverPath!,
        ],
      ];
}
