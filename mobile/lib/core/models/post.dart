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
