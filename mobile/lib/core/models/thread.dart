import 'comment.dart';
import 'json.dart';
import 'results.dart';

/// The counter block of `get_post_thread` — snapshots of the post's
/// trigger-maintained columns at fetch time. The screen seeds the optimistic
/// engine from the envelope, so these exist mostly for parity and debugging.
class PostThreadStats {
  /// Creates a stats block.
  const PostThreadStats({
    this.likeCount = 0,
    this.repostCount = 0,
    this.saveCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
  });

  /// Parses the `stats` block.
  factory PostThreadStats.fromJson(Map<String, dynamic> json) =>
      PostThreadStats(
        likeCount: asInt(json['like_count']),
        repostCount: asInt(json['repost_count']),
        saveCount: asInt(json['save_count']),
        commentCount: asInt(json['comment_count']),
        viewCount: asInt(json['view_count']),
      );

  /// Likes at fetch time.
  final int likeCount;

  /// Reposts at fetch time.
  final int repostCount;

  /// Saves at fetch time.
  final int saveCount;

  /// Comments at fetch time.
  final int commentCount;

  /// Views at fetch time.
  final int viewCount;
}

/// The `get_post_thread` payload (0021): the post's pulse envelope, a stats
/// snapshot, one page of comments with batched viewer state, and an explicit
/// `has_more` flag (the thread wraps its comments, so it does not use the
/// extra-row contract the flat feeds use).
class PostThread {
  /// Creates a thread payload.
  const PostThread({
    required this.post,
    required this.stats,
    this.comments = const <CommentModel>[],
    this.hasMore = false,
  });

  /// Parses the RPC payload. [postId] stamps `entity_type`/`entity_id` onto
  /// each comment map — the RPC omits them because they are implied by the
  /// call, but [CommentModel] carries them so one comment row renders the
  /// same everywhere.
  factory PostThread.fromJson(Map<String, dynamic> json, String postId) =>
      PostThread(
        post: PulseEntry.fromJson(asMap(json['post'])),
        stats: PostThreadStats.fromJson(asMap(json['stats'])),
        comments: <CommentModel>[
          for (final c in asMapList(json['comments']))
            CommentModel.fromJson(<String, dynamic>{
              ...c,
              'entity_type': 'post',
              'entity_id': postId,
            }),
        ],
        hasMore: asBool(json['has_more']),
      );

  /// The post itself, envelope-shaped exactly like a pulse row.
  final PulseEntry post;

  /// Counter snapshot.
  final PostThreadStats stats;

  /// One page of comments, already ordered by the requested sort.
  final List<CommentModel> comments;

  /// Whether another page of comments exists beyond this one.
  final bool hasMore;
}
