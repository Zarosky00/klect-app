import 'enums.dart';
import 'json.dart';
import 'profile.dart';

/// A row of `public.posts` — the unit of the Pulse stream.
///
/// A post may carry an attached entity via [entityType] / [entityId]: that is
/// how a collection or item is shared into the X-style feed.
class PostModel {
  /// Creates a post.
  const PostModel({
    required this.id,
    this.authorId,
    this.body,
    this.kind = PostKind.post,
    this.entityType,
    this.entityId,
    this.visibility,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.commentCount = 0,
    this.replyCount = 0,
    this.viewCount = 0,
    this.hiddenAt,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
    this.author,
  });

  /// Parses a `posts` row.
  factory PostModel.fromJson(Map<String, dynamic> json) {
    final author = asMap(json['author'] ?? json['profiles']);
    return PostModel(
      id: asString(json['id']),
      authorId: asStringOrNull(json['author_id']),
      body: asStringOrNull(json['body']),
      kind: PostKind.parse(json['kind']),
      entityType: EntityType.tryParse(json['entity_type']),
      entityId: asStringOrNull(json['entity_id']),
      visibility: EntityVisibility.tryParse(json['visibility']),
      likeCount: asInt(json['like_count']),
      saveCount: asInt(json['save_count']),
      repostCount: asInt(json['repost_count']),
      commentCount: asInt(json['comment_count']),
      replyCount: asInt(json['reply_count']),
      viewCount: asInt(json['view_count']),
      hiddenAt: asDateOrNull(json['hidden_at']),
      deletedAt: asDateOrNull(json['deleted_at']),
      createdAt: asDateOrNull(json['created_at']),
      updatedAt: asDateOrNull(json['updated_at']),
      author: author.isEmpty ? null : Profile.fromJson(author),
    );
  }

  /// Primary key.
  final String id;

  /// Author's user id.
  final String? authorId;

  /// Post text.
  final String? body;

  /// Original / quote / reply.
  final PostKind kind;

  /// Type of the attached entity, if any.
  final EntityType? entityType;

  /// Id of the attached entity, if any.
  final String? entityId;

  /// Explicit visibility.
  final EntityVisibility? visibility;

  /// Trigger-maintained.
  final int likeCount;

  /// Trigger-maintained.
  final int saveCount;

  /// Trigger-maintained.
  final int repostCount;

  /// Trigger-maintained.
  final int commentCount;

  /// Trigger-maintained reply count.
  final int replyCount;

  /// Trigger-maintained.
  final int viewCount;

  /// Set by moderation.
  final DateTime? hiddenAt;

  /// Soft delete.
  final DateTime? deletedAt;

  /// Row creation time.
  final DateTime? createdAt;

  /// Last mutation time.
  final DateTime? updatedAt;

  /// Embedded author profile when the query joined it.
  final Profile? author;

  /// True when this post shares a collection / subcollection / item.
  bool get hasAttachment => entityType != null && entityId != null;
}

/// The server-embedded preview of a post's attached / quoted / reposted thing
/// — the `target` block of the 0018 pulse envelope.
///
/// Uniform keys across every entity type; `{type, id, unavailable: true}` when
/// the thing is not visible to the caller, so a repost of vanished content
/// renders as a tombstone instead of an empty card.
class PulseTarget {
  /// Creates a target payload.
  const PulseTarget({
    required this.id,
    this.type,
    this.unavailable = false,
    this.title,
    this.subtitle,
    this.body,
    this.kind,
    this.coverPath,
    this.coverBlurhash,
    this.coverWidth,
    this.coverHeight,
    this.childCount = 0,
    this.likeCount = 0,
    this.createdAt,
    this.author,
    this.parentType,
    this.parentId,
  });

  /// Parses the envelope's `target` block.
  factory PulseTarget.fromJson(Map<String, dynamic> json) {
    final author = asMap(json['author']);
    return PulseTarget(
      id: asString(json['id']),
      type: EntityType.tryParse(json['type']),
      unavailable: asBool(json['unavailable']),
      title: asStringOrNull(json['title']),
      subtitle: asStringOrNull(json['subtitle']),
      body: asStringOrNull(json['body']),
      kind: asStringOrNull(json['kind']),
      coverPath: asStringOrNull(json['cover_path']),
      coverBlurhash: asStringOrNull(json['cover_blurhash']),
      coverWidth: asIntOrNull(json['cover_width']),
      coverHeight: asIntOrNull(json['cover_height']),
      childCount: asInt(json['child_count']),
      likeCount: asInt(json['like_count']),
      createdAt: asDateOrNull(json['created_at']),
      author: author.isEmpty ? null : Profile.fromJson(author),
      parentType: EntityType.tryParse(json['parent_type']),
      parentId: asStringOrNull(json['parent_id']),
    );
  }

  /// The target's id.
  final String id;

  /// Which entity level the target is. Null when the wire value was foreign.
  final EntityType? type;

  /// True when the caller may not see the target — render a tombstone.
  final bool unavailable;

  /// Collection / shelf name or item title. Null for posts.
  final String? title;

  /// Description / brand line.
  final String? subtitle;

  /// Post body, when the target is a quoted post or comment.
  final String? body;

  /// The quoted post's own kind (`post` | `quote` | `reply`), when a post.
  final String? kind;

  /// Cover storage path — for a post, its first photo.
  final String? coverPath;

  /// Blurhash of the cover.
  final String? coverBlurhash;

  /// Intrinsic cover width, when recorded.
  final int? coverWidth;

  /// Intrinsic cover height, when recorded.
  final int? coverHeight;

  /// Children beneath the target (things, photos, replies).
  final int childCount;

  /// Live like count at envelope time.
  final int likeCount;

  /// When the target was created.
  final DateTime? createdAt;

  /// Who owns the target.
  final Profile? author;

  /// For a comment target (0021): which entity level the discussion lives
  /// under, so a reposted comment can deep-link to it.
  final EntityType? parentType;

  /// For a comment target: the id of the entity the comment sits on.
  final String? parentId;

  /// Cover aspect ratio, or null when unknown.
  double? get coverAspect {
    final w = coverWidth;
    final h = coverHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }
}
