/// Copy and routing shared by every surface a notification can appear on —
/// the Alerts row, the in-app banner and the system tray. One source of
/// truth, so "liked your collection" never drifts between surfaces.
library;

import '../../core/links.dart';
import '../../core/models/models.dart';

/// The actor part of the sentence: `aria`, `aria and 3 others`, or `KLECT`
/// for system notices.
String notificationActorLabel(NotificationModel notification) {
  final actor = notification.actor;
  if (actor == null) return 'KLECT';
  if (notification.isGrouped) {
    final others = notification.count - 1;
    return '${actor.name} and $others other${others == 1 ? '' : 's'}';
  }
  return actor.name;
}

/// The verb phrase that follows the actor.
String notificationPhrase(NotificationModel notification) =>
    switch (notification.type) {
      NotificationType.like => 'liked your ${_entityNoun(notification)}',
      NotificationType.save => 'saved your ${_entityNoun(notification)}',
      NotificationType.repost => 'reposted your ${_entityNoun(notification)}',
      NotificationType.comment =>
        'commented on your ${_entityNoun(notification)}',
      NotificationType.reply => 'replied to your comment',
      NotificationType.mention => 'mentioned you',
      NotificationType.follow => 'started following you',
      NotificationType.message => 'sent you a message',
      NotificationType.call => 'called you',
      NotificationType.match => 'collects what you collect',
      NotificationType.system => notification.body == null
          ? 'has an update for you'
          : 'from the KLECT team',
    };

/// Body preview, only for the types where the payload text is the point.
String? notificationPreview(NotificationModel notification) {
  final body = notification.body;
  if (body == null || body.isEmpty) return null;
  return switch (notification.type) {
    NotificationType.comment ||
    NotificationType.reply ||
    NotificationType.mention ||
    NotificationType.message ||
    NotificationType.system =>
      body,
    _ => null,
  };
}

/// Where the notification points. Null means "nothing to open".
///
/// Follow/match destinations need the actor's username, so enrich
/// `notification.actor` first when you have only the realtime row.
String? notificationDestination(NotificationModel notification) =>
    switch (notification.type) {
      NotificationType.message || NotificationType.call =>
        notification.conversationId == null
            ? null
            : '/messages/${notification.conversationId}',
      NotificationType.follow || NotificationType.match =>
        notification.actor == null
            ? null
            : KlectLinks.profilePath(notification.actor!.username),
      _ => _entityDestination(notification),
    };

String? _entityDestination(NotificationModel notification) {
  final type = notification.entityType;
  final id = notification.entityId;
  if (type == null || id == null) return null;
  // A comment lives inside the thing it is about; without the parent there
  // is nowhere sensible to land.
  if (type == EntityType.comment) return null;
  return KlectLinks.closeupPath(type, id);
}

String _entityNoun(NotificationModel notification) =>
    switch (notification.entityType) {
      EntityType.collection => 'collection',
      EntityType.subcollection => 'subcollection',
      EntityType.item => 'item',
      EntityType.post => 'post',
      EntityType.comment => 'comment',
      null => 'work',
    };
