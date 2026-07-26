import 'enums.dart';
import 'json.dart';
import 'profile.dart';

/// A row of `public.notifications`.
///
/// Repeats are deduped server-side by bumping [count] rather than inserting a
/// second row, so "12 people liked your collection" is one notification.
class NotificationModel {
  /// Creates a notification.
  const NotificationModel({
    required this.id,
    required this.type,
    this.userId,
    this.actorId,
    this.entityType,
    this.entityId,
    this.commentId,
    this.messageId,
    this.conversationId,
    this.body,
    this.count = 1,
    this.readAt,
    this.createdAt,
    this.actor,
  });

  /// Parses a `notifications` row, optionally with an embedded `actor` join.
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final actor = asMap(json['actor'] ?? json['profiles']);
    return NotificationModel(
      id: asString(json['id']),
      type: NotificationType.parse(json['type']),
      userId: asStringOrNull(json['user_id']),
      actorId: asStringOrNull(json['actor_id']),
      entityType: EntityType.tryParse(json['entity_type']),
      entityId: asStringOrNull(json['entity_id']),
      commentId: asStringOrNull(json['comment_id']),
      messageId: asStringOrNull(json['message_id']),
      conversationId: asStringOrNull(json['conversation_id']),
      body: asStringOrNull(json['body']),
      count: asInt(json['count'], 1),
      readAt: asDateOrNull(json['read_at']),
      createdAt: asDateOrNull(json['created_at']),
      actor: actor.isEmpty ? null : Profile.fromJson(actor),
    );
  }

  /// Primary key.
  final String id;

  /// What happened.
  final NotificationType type;

  /// Recipient.
  final String? userId;

  /// Who triggered it. Null for system notices.
  final String? actorId;

  /// Type of the entity involved.
  final EntityType? entityType;

  /// Id of the entity involved.
  final String? entityId;

  /// The comment involved, for comment/reply/mention.
  final String? commentId;

  /// The message involved, for message notifications.
  final String? messageId;

  /// The conversation involved, for message notifications.
  final String? conversationId;

  /// Preview text (comment body, message body, system copy).
  final String? body;

  /// How many times this was rolled up. 1 means a single event.
  final int count;

  /// Null while unread. `mark_notifications_read` sets it.
  final DateTime? readAt;

  /// Row creation time.
  final DateTime? createdAt;

  /// Embedded actor profile when the query joined it.
  final Profile? actor;

  /// Unread state, for the badge.
  bool get isUnread => readAt == null;

  /// True when this rolled several identical events together.
  bool get isGrouped => count > 1;

  /// Marks the model read locally, for optimistic badge clearing.
  NotificationModel markRead() => NotificationModel(
        id: id,
        type: type,
        userId: userId,
        actorId: actorId,
        entityType: entityType,
        entityId: entityId,
        commentId: commentId,
        messageId: messageId,
        conversationId: conversationId,
        body: body,
        count: count,
        readAt: readAt ?? DateTime.now(),
        createdAt: createdAt,
        actor: actor,
      );
}
