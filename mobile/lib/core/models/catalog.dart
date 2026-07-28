import 'enums.dart';
import 'json.dart';

/// A row of `public.collections` — the top-level shelf, e.g. "Anime".
class CollectionModel {
  /// Creates a collection.
  const CollectionModel({
    required this.id,
    required this.name,
    this.userId,
    this.templateId,
    this.slug,
    this.description,
    this.coverPath,
    this.coverBlurhash,
    this.accentColor,
    this.visibility,
    this.isFeatured = false,
    this.isPinned = false,
    this.position = 0,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.quoteCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.subcollectionCount = 0,
    this.itemCount = 0,
    this.hiddenAt,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Parses a `collections` row, or the `collection` block of `get_closeup`.
  factory CollectionModel.fromJson(Map<String, dynamic> json) =>
      CollectionModel(
        id: asString(json['id']),
        name: asString(json['name']),
        userId: asStringOrNull(json['user_id']),
        templateId: asStringOrNull(json['template_id']),
        slug: asStringOrNull(json['slug']),
        description: asStringOrNull(json['description']),
        coverPath: asStringOrNull(json['cover_path']),
        coverBlurhash: asStringOrNull(json['cover_blurhash']),
        accentColor: asStringOrNull(json['accent_color']),
        visibility: EntityVisibility.tryParse(json['visibility']),
        isFeatured: asBool(json['is_featured']),
        isPinned: asBool(json['is_pinned']),
        position: asInt(json['position']),
        likeCount: asInt(json['like_count']),
        saveCount: asInt(json['save_count']),
        repostCount: asInt(json['repost_count']),
        quoteCount: asInt(json['quote_count']),
        commentCount: asInt(json['comment_count']),
        viewCount: asInt(json['view_count']),
        subcollectionCount: asInt(json['subcollection_count']),
        itemCount: asInt(json['item_count']),
        hiddenAt: asDateOrNull(json['hidden_at']),
        deletedAt: asDateOrNull(json['deleted_at']),
        createdAt: asDateOrNull(json['created_at']),
        updatedAt: asDateOrNull(json['updated_at']),
      );

  /// Primary key.
  final String id;

  /// Display name, rendered in Instrument Serif.
  final String name;

  /// Owner.
  final String? userId;

  /// The `collection_templates` row this was seeded from, if any.
  final String? templateId;

  /// URL slug, unique per owner.
  final String? slug;

  /// Free text description.
  final String? description;

  /// Storage path of the cover image.
  final String? coverPath;

  /// Blurhash placeholder for [coverPath].
  final String? coverBlurhash;

  /// Optional hex accent for this shelf.
  final String? accentColor;

  /// Explicit visibility. Never null on a collection in practice.
  final EntityVisibility? visibility;

  /// Staff-set feature flag.
  final bool isFeatured;

  /// Pinned to the top of the owner's profile.
  final bool isPinned;

  /// Manual sort order on the profile.
  final int position;

  /// Trigger-maintained. Never COUNT(*) this in the client.
  final int likeCount;

  /// Trigger-maintained.
  final int saveCount;

  /// Trigger-maintained.
  final int repostCount;

  /// Trigger-maintained quote count.
  final int quoteCount;

  /// Trigger-maintained.
  final int commentCount;

  /// Trigger-maintained, deduped per viewer per day by `record_view`.
  final int viewCount;

  /// Trigger-maintained structural count.
  final int subcollectionCount;

  /// Trigger-maintained structural count.
  final int itemCount;

  /// Set by moderation.
  final DateTime? hiddenAt;

  /// Soft delete.
  final DateTime? deletedAt;

  /// Row creation time.
  final DateTime? createdAt;

  /// Last mutation time.
  final DateTime? updatedAt;

  /// The polymorphic type of this row.
  EntityType get entityType => EntityType.collection;
}

/// A row of `public.subcollections` — e.g. "JJK" inside "Anime".
class SubcollectionModel {
  /// Creates a subcollection.
  const SubcollectionModel({
    required this.id,
    required this.name,
    this.collectionId,
    this.userId,
    this.slug,
    this.description,
    this.coverPath,
    this.coverBlurhash,
    this.visibility,
    this.position = 0,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.quoteCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.itemCount = 0,
    this.hiddenAt,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Parses a `subcollections` row, or the `subcollection` closeup block.
  factory SubcollectionModel.fromJson(Map<String, dynamic> json) =>
      SubcollectionModel(
        id: asString(json['id']),
        name: asString(json['name']),
        collectionId: asStringOrNull(json['collection_id']),
        userId: asStringOrNull(json['user_id']),
        slug: asStringOrNull(json['slug']),
        description: asStringOrNull(json['description']),
        coverPath: asStringOrNull(json['cover_path']),
        coverBlurhash: asStringOrNull(json['cover_blurhash']),
        visibility: EntityVisibility.tryParse(json['visibility']),
        position: asInt(json['position']),
        likeCount: asInt(json['like_count']),
        saveCount: asInt(json['save_count']),
        repostCount: asInt(json['repost_count']),
        quoteCount: asInt(json['quote_count']),
        commentCount: asInt(json['comment_count']),
        viewCount: asInt(json['view_count']),
        itemCount: asInt(json['item_count']),
        hiddenAt: asDateOrNull(json['hidden_at']),
        deletedAt: asDateOrNull(json['deleted_at']),
        createdAt: asDateOrNull(json['created_at']),
        updatedAt: asDateOrNull(json['updated_at']),
      );

  /// Primary key.
  final String id;

  /// Display name.
  final String name;

  /// Parent collection.
  final String? collectionId;

  /// Owner.
  final String? userId;

  /// URL slug, unique per collection.
  final String? slug;

  /// Free text description.
  final String? description;

  /// Storage path of the cover image.
  final String? coverPath;

  /// Blurhash placeholder for [coverPath].
  final String? coverBlurhash;

  /// Null means "inherit the parent collection's visibility".
  final EntityVisibility? visibility;

  /// Manual sort order inside the collection.
  final int position;

  /// Trigger-maintained.
  final int likeCount;

  /// Trigger-maintained.
  final int saveCount;

  /// Trigger-maintained.
  final int repostCount;

  /// Trigger-maintained quote count.
  final int quoteCount;

  /// Trigger-maintained.
  final int commentCount;

  /// Trigger-maintained.
  final int viewCount;

  /// Trigger-maintained structural count.
  final int itemCount;

  /// Set by moderation.
  final DateTime? hiddenAt;

  /// Soft delete.
  final DateTime? deletedAt;

  /// Row creation time.
  final DateTime? createdAt;

  /// Last mutation time.
  final DateTime? updatedAt;

  /// The polymorphic type of this row.
  EntityType get entityType => EntityType.subcollection;
}

/// A row of `public.items` — a thing, with 1..n photos.
class ItemModel {
  /// Creates an item.
  const ItemModel({
    required this.id,
    required this.title,
    this.userId,
    this.collectionId,
    this.subcollectionId,
    this.description,
    this.brand,
    this.model,
    this.year,
    this.condition,
    this.rarity,
    this.acquisitionDate,
    this.acquisitionPlace,
    this.purchasePrice,
    this.currency,
    this.isFavorite = false,
    this.visibility,
    this.attributes = const <String, dynamic>{},
    this.position = 0,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.quoteCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.mediaCount = 0,
    this.coverPath,
    this.coverBlurhash,
    this.coverWidth,
    this.coverHeight,
    this.hiddenAt,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Parses an `items` row, or the `item` block of `get_closeup`.
  factory ItemModel.fromJson(Map<String, dynamic> json) => ItemModel(
    id: asString(json['id']),
    title: asString(json['title']),
    userId: asStringOrNull(json['user_id']),
    collectionId: asStringOrNull(json['collection_id']),
    subcollectionId: asStringOrNull(json['subcollection_id']),
    description: asStringOrNull(json['description']),
    brand: asStringOrNull(json['brand']),
    model: asStringOrNull(json['model']),
    year: asIntOrNull(json['year']),
    condition: asStringOrNull(json['condition']),
    rarity: asStringOrNull(json['rarity']),
    acquisitionDate: asDateOrNull(json['acquisition_date']),
    acquisitionPlace: asStringOrNull(json['acquisition_place']),
    purchasePrice: asDoubleOrNull(json['purchase_price']),
    currency: asStringOrNull(json['currency']),
    isFavorite: asBool(json['is_favorite']),
    visibility: EntityVisibility.tryParse(json['visibility']),
    attributes: asMap(json['attributes']),
    position: asInt(json['position']),
    likeCount: asInt(json['like_count']),
    saveCount: asInt(json['save_count']),
    repostCount: asInt(json['repost_count']),
    quoteCount: asInt(json['quote_count']),
    commentCount: asInt(json['comment_count']),
    viewCount: asInt(json['view_count']),
    mediaCount: asInt(json['media_count']),
    coverPath: asStringOrNull(json['cover_path']),
    coverBlurhash: asStringOrNull(json['cover_blurhash']),
    coverWidth: asIntOrNull(json['cover_width']),
    coverHeight: asIntOrNull(json['cover_height']),
    hiddenAt: asDateOrNull(json['hidden_at']),
    deletedAt: asDateOrNull(json['deleted_at']),
    createdAt: asDateOrNull(json['created_at']),
    updatedAt: asDateOrNull(json['updated_at']),
  );

  /// Primary key.
  final String id;

  /// Display title.
  final String title;

  /// Owner.
  final String? userId;

  /// Parent collection (denormalised for feed queries).
  final String? collectionId;

  /// Parent subcollection.
  final String? subcollectionId;

  /// Long description.
  final String? description;

  /// Maker / publisher — rendered as the card subtitle.
  final String? brand;

  /// Model designation.
  final String? model;

  /// Year of manufacture or release.
  final int? year;

  /// Free text condition grade.
  final String? condition;

  /// Free text rarity grade.
  final String? rarity;

  /// When the owner acquired it.
  final DateTime? acquisitionDate;

  /// Where the owner acquired it.
  final String? acquisitionPlace;

  /// What the owner paid.
  final double? purchasePrice;

  /// ISO currency code for [purchasePrice].
  final String? currency;

  /// Owner's favourite flag.
  final bool isFavorite;

  /// Null means "inherit the parent subcollection's visibility".
  final EntityVisibility? visibility;

  /// Template-driven extra fields, free-form JSON.
  final Map<String, dynamic> attributes;

  /// Manual sort order inside the subcollection.
  final int position;

  /// Trigger-maintained.
  final int likeCount;

  /// Trigger-maintained.
  final int saveCount;

  /// Trigger-maintained.
  final int repostCount;

  /// Trigger-maintained quote count.
  final int quoteCount;

  /// Trigger-maintained.
  final int commentCount;

  /// Trigger-maintained.
  final int viewCount;

  /// Trigger-maintained number of `item_media` rows.
  final int mediaCount;

  /// Auto-derived from the media at position 0.
  final String? coverPath;

  /// Blurhash of [coverPath].
  final String? coverBlurhash;

  /// Intrinsic pixel width of the cover — reserves the masonry tile.
  final int? coverWidth;

  /// Intrinsic pixel height of the cover — reserves the masonry tile.
  final int? coverHeight;

  /// Set by moderation.
  final DateTime? hiddenAt;

  /// Soft delete.
  final DateTime? deletedAt;

  /// Row creation time.
  final DateTime? createdAt;

  /// Last mutation time.
  final DateTime? updatedAt;

  /// The polymorphic type of this row.
  EntityType get entityType => EntityType.item;

  /// Cover aspect ratio (width / height), or null when unknown.
  double? get coverAspect {
    final w = coverWidth;
    final h = coverHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }
}

/// A row of `public.item_media` — one photo of an item.
class ItemMedia {
  /// Creates a media row.
  const ItemMedia({
    required this.id,
    required this.storagePath,
    this.itemId,
    this.userId,
    this.altText,
    this.width,
    this.height,
    this.blurhash,
    this.dominantColor,
    this.mimeType,
    this.bytes,
    this.position = 0,
    this.createdAt,
  });

  /// Parses an `item_media` row or a closeup `media[]` entry.
  factory ItemMedia.fromJson(Map<String, dynamic> json) => ItemMedia(
    id: asString(json['id']),
    storagePath: asString(json['storage_path']),
    itemId: asStringOrNull(json['item_id']),
    userId: asStringOrNull(json['user_id']),
    altText: asStringOrNull(json['alt_text']),
    width: asIntOrNull(json['width']),
    height: asIntOrNull(json['height']),
    blurhash: asStringOrNull(json['blurhash']),
    dominantColor: asStringOrNull(json['dominant_color']),
    mimeType: asStringOrNull(json['mime_type']),
    bytes: asIntOrNull(json['bytes']),
    position: asInt(json['position']),
    createdAt: asDateOrNull(json['created_at']),
  );

  /// Primary key.
  final String id;

  /// Path inside the `media` bucket.
  final String storagePath;

  /// Parent item.
  final String? itemId;

  /// Uploader — must be the first path segment of [storagePath].
  final String? userId;

  /// Accessibility text. The closeup surfaces this.
  final String? altText;

  /// Intrinsic pixel width.
  final int? width;

  /// Intrinsic pixel height.
  final int? height;

  /// Blurhash placeholder.
  final String? blurhash;

  /// Dominant hex colour, for scrim tinting.
  final String? dominantColor;

  /// MIME type as uploaded.
  final String? mimeType;

  /// File size in bytes.
  final int? bytes;

  /// Order within the item. Position 0 becomes the item cover.
  final int position;

  /// Row creation time.
  final DateTime? createdAt;

  /// Aspect ratio (width / height), or null when unknown.
  double? get aspect {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }
}

/// A row of `public.collection_templates` — the onboarding interest picker.
class CollectionTemplate {
  /// Creates a template.
  const CollectionTemplate({
    required this.id,
    required this.slug,
    required this.name,
    this.icon,
    this.description,
    this.accentColor,
    this.suggestedFields = const <Map<String, dynamic>>[],
    this.suggestedTags = const <String>[],
    this.sortOrder = 0,
  });

  /// Parses a `collection_templates` row.
  factory CollectionTemplate.fromJson(Map<String, dynamic> json) =>
      CollectionTemplate(
        id: asString(json['id']),
        slug: asString(json['slug']),
        name: asString(json['name']),
        icon: asStringOrNull(json['icon']),
        description: asStringOrNull(json['description']),
        accentColor: asStringOrNull(json['accent_color']),
        suggestedFields: asMapList(json['suggested_fields']),
        suggestedTags: asStringList(json['suggested_tags']),
        sortOrder: asInt(json['sort_order']),
      );

  /// Primary key.
  final String id;

  /// Stable slug, e.g. `anime`.
  final String slug;

  /// Display name.
  final String name;

  /// Icon key.
  final String? icon;

  /// One-line pitch shown under the name.
  final String? description;

  /// Suggested hex accent for collections seeded from this template.
  final String? accentColor;

  /// Extra item fields this template suggests.
  final List<Map<String, dynamic>> suggestedFields;

  /// Tags pre-attached to collections seeded from this template.
  final List<String> suggestedTags;

  /// Display order in the picker.
  final int sortOrder;
}

/// A row of `public.tags`.
class TagModel {
  /// Creates a tag.
  const TagModel({
    required this.slug,
    required this.name,
    this.id,
    this.useCount = 0,
  });

  /// Parses a `tags` row or a `search_all` tag entry.
  factory TagModel.fromJson(Map<String, dynamic> json) => TagModel(
    slug: asString(json['slug']),
    name: asString(json['name']),
    id: asStringOrNull(json['id']),
    useCount: asInt(json['use_count']),
  );

  /// Primary key. Absent from `search_all` projections.
  final String? id;

  /// URL-safe slug.
  final String slug;

  /// Display name.
  final String name;

  /// How many entities carry this tag.
  final int useCount;
}
