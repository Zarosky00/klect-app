import '../../design/tokens.g.dart';
import 'enums.dart';
import 'json.dart';

/// One tile of the Pinterest-style Surf grid — a row of `surf_feed`.
///
/// [width] / [height] are the cover's intrinsic pixels: reserve the tile from
/// them **before** the image loads so the masonry never reflows.
class SurfCard {
  /// Creates a surf card.
  const SurfCard({
    required this.entityType,
    required this.entityId,
    required this.ownerId,
    required this.username,
    this.displayName,
    this.avatarPath,
    this.isVerified = false,
    this.title,
    this.subtitle,
    this.coverPath,
    this.coverBlurhash,
    this.width,
    this.height,
    this.accentColor,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.quoteCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.childCount = 0,
    this.createdAt,
    this.score = 0,
    this.viewerLiked = false,
    this.viewerSaved = false,
    this.viewerReposted = false,
    this.viewerFollows = false,
    this.raw = const <String, dynamic>{},
  });

  /// Parses one `surf_card` row.
  factory SurfCard.fromJson(Map<String, dynamic> json) => SurfCard(
    entityType: EntityType.parse(json['entity_type']),
    entityId: asString(json['entity_id']),
    ownerId: asString(json['owner_id']),
    username: asString(json['username']),
    displayName: asStringOrNull(json['display_name']),
    avatarPath: asStringOrNull(json['avatar_path']),
    isVerified: asBool(json['is_verified']),
    title: asStringOrNull(json['title']),
    subtitle: asStringOrNull(json['subtitle']),
    coverPath: asStringOrNull(json['cover_path']),
    coverBlurhash: asStringOrNull(json['cover_blurhash']),
    width: asIntOrNull(json['width']),
    height: asIntOrNull(json['height']),
    accentColor: asStringOrNull(json['accent_color']),
    likeCount: asInt(json['like_count']),
    saveCount: asInt(json['save_count']),
    repostCount: asInt(json['repost_count']),
    quoteCount: asInt(json['quote_count']),
    commentCount: asInt(json['comment_count']),
    viewCount: asInt(json['view_count']),
    childCount: asInt(json['child_count']),
    createdAt: asDateOrNull(json['created_at']),
    score: asDouble(json['score']),
    viewerLiked: asBool(json['viewer_liked']),
    viewerSaved: asBool(json['viewer_saved']),
    viewerReposted: asBool(json['viewer_reposted']),
    viewerFollows: asBool(json['viewer_follows']),
    raw: json,
  );

  /// Which of the three levels this tile represents.
  final EntityType entityType;

  /// The entity's id — half of the polymorphic key.
  final String entityId;

  /// Owner's user id.
  final String ownerId;

  /// Owner's handle.
  final String username;

  /// Owner's display name.
  final String? displayName;

  /// Owner's avatar path or absolute URL.
  final String? avatarPath;

  /// Owner's verified badge.
  final bool isVerified;

  /// Card headline.
  final String? title;

  /// Card sub-headline (brand for items, parent name for subcollections).
  final String? subtitle;

  /// Cover storage path.
  final String? coverPath;

  /// Blurhash placeholder for the cover.
  final String? coverBlurhash;

  /// Intrinsic cover width in pixels.
  final int? width;

  /// Intrinsic cover height in pixels.
  final int? height;

  /// Optional hex accent from the owning collection.
  final String? accentColor;

  /// Live counter column.
  final int likeCount;

  /// Live counter column.
  final int saveCount;

  /// Live counter column.
  final int repostCount;

  /// Trigger-maintained quote count.
  final int quoteCount;

  /// Live counter column.
  final int commentCount;

  /// Live counter column.
  final int viewCount;

  /// Children beneath this entity (subcollections, items or media).
  final int childCount;

  /// Row creation time.
  final DateTime? createdAt;

  /// Ranking score, jittered per `p_seed`.
  final double score;

  /// Whether the viewer has liked this entity.
  final bool viewerLiked;

  /// Whether the viewer has saved this entity.
  final bool viewerSaved;

  /// Whether the viewer has reposted this entity.
  final bool viewerReposted;

  /// Whether the viewer follows the owner.
  final bool viewerFollows;

  /// The untouched `surf_card` row — what the offline first-page cache
  /// persists, so a cached card round-trips through [SurfCard.fromJson].
  final Map<String, dynamic> raw;

  /// Owner's display name, falling back to the handle.
  String get ownerName =>
      displayName?.isNotEmpty == true ? displayName! : username;

  /// Aspect ratio clamped into the grid's allowed band so one pathological
  /// image cannot own the whole column.
  double get tileAspect {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return Aspect.cover;
    return (w / h).clamp(Aspect.gridMin, Aspect.gridMax);
  }

  /// Stable identity for list keys and de-duplication across pages.
  String get key => '${entityType.wire}:$entityId';
}
