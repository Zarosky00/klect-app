import 'enums.dart';
import 'json.dart';
import 'profile.dart';

/// A row of `public.comments`. Comments are themselves a likeable entity
/// (`entity_type = 'comment'`), which is why they carry [likeCount].
class CommentModel {
  /// Creates a comment.
  const CommentModel({
    required this.id,
    required this.body,
    required this.entityType,
    required this.entityId,
    this.authorId,
    this.parentId,
    this.depth = 0,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.replyCount = 0,
    this.editedAt,
    this.hiddenAt,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
    this.author,
    this.viewerLiked = false,
    this.viewerSaved = false,
    this.viewerReposted = false,
    this.isPending = false,
    this.failed = false,
  });

  /// Parses a `comments` row, optionally with an embedded `author` join.
  ///
  /// Also accepts a `get_post_thread` comment entry (0021), whose viewer
  /// state arrives nested as `viewer: {liked, saved, reposted}`.
  factory CommentModel.fromJson(Map<String, dynamic> json) {
    final author = asMap(json['author'] ?? json['profiles']);
    final viewer = asMap(json['viewer']);
    return CommentModel(
      id: asString(json['id']),
      body: asString(json['body']),
      entityType: EntityType.parse(json['entity_type']),
      entityId: asString(json['entity_id']),
      authorId: asStringOrNull(json['author_id']),
      parentId: asStringOrNull(json['parent_id']),
      depth: asInt(json['depth']),
      likeCount: asInt(json['like_count']),
      saveCount: asInt(json['save_count']),
      repostCount: asInt(json['repost_count']),
      replyCount: asInt(json['reply_count']),
      editedAt: asDateOrNull(json['edited_at']),
      hiddenAt: asDateOrNull(json['hidden_at']),
      deletedAt: asDateOrNull(json['deleted_at']),
      createdAt: asDateOrNull(json['created_at']),
      updatedAt: asDateOrNull(json['updated_at']),
      author: author.isEmpty ? null : Profile.fromJson(author),
      viewerLiked: asBool(json['viewer_liked'] ?? viewer['liked']),
      viewerSaved: asBool(json['viewer_saved'] ?? viewer['saved']),
      viewerReposted: asBool(json['viewer_reposted'] ?? viewer['reposted']),
    );
  }

  /// Primary key. For an optimistic comment this is a client-side uuid until
  /// `add_comment` returns the real one.
  final String id;

  /// The comment text.
  final String body;

  /// What was commented on.
  final EntityType entityType;

  /// Which entity was commented on.
  final String entityId;

  /// Author's user id.
  final String? authorId;

  /// Parent comment, for threaded replies.
  final String? parentId;

  /// Thread depth, 0-based; the product allows replies to depth 3.
  final int depth;

  /// Trigger-maintained like count for this comment.
  final int likeCount;

  /// Trigger-maintained save count (0021 — comments are full social
  /// citizens).
  final int saveCount;

  /// Trigger-maintained repost count (0021).
  final int repostCount;

  /// Trigger-maintained reply count.
  final int replyCount;

  /// Set when edited.
  final DateTime? editedAt;

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

  /// Whether the viewer liked this comment.
  final bool viewerLiked;

  /// Whether the viewer saved this comment.
  final bool viewerSaved;

  /// Whether the viewer reposted this comment.
  final bool viewerReposted;

  /// Client-only: the comment is on screen but not yet acknowledged by the
  /// server. Render it at reduced opacity.
  final bool isPending;

  /// Client-only: the insert failed. The composer restores the draft rather
  /// than losing the text.
  final bool failed;

  /// Whether this comment is a reply.
  bool get isReply => parentId != null;

  /// Copy with overrides.
  CommentModel copyWith({
    String? id,
    String? body,
    int? likeCount,
    int? saveCount,
    int? repostCount,
    int? replyCount,
    bool? viewerLiked,
    bool? viewerSaved,
    bool? viewerReposted,
    bool? isPending,
    bool? failed,
    DateTime? createdAt,
    Profile? author,
  }) =>
      CommentModel(
        id: id ?? this.id,
        body: body ?? this.body,
        entityType: entityType,
        entityId: entityId,
        authorId: authorId,
        parentId: parentId,
        depth: depth,
        likeCount: likeCount ?? this.likeCount,
        saveCount: saveCount ?? this.saveCount,
        repostCount: repostCount ?? this.repostCount,
        replyCount: replyCount ?? this.replyCount,
        editedAt: editedAt,
        hiddenAt: hiddenAt,
        deletedAt: deletedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt,
        author: author ?? this.author,
        viewerLiked: viewerLiked ?? this.viewerLiked,
        viewerSaved: viewerSaved ?? this.viewerSaved,
        viewerReposted: viewerReposted ?? this.viewerReposted,
        isPending: isPending ?? this.isPending,
        failed: failed ?? this.failed,
      );
}
