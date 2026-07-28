import 'comment.dart';
import 'enums.dart';
import 'json.dart';
import 'post.dart';
import 'profile.dart';
import 'results.dart';

/// The public Pulse slices available on a profile.
enum ProfilePulseView {
  all,
  originals,
  reposts,
  quotes,
  media;

  String get wire => name;
}

/// Which half of KLECT a discussion or private reaction belongs to.
enum ProfileSurface {
  all,
  surf,
  pulse;

  String get wire => name;
}

/// Owner-only profile activity type.
enum ProfileReactionAction {
  like,
  save;

  String get wire => name;
}

/// A tab in the public engagement viewer.
enum SocialEngagementTab {
  like('Likes'),
  repost('Reposts'),
  quote('Quotes');

  const SocialEngagementTab(this.label);

  final String label;
  String get wire => name;
}

Map<String, dynamic>? _cursor(Map<String, dynamic> json) {
  final value = asMap(json['next_cursor']);
  return value.isEmpty ? null : value;
}

/// One opaque-cursor page from `pulse_feed_v2` or profile Pulse activity.
class PulseEntryPage {
  const PulseEntryPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  factory PulseEntryPage.fromJson(Map<String, dynamic> json) => PulseEntryPage(
    items: <PulseEntry>[
      for (final row in asMapList(json['items'])) PulseEntry.fromJson(row),
    ],
    hasMore: asBool(json['has_more']),
    nextCursor: _cursor(json),
  );

  final List<PulseEntry> items;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
}

/// Authoritative totals displayed above the engagement tabs.
class EngagementSummary {
  const EngagementSummary({
    this.likeCount = 0,
    this.repostCount = 0,
    this.quoteCount = 0,
  });

  factory EngagementSummary.fromJson(Map<String, dynamic> json) =>
      EngagementSummary(
        likeCount: asInt(json['like_count'] ?? json['like']),
        repostCount: asInt(json['repost_count'] ?? json['repost']),
        quoteCount: asInt(json['quote_count'] ?? json['quote']),
      );

  final int likeCount;
  final int repostCount;
  final int quoteCount;

  @override
  bool operator ==(Object other) =>
      other is EngagementSummary &&
      other.likeCount == likeCount &&
      other.repostCount == repostCount &&
      other.quoteCount == quoteCount;

  @override
  int get hashCode => Object.hash(likeCount, repostCount, quoteCount);
}

/// A viewer-safe actor row or a quote card in an engagement page.
class SocialEngagementItem {
  const SocialEngagementItem({
    required this.kind,
    this.profile,
    this.entry,
    this.viewerFollows = false,
    this.actedAt,
  });

  factory SocialEngagementItem.fromJson(Map<String, dynamic> json) {
    final profile = asMap(json['user'] ?? json['profile']);
    final entry = asMap(json['entry'] ?? json['post']);
    return SocialEngagementItem(
      kind: asStringOrNull(json['kind']) ?? (entry.isEmpty ? 'actor' : 'quote'),
      profile: profile.isEmpty ? null : Profile.fromJson(profile),
      entry: entry.isEmpty ? null : PulseEntry.fromJson(entry),
      viewerFollows: asBool(json['viewer_follows']),
      actedAt: asDateOrNull(json['acted_at']),
    );
  }

  final String kind;
  final Profile? profile;
  final PulseEntry? entry;
  final bool viewerFollows;
  final DateTime? actedAt;

  bool get isQuote => entry != null || kind == 'quote';
}

/// `social_engagement_v1` response.
class SocialEngagementPage {
  const SocialEngagementPage({
    required this.summary,
    required this.items,
    required this.hasMore,
    this.nextCursor,
    this.unavailable = false,
  });

  factory SocialEngagementPage.fromJson(Map<String, dynamic> json) {
    final summary = asMap(json['summary']);
    final compatibilityCounts = asMap(json['counts']);
    final target = asMap(json['target']);
    return SocialEngagementPage(
      summary: EngagementSummary.fromJson(
        summary.isEmpty ? compatibilityCounts : summary,
      ),
      items: <SocialEngagementItem>[
        for (final row in asMapList(json['items']))
          SocialEngagementItem.fromJson(row),
      ],
      hasMore: asBool(json['has_more']),
      nextCursor: _cursor(json),
      unavailable: asBool(json['unavailable'] ?? target['unavailable']),
    );
  }

  final EngagementSummary summary;
  final List<SocialEngagementItem> items;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
  final bool unavailable;
}

/// Direct-parent context for a profile reply row.
class DiscussionReplyingTo {
  const DiscussionReplyingTo({
    this.id,
    this.authorId,
    this.username,
    this.body,
  });

  factory DiscussionReplyingTo.fromJson(Map<String, dynamic> json) =>
      DiscussionReplyingTo(
        id: asStringOrNull(json['id']),
        authorId: asStringOrNull(json['author_id']),
        username: asStringOrNull(json['username']),
        body: asStringOrNull(json['body']),
      );

  final String? id;
  final String? authorId;
  final String? username;
  final String? body;
}

/// Deep-link destination for one profile discussion row.
class DiscussionDestination {
  const DiscussionDestination({
    required this.type,
    required this.id,
    required this.highlightCommentId,
  });

  factory DiscussionDestination.fromJson(Map<String, dynamic> json) =>
      DiscussionDestination(
        type: EntityType.parse(json['type']),
        id: asString(json['id']),
        highlightCommentId: asString(
          json['highlight_comment_id'] ?? json['comment_id'],
        ),
      );

  final EntityType type;
  final String id;
  final String highlightCommentId;
}

/// An authored comment/reply with enough immutable context to understand it
/// away from the original thread.
class ProfileDiscussionActivity {
  const ProfileDiscussionActivity({
    required this.comment,
    required this.surface,
    required this.context,
    required this.destination,
    this.replyingTo,
  });

  factory ProfileDiscussionActivity.fromJson(Map<String, dynamic> json) {
    final nestedComment = asMap(json['comment']);
    final rawComment = nestedComment.isEmpty
        ? <String, dynamic>{...json}
        : <String, dynamic>{...nestedComment};
    final counts = asMap(rawComment['counts'] ?? json['counts']);
    final viewer = asMap(rawComment['viewer'] ?? json['viewer']);
    final destination = asMap(json['destination']);
    rawComment
      ..putIfAbsent('entity_type', () => destination['type'] ?? 'post')
      ..putIfAbsent('entity_id', () => destination['id'] ?? '')
      ..putIfAbsent('like_count', () => counts['like'])
      ..putIfAbsent('save_count', () => counts['save'])
      ..putIfAbsent('repost_count', () => counts['repost'])
      ..putIfAbsent('reply_count', () => counts['reply'])
      ..putIfAbsent('viewer_liked', () => viewer['liked'])
      ..putIfAbsent('viewer_saved', () => viewer['saved'])
      ..putIfAbsent('viewer_reposted', () => viewer['reposted']);

    final contextJson = asMap(json['context']);
    final targetJson = contextJson['target_type'] != null
        ? <String, dynamic>{
            'type': contextJson['target_type'],
            'id': contextJson['target_id'],
            ...contextJson,
          }
        : contextJson;
    final replyingTo = asMap(json['replying_to']);
    return ProfileDiscussionActivity(
      comment: CommentModel.fromJson(rawComment),
      surface: ProfileSurface.values.firstWhere(
        (value) => value.wire == asStringOrNull(json['surface']),
        orElse: () => ProfileSurface.pulse,
      ),
      context: PulseTarget.fromJson(targetJson),
      replyingTo: replyingTo.isEmpty
          ? null
          : DiscussionReplyingTo.fromJson(replyingTo),
      destination: DiscussionDestination.fromJson(destination),
    );
  }

  final CommentModel comment;
  final ProfileSurface surface;
  final PulseTarget context;
  final DiscussionReplyingTo? replyingTo;
  final DiscussionDestination destination;
}

/// `profile_discussion_activity_v1` response.
class ProfileDiscussionPage {
  const ProfileDiscussionPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  factory ProfileDiscussionPage.fromJson(Map<String, dynamic> json) =>
      ProfileDiscussionPage(
        items: <ProfileDiscussionActivity>[
          for (final row in asMapList(json['items']))
            ProfileDiscussionActivity.fromJson(row),
        ],
        hasMore: asBool(json['has_more']),
        nextCursor: _cursor(json),
      );

  final List<ProfileDiscussionActivity> items;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
}

/// One private like/save entry on the owner's Activity tab.
class ProfileReactionActivity {
  const ProfileReactionActivity({
    required this.targetType,
    required this.targetId,
    this.actedAt,
    this.entry,
    this.target,
  });

  factory ProfileReactionActivity.fromJson(Map<String, dynamic> json) {
    final entry = asMap(json['entry']);
    final target = asMap(json['target']);
    final parsedTarget = target.isEmpty ? null : PulseTarget.fromJson(target);
    return ProfileReactionActivity(
      targetType: EntityType.parse(
        json['target_type'] ?? parsedTarget?.type?.wire,
      ),
      targetId: asString(json['target_id'] ?? parsedTarget?.id),
      actedAt: asDateOrNull(json['acted_at']),
      entry: entry.isEmpty ? null : PulseEntry.fromJson(entry),
      target: parsedTarget,
    );
  }

  final EntityType targetType;
  final String targetId;
  final DateTime? actedAt;
  final PulseEntry? entry;
  final PulseTarget? target;
}

/// `my_profile_reactions_v1` response.
class ProfileReactionPage {
  const ProfileReactionPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  factory ProfileReactionPage.fromJson(Map<String, dynamic> json) =>
      ProfileReactionPage(
        items: <ProfileReactionActivity>[
          for (final row in asMapList(json['items']))
            ProfileReactionActivity.fromJson(row),
        ],
        hasMore: asBool(json['has_more']),
        nextCursor: _cursor(json),
      );

  final List<ProfileReactionActivity> items;
  final bool hasMore;
  final Map<String, dynamic>? nextCursor;
}
