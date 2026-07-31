/// Copy and routing shared by every surface a notification can appear on —
/// the Alerts row, the in-app banner and the system tray. One source of
/// truth, so "liked your collection" never drifts between surfaces.
library;

import 'package:flutter/foundation.dart';
// For `String.characters`: the banner text bound is counted in grapheme
// clusters. Nothing here builds or touches a widget.
import 'package:flutter/widgets.dart';

import '../../core/links.dart';
import '../../core/models/models.dart';
import 'notification_category.dart';

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
      NotificationType.recommendation =>
        'has a ${_entityNoun(notification)} for you',
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
// ── Banner composition ───────────────────────────────────────────────────────
//
// `bannerContentFor` is the whole of Requirement 3.1–3.6 and 3.12: a total,
// pure function from a `notifications` row to the copy, the thumbnail
// reference and the actions a banner should carry. It performs no I/O, takes no
// `BuildContext` and reads no colours — the presenter resolves the avatar, the
// thumbnail and the glyph tint from the category afterwards, and wires the
// action effects. Composition therefore stays testable without a widget tree.

/// Longest run of body or preview text a banner line carries, counted in
/// grapheme clusters so an emoji cluster is never split (Requirements 3.1, 3.6).
const int bannerBodyMaxChars = 140;

/// Actor copy used where no display name resolves (Requirement 3.12).
const String bannerActorPlaceholder = 'Someone';

/// Actor copy for a notice KLECT itself sent.
const String bannerSystemActor = 'KLECT';

const String _ellipsis = '…';

/// Ringing-call message line. Matches the tray copy in `push-fanout`.
const String _callPhrase = 'is calling you';

final RegExp _whitespaceRun = RegExp(r'\s+');

/// What a banner action does, so the presenter can attach exactly one effect
/// per action without re-reading the notification (Requirements 3.2, 3.3).
enum BannerActionKind {
  /// Follows the actor back, then confirms and leaves.
  followBack,

  /// Answers the ringing call and opens the Call_Screen.
  acceptCall,

  /// Declines the ringing call without navigating.
  declineCall,
}

/// One action a banner offers: what it says, what a screen reader says, and
/// which single effect it stands for.
@immutable
class BannerActionSpec {
  /// Creates an action spec.
  const BannerActionSpec({
    required this.kind,
    required this.label,
    required this.semanticLabel,
    this.confirmedLabel,
  });

  /// The effect this action stands for.
  final BannerActionKind kind;

  /// Rendered copy — "Follow back", "Accept", "Decline".
  final String label;

  /// What a screen reader announces.
  final String semanticLabel;

  /// Replaces [label] once the effect succeeds — "Following".
  final String? confirmedLabel;

  @override
  bool operator ==(Object other) =>
      other is BannerActionSpec &&
      other.kind == kind &&
      other.label == label &&
      other.semanticLabel == semanticLabel &&
      other.confirmedLabel == confirmedLabel;

  @override
  int get hashCode => Object.hash(kind, label, semanticLabel, confirmedLabel);
}

/// The entity whose cover thumbnail and blurhash the banner should show.
///
/// A reference, never a URL: resolving storage paths is the presenter's job and
/// is raced against the thumbnail budget (Requirements 1.3, 1.4).
@immutable
class BannerThumbRef {
  /// Creates a thumbnail reference.
  const BannerThumbRef(this.entityType, this.entityId);

  /// Which table the entity lives in. Never [EntityType.comment], which has no
  /// cover of its own.
  final EntityType entityType;

  /// The entity's primary key.
  final String entityId;

  @override
  bool operator ==(Object other) =>
      other is BannerThumbRef &&
      other.entityType == entityType &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(entityType, entityId);
}

/// The composed, render-ready content of one notification banner.
@immutable
class BannerContent {
  /// Creates banner content.
  const BannerContent({
    required this.category,
    required this.actorLabel,
    required this.title,
    required this.message,
    this.thumb,
    this.callId,
    this.destination,
    this.actions = const <BannerActionSpec>[],
  });

  /// The category the glyph and its tint are read from (Requirement 1.6).
  final NotificationCategory category;

  /// Who acted, already falling back to a placeholder (Requirement 3.12). Also
  /// the source of the avatar initials.
  final String actorLabel;

  /// The title line: one line, ellipsised by the banner beyond it.
  final String title;

  /// The message line: at most two lines, bounded at [bannerBodyMaxChars]
  /// clusters here and ellipsised by the banner beyond two lines.
  final String message;

  /// The entity whose cover belongs in the thumb slot, or null for none.
  final BannerThumbRef? thumb;

  /// The call this notification points at, for the accept/decline effects.
  final String? callId;

  /// Route the banner's tap should open. Null means "nothing to open", which
  /// the presenter turns into the Alert_Center (Requirement 3.13).
  final String? destination;

  /// Follow-back, or accept plus decline. Empty for every other category.
  final List<BannerActionSpec> actions;

  @override
  bool operator ==(Object other) =>
      other is BannerContent &&
      other.category == category &&
      other.actorLabel == actorLabel &&
      other.title == title &&
      other.message == message &&
      other.thumb == thumb &&
      other.callId == callId &&
      other.destination == destination &&
      listEquals(other.actions, actions);

  @override
  int get hashCode => Object.hash(
        category,
        actorLabel,
        title,
        message,
        thumb,
        callId,
        destination,
        Object.hashAll(actions),
      );
}

/// Composes the banner content for [notification].
///
/// Total over [NotificationType]: every type resolves to a titled, non-empty
/// message line. Wire labels the client does not know arrive here as
/// [NotificationType.system] (see `NotificationType.parse`) and take the
/// generic shape — default glyph, actor label, first [bannerBodyMaxChars]
/// characters of the body (Requirement 3.6).
BannerContent bannerContentFor(NotificationModel notification) {
  final actorLabel = bannerActorLabel(notification);
  final category = NotificationCategory.of(notification.type);
  final destination = notificationDestination(notification);
  final thumb = bannerThumbFor(notification);
  final body = truncateBannerText(notification.body);

  switch (notification.type) {
    // 3.1 — sender name as the title, the body as the message line, the
    // attachment label where the body is empty.
    case NotificationType.message:
      return BannerContent(
        category: category,
        actorLabel: actorLabel,
        title: actorLabel,
        message: body.isEmpty ? messageAttachmentLabel(notification) : body,
        thumb: thumb,
        destination: destination,
      );

    // 3.2 — follow phrase plus the follow-back action.
    case NotificationType.follow:
      return BannerContent(
        category: category,
        actorLabel: actorLabel,
        title: actorLabel,
        message: notificationPhrase(notification),
        thumb: thumb,
        destination: destination,
        actions: <BannerActionSpec>[_followBackAction(actorLabel)],
      );

    // 3.3 — accept and decline, but only where there is a call id to act on.
    // The presenter checks the row status is `ringing` before presenting.
    case NotificationType.call:
      final callId = bannerCallId(notification);
      return BannerContent(
        category: category,
        actorLabel: actorLabel,
        title: actorLabel,
        message: _callPhrase,
        callId: callId,
        destination: destination,
        actions: callId == null
            ? const <BannerActionSpec>[]
            : <BannerActionSpec>[
                _acceptCallAction(actorLabel),
                _declineCallAction(actorLabel),
              ],
      );

    // 3.4 — the recommended entity's cover, with the owner's name as the title.
    case NotificationType.recommendation:
      return BannerContent(
        category: category,
        actorLabel: actorLabel,
        title: actorLabel,
        message: body.isEmpty ? notificationPhrase(notification) : body,
        thumb: thumb,
        destination: destination,
      );

    // 3.5 — the shared glyph/actor/phrase shape, with the payload preview
    // appended where the text is the point of the notification.
    case NotificationType.like:
    case NotificationType.save:
    case NotificationType.repost:
    case NotificationType.comment:
    case NotificationType.reply:
    case NotificationType.mention:
    case NotificationType.match:
      final phrase = notificationPhrase(notification);
      final preview = truncateBannerText(notificationPreview(notification));
      return BannerContent(
        category: category,
        actorLabel: actorLabel,
        title: actorLabel,
        message:
            preview.isEmpty ? phrase : truncateBannerText('$phrase: $preview'),
        thumb: thumb,
        destination: destination,
      );

    // 3.5 for `system`, 3.6 for anything the client does not recognise: the
    // generic shape, which is the body where there is one and the system
    // phrase where there is not.
    case NotificationType.system:
      return BannerContent(
        category: category,
        actorLabel: actorLabel,
        title: actorLabel,
        message: body.isEmpty ? notificationPhrase(notification) : body,
        thumb: thumb,
        destination: destination,
      );
  }
}

/// The banner's actor label: the display name, the grouped form where the row
/// rolled several events together, or a placeholder where no name resolves
/// (Requirement 3.12).
String bannerActorLabel(NotificationModel notification) {
  final name = _collapse(notification.actor?.name);
  if (name.isEmpty) {
    return notification.type == NotificationType.system
        ? bannerSystemActor
        : bannerActorPlaceholder;
  }
  if (!notification.isGrouped) return truncateBannerText(name);
  final others = notification.count - 1;
  return truncateBannerText(
    '$name and $others other${others == 1 ? '' : 's'}',
  );
}

/// The message line standing in for an empty message body (Requirement 3.1).
///
/// A shared collection/subcollection/item/post names itself; otherwise the only
/// attachment kind chat carries is an image ([MessageKind.image]).
String messageAttachmentLabel(NotificationModel notification) {
  final type = notification.entityType;
  if (type != null && type != EntityType.comment) {
    return 'Shared a ${_entityNoun(notification)}';
  }
  return 'Sent a photo';
}

/// The call a `call` notification points at, or null where the row carries no
/// usable id. Mirrors `callIdFor` in the `push-fanout` edge function: the id
/// rides on `entity_id`, whose `entity_type` (`call`) is outside
/// [EntityType], so it parses to null.
String? bannerCallId(NotificationModel notification) {
  if (notification.type != NotificationType.call) return null;
  if (notification.entityType != null) return null;
  return notification.entityId;
}

/// The entity whose cover the banner should show, or null where there is none
/// to show. Comments have no cover of their own (Requirement 1.3).
BannerThumbRef? bannerThumbFor(NotificationModel notification) {
  final type = notification.entityType;
  final id = notification.entityId;
  if (type == null || id == null || type == EntityType.comment) return null;
  return BannerThumbRef(type, id);
}

/// Collapses whitespace in [text] and bounds it to [maxChars] grapheme
/// clusters, ending in a single ellipsis where it had to cut.
///
/// Grapheme clusters rather than code units, so an emoji or a combining mark is
/// never split in half. Null and whitespace-only input yield an empty string,
/// which is what lets an empty message body fall through to its attachment
/// label.
String truncateBannerText(String? text, {int maxChars = bannerBodyMaxChars}) {
  final collapsed = _collapse(text);
  if (collapsed.isEmpty) return '';
  final clusters = collapsed.characters;
  if (clusters.length <= maxChars) return collapsed;
  if (maxChars <= 1) return _ellipsis;
  return '${clusters.take(maxChars - 1)}$_ellipsis';
}

BannerActionSpec _followBackAction(String actorLabel) => BannerActionSpec(
      kind: BannerActionKind.followBack,
      label: 'Follow back',
      semanticLabel: 'Follow $actorLabel back',
      confirmedLabel: 'Following',
    );

BannerActionSpec _acceptCallAction(String actorLabel) => BannerActionSpec(
      kind: BannerActionKind.acceptCall,
      label: 'Accept',
      semanticLabel: 'Answer the call from $actorLabel',
    );

BannerActionSpec _declineCallAction(String actorLabel) => BannerActionSpec(
      kind: BannerActionKind.declineCall,
      label: 'Decline',
      semanticLabel: 'Decline the call from $actorLabel',
    );

String _collapse(String? text) =>
    text == null ? '' : text.replaceAll(_whitespaceRun, ' ').trim();
