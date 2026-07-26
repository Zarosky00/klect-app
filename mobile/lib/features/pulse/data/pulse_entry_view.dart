import 'package:flutter/foundation.dart';

import '../../../core/interactions/interactions.dart';
import '../../../core/models/models.dart';

/// Which shape a Pulse row takes on screen.
enum PulseKind {
  /// An original post.
  post,

  /// Somebody you follow reposted something.
  repost,

  /// A repost carrying commentary.
  quote,

  /// A reply to another post.
  reply,
}

/// A Pulse row, normalised for rendering.
///
/// `pulse_feed` returns `jsonb[]`, and the exact envelope is the one part of
/// the backend contract that could not be verified from an anonymous session
/// (the RPC requires a JWT). This adapter therefore reads the *raw* payload and
/// accepts every plausible spelling of each field — `feed_kind` or `kind`,
/// `sort_at` or `created_at`, `target_type`/`target_id` or
/// `entity_type`/`entity_id` — so a shape mismatch degrades to a plainer card
/// instead of an empty feed.
@immutable
class PulseItem {
  /// Creates a normalised row.
  const PulseItem({
    required this.source,
    required this.kind,
    this.postId,
    this.targetType,
    this.targetId,
    this.author,
    this.reposter,
    this.body,
    this.quote,
    this.sortAt,
    this.media = const <ItemMedia>[],
    this.target,
    this.replyToPostId,
  });

  /// Normalises one entry of the stream.
  factory PulseItem.fromEntry(PulseEntry entry) {
    final raw = entry.raw;

    Map<String, dynamic> person(String key, String idKey) {
      final map = <String, dynamic>{...asMap(raw[key])};
      if (map.isEmpty) return map;
      if (asStringOrNull(map['id']) == null) {
        final id = asStringOrNull(raw[idKey]);
        if (id != null) map['id'] = id;
      }
      return map;
    }

    var authorMap = person('author', 'actor_id');
    if (authorMap.isEmpty) authorMap = person('owner', 'actor_id');
    var reposterMap = person('reposter', 'reposter_id');
    if (reposterMap.isEmpty) reposterMap = person('actor', 'reposter_id');

    final feedKind = asStringOrNull(raw['feed_kind']);
    // The 0018 envelope carries both: `feed_kind` (post | repost) and, for
    // post rows, the post's own `kind` (post | quote | reply).
    final postKind = asStringOrNull(raw['kind']);
    final quote = asStringOrNull(raw['quote_text'] ?? raw['quote']);

    final declaredType =
        EntityType.tryParse(raw['target_type'] ?? raw['entity_type']);
    final declaredId = asStringOrNull(raw['target_id'] ?? raw['entity_id']);

    final postId = asStringOrNull(raw['post_id']) ??
        (declaredType == EntityType.post && feedKind != 'repost'
            ? declaredId
            : null);
    final targetType = declaredType == EntityType.post ? null : declaredType;
    final targetId = declaredType == EntityType.post ? null : declaredId;

    final kind = switch (feedKind) {
      'repost' => quote == null ? PulseKind.repost : PulseKind.quote,
      'post' => switch (postKind) {
          'quote' => PulseKind.quote,
          'reply' => PulseKind.reply,
          _ => PulseKind.post,
        },
      'quote' => PulseKind.quote,
      'reply' => PulseKind.reply,
      _ => reposterMap.isEmpty
          ? PulseKind.post
          : (quote == null ? PulseKind.repost : PulseKind.quote),
    };

    return PulseItem(
      source: entry,
      kind: kind,
      postId: postId,
      targetType: targetType,
      targetId: targetId,
      author: authorMap.isEmpty ? null : Profile.fromJson(authorMap),
      reposter: reposterMap.isEmpty ? null : Profile.fromJson(reposterMap),
      body: asStringOrNull(raw['body']) ?? entry.body,
      quote: quote,
      sortAt: asDateOrNull(raw['sort_at']) ?? entry.createdAt,
      media: entry.media,
      target: entry.target,
      replyToPostId: asStringOrNull(raw['reply_to_post_id']),
    );
  }

  /// The untouched envelope, for anything this adapter does not name.
  final PulseEntry source;

  /// Which card shape to render.
  final PulseKind kind;

  /// The `posts` row this entry is built around, when there is one.
  final String? postId;

  /// The attached collection / subcollection / item, if any.
  final EntityType? targetType;

  /// Id of the attached entity.
  final String? targetId;

  /// Who made the underlying thing.
  final Profile? author;

  /// Who put it in your feed, when that is somebody else.
  final Profile? reposter;

  /// Post text.
  final String? body;

  /// Commentary attached to a repost.
  final String? quote;

  /// Cursor value — the oldest one on screen is the next `p_before`.
  final DateTime? sortAt;

  /// The post's own photos, from the envelope's `media[]`.
  final List<ItemMedia> media;

  /// Server-embedded preview of the attached / quoted / reposted thing.
  final PulseTarget? target;

  /// Parent post when this is a reply.
  final String? replyToPostId;

  /// The entity every social action on this card applies to.
  ///
  /// A post is its own likeable entity; a bare repost of a collection points
  /// at the collection itself, which is exactly the symmetry the product is
  /// built on.
  EntityRef get entity {
    final id = postId;
    if (id != null && id.isNotEmpty) return EntityRef.post(id);
    final type = targetType;
    final target = targetId;
    if (type != null && target != null && target.isNotEmpty) {
      return EntityRef(type, target);
    }
    return EntityRef(source.entityType, source.entityId);
  }

  /// The attached entity, when the card should render a preview of one.
  EntityRef? get attachment {
    final type = targetType;
    final id = targetId;
    if (type == null || id == null || id.isEmpty) return null;
    if (type == EntityType.post || type == EntityType.comment) return null;
    return EntityRef(type, id);
  }

  /// The text this card shows, whichever field carried it.
  String? get text {
    final commentary = quote;
    if (commentary != null && commentary.isNotEmpty) return commentary;
    final content = body;
    if (content != null && content.isNotEmpty) return content;
    return null;
  }

  /// Authoritative social state, ready to seed the optimistic engine.
  InteractionState get seed => InteractionState.fromPulse(source);

  /// Stable list key that survives pagination.
  String get key => '${kind.name}:${entity.key}:'
      '${sortAt?.microsecondsSinceEpoch ?? 0}';
}
