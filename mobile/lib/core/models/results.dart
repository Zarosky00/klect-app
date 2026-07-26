import 'catalog.dart';
import 'enums.dart';
import 'json.dart';
import 'profile.dart';

/// The authoritative `{active, count}` every toggle RPC returns.
///
/// The optimistic engine overwrites its local state with this the moment it
/// arrives — which is why a double-fire or an offline replay cannot corrupt a
/// count.
class ToggleResult {
  /// Creates a toggle result.
  const ToggleResult({required this.active, required this.count});

  /// Parses `{active, count}`.
  factory ToggleResult.fromJson(Map<String, dynamic> json) => ToggleResult(
        active: asBool(json['active']),
        count: asInt(json['count']),
      );

  /// Whether the relationship now exists (liked / saved / reposted / follows).
  final bool active;

  /// The authoritative counter after the toggle.
  final int count;
}

/// What `add_comment` returns.
class CommentResult {
  /// Creates a comment result.
  const CommentResult({required this.id, required this.count});

  /// Parses `{id, count}`.
  factory CommentResult.fromJson(Map<String, dynamic> json) => CommentResult(
        id: asString(json['id']),
        count: asInt(json['count']),
      );

  /// The new comment's server id.
  final String id;

  /// The parent entity's new comment count.
  final int count;
}

/// What `submit_report` returns.
class ReportResult {
  /// Creates a report result.
  const ReportResult({required this.id, required this.alreadyReported});

  /// Parses `{id, already_reported}`.
  factory ReportResult.fromJson(Map<String, dynamic> json) => ReportResult(
        id: asString(json['id']),
        alreadyReported: asBool(json['already_reported']),
      );

  /// The report row id.
  final String id;

  /// True when this viewer had already reported the same target — surface
  /// "you already reported this", never an error.
  final bool alreadyReported;
}

/// A collection hit from `search_all`.
class CollectionSearchHit {
  /// Creates a hit.
  const CollectionSearchHit({
    required this.id,
    required this.name,
    this.slug,
    this.coverPath,
    this.coverBlurhash,
    this.itemCount = 0,
    this.likeCount = 0,
    this.username,
    this.displayName,
    this.avatarPath,
  });

  /// Parses a `collections` entry of `search_all`.
  factory CollectionSearchHit.fromJson(Map<String, dynamic> json) =>
      CollectionSearchHit(
        id: asString(json['id']),
        name: asString(json['name']),
        slug: asStringOrNull(json['slug']),
        coverPath: asStringOrNull(json['cover_path']),
        coverBlurhash: asStringOrNull(json['cover_blurhash']),
        itemCount: asInt(json['item_count']),
        likeCount: asInt(json['like_count']),
        username: asStringOrNull(json['username']),
        displayName: asStringOrNull(json['display_name']),
        avatarPath: asStringOrNull(json['avatar_path']),
      );

  /// Collection id.
  final String id;

  /// Collection name.
  final String name;

  /// URL slug.
  final String? slug;

  /// Cover storage path.
  final String? coverPath;

  /// Blurhash of the cover.
  final String? coverBlurhash;

  /// Items inside.
  final int itemCount;

  /// Live like count.
  final int likeCount;

  /// Owner handle.
  final String? username;

  /// Owner display name.
  final String? displayName;

  /// Owner avatar.
  final String? avatarPath;
}

/// An item hit from `search_all`.
class ItemSearchHit {
  /// Creates a hit.
  const ItemSearchHit({
    required this.id,
    required this.title,
    this.brand,
    this.coverPath,
    this.coverBlurhash,
    this.coverWidth,
    this.coverHeight,
    this.likeCount = 0,
    this.username,
    this.displayName,
    this.avatarPath,
  });

  /// Parses an `items` entry of `search_all`.
  factory ItemSearchHit.fromJson(Map<String, dynamic> json) => ItemSearchHit(
        id: asString(json['id']),
        title: asString(json['title']),
        brand: asStringOrNull(json['brand']),
        coverPath: asStringOrNull(json['cover_path']),
        coverBlurhash: asStringOrNull(json['cover_blurhash']),
        coverWidth: asIntOrNull(json['cover_width']),
        coverHeight: asIntOrNull(json['cover_height']),
        likeCount: asInt(json['like_count']),
        username: asStringOrNull(json['username']),
        displayName: asStringOrNull(json['display_name']),
        avatarPath: asStringOrNull(json['avatar_path']),
      );

  /// Item id.
  final String id;

  /// Item title.
  final String title;

  /// Maker.
  final String? brand;

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

  /// Owner handle.
  final String? username;

  /// Owner display name.
  final String? displayName;

  /// Owner avatar.
  final String? avatarPath;
}

/// The whole `search_all` payload: `{people, collections, items, tags}`.
class SearchResults {
  /// Creates a result set.
  const SearchResults({
    this.people = const <Profile>[],
    this.collections = const <CollectionSearchHit>[],
    this.items = const <ItemSearchHit>[],
    this.tags = const <TagModel>[],
  });

  /// Parses the `search_all` payload.
  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        people: <Profile>[
          for (final p in asMapList(json['people'])) Profile.fromJson(p),
        ],
        collections: <CollectionSearchHit>[
          for (final c in asMapList(json['collections']))
            CollectionSearchHit.fromJson(c),
        ],
        items: <ItemSearchHit>[
          for (final i in asMapList(json['items'])) ItemSearchHit.fromJson(i),
        ],
        tags: <TagModel>[
          for (final t in asMapList(json['tags'])) TagModel.fromJson(t),
        ],
      );

  /// Matching people.
  final List<Profile> people;

  /// Matching collections.
  final List<CollectionSearchHit> collections;

  /// Matching items.
  final List<ItemSearchHit> items;

  /// Matching tags.
  final List<TagModel> tags;

  /// True when nothing matched anywhere.
  bool get isEmpty =>
      people.isEmpty && collections.isEmpty && items.isEmpty && tags.isEmpty;

  /// Total hits across every bucket.
  int get total =>
      people.length + collections.length + items.length + tags.length;
}

/// One collector from `get_matches` — ranked by taste overlap.
class MatchModel {
  /// Creates a match.
  const MatchModel({
    required this.profile,
    this.score = 0,
    this.sharedTags = const <String>[],
    this.computedAt,
  });

  /// Parses a `get_matches` row. The RPC returns the profile fields flattened
  /// alongside `score` / `shared_tags`, so we hand the same map to
  /// [Profile.fromJson] and pick the match fields off the top level.
  factory MatchModel.fromJson(Map<String, dynamic> json) {
    final nested = asMap(json['profile'] ?? json['other'] ?? json['user']);
    return MatchModel(
      profile: Profile.fromJson(nested.isEmpty ? json : nested),
      score: asDouble(json['score']),
      sharedTags: asStringList(json['shared_tags']),
      computedAt: asDateOrNull(json['computed_at']),
    );
  }

  /// The matched collector.
  final Profile profile;

  /// Overlap score, 0..1.
  final double score;

  /// Tag slugs both accounts collect.
  final List<String> sharedTags;

  /// When the score was last recomputed.
  final DateTime? computedAt;

  /// Score as a whole percentage, for the badge.
  int get percent => (score <= 1 ? score * 100 : score).round().clamp(0, 100);
}

/// One entry of the Pulse stream.
///
/// `pulse_feed` returns `jsonb[]`, i.e. a heterogeneous stream of posts,
/// reposts and quotes. The typed fields below cover the shared envelope; the
/// untouched payload stays available on [raw] so a feature can read anything
/// the envelope does not name yet.
class PulseEntry {
  /// Creates a pulse entry.
  const PulseEntry({
    required this.raw,
    required this.entityType,
    required this.entityId,
    this.kind,
    this.actor,
    this.author,
    this.body,
    this.createdAt,
    this.likeCount = 0,
    this.saveCount = 0,
    this.repostCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.viewerLiked = false,
    this.viewerSaved = false,
    this.viewerReposted = false,
  });

  /// Parses one entry of the `pulse_feed` array.
  factory PulseEntry.fromJson(Map<String, dynamic> json) {
    final actor = asMap(json['actor'] ?? json['reposter']);
    final author = asMap(json['author'] ?? json['owner'] ?? json['profile']);
    final counts = asMap(json['counts']);
    int count(String key, String legacy) =>
        counts.isEmpty ? asInt(json[legacy]) : asInt(counts[key]);
    return PulseEntry(
      raw: json,
      entityType: EntityType.parse(json['entity_type']),
      entityId: asString(json['entity_id'] ?? json['id']),
      kind: asStringOrNull(json['kind']),
      actor: actor.isEmpty ? null : Profile.fromJson(actor),
      author: author.isEmpty ? null : Profile.fromJson(author),
      body: asStringOrNull(json['body'] ?? json['title']),
      createdAt: asDateOrNull(json['created_at']),
      likeCount: count('like', 'like_count'),
      saveCount: count('save', 'save_count'),
      repostCount: count('repost', 'repost_count'),
      commentCount: count('comment', 'comment_count'),
      viewCount: count('view', 'view_count'),
      viewerLiked: asBool(json['viewer_liked']),
      viewerSaved: asBool(json['viewer_saved']),
      viewerReposted: asBool(json['viewer_reposted']),
    );
  }

  /// The untouched jsonb payload.
  final Map<String, dynamic> raw;

  /// Which entity this entry is about.
  final EntityType entityType;

  /// The entity's id.
  final String entityId;

  /// `post` | `quote` | `reply` | `repost` — whatever the RPC labelled it.
  final String? kind;

  /// Who put this in your feed (the reposter, when different from the author).
  final Profile? actor;

  /// Who created the underlying entity.
  final Profile? author;

  /// Text body or title.
  final String? body;

  /// Ordering key — pass the oldest one back as `p_before` to paginate.
  final DateTime? createdAt;

  /// Live like count.
  final int likeCount;

  /// Live save count.
  final int saveCount;

  /// Live repost count.
  final int repostCount;

  /// Live comment count.
  final int commentCount;

  /// Live view count.
  final int viewCount;

  /// Viewer has liked it.
  final bool viewerLiked;

  /// Viewer has saved it.
  final bool viewerSaved;

  /// Viewer has reposted it.
  final bool viewerReposted;

  /// Stable list key.
  String get key => '${entityType.wire}:$entityId';
}
