import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../design/theme.dart';

/// The one notification taxonomy the client speaks.
///
/// Mirrors `public.notification_category(notification_type)` exactly: every
/// [NotificationType] lands in exactly one category, and anything unmapped —
/// including wire labels added to the enum later — is absorbed by
/// [NotificationCategory.system]. The banner glyph, the Alert Center row glyph,
/// the filter rail chip and the preference switches all read from here, so they
/// cannot drift apart.
enum NotificationCategory {
  /// `like`.
  likes('likes'),

  /// `save`.
  saves('saves'),

  /// `repost`.
  reposts('reposts'),

  /// `comment` and `reply`, which read as one stream.
  commentsAndReplies('comments_and_replies'),

  /// `mention`.
  mentions('mentions'),

  /// `follow`.
  follows('follows'),

  /// `message`.
  messages('messages'),

  /// `call`.
  calls('calls'),

  /// `recommendation`.
  recommendations('recommendations'),

  /// `match`.
  matches('matches'),

  /// `system`, plus every unmapped or unknown type.
  system('system');

  const NotificationCategory(this.wire);

  /// The label Postgres emits and the JSONB preference key.
  final String wire;

  /// Total over [NotificationType]: unmapped and unknown types land in
  /// [NotificationCategory.system], matching the SQL `else` branch.
  static NotificationCategory of(NotificationType type) => switch (type) {
        NotificationType.like => NotificationCategory.likes,
        NotificationType.save => NotificationCategory.saves,
        NotificationType.repost => NotificationCategory.reposts,
        NotificationType.comment ||
        NotificationType.reply =>
          NotificationCategory.commentsAndReplies,
        NotificationType.mention => NotificationCategory.mentions,
        NotificationType.follow => NotificationCategory.follows,
        NotificationType.message => NotificationCategory.messages,
        NotificationType.call => NotificationCategory.calls,
        NotificationType.recommendation => NotificationCategory.recommendations,
        NotificationType.match => NotificationCategory.matches,
        NotificationType.system => NotificationCategory.system,
      };

  /// Parses a wire label, defaulting to [NotificationCategory.system] so an
  /// unknown server label can never crash a rail or a preference read.
  static NotificationCategory parse(Object? value) {
    final label = value?.toString();
    for (final category in NotificationCategory.values) {
      if (category.wire == label) return category;
    }
    return NotificationCategory.system;
  }

  /// The action glyph and its tint, read from the Token_Set.
  ///
  /// Categories the Token_Set assigns no action colour fall back to
  /// [KlectColors.accentDefault] (Requirement 1.6).
  ({IconData glyph, Color tint}) style(KlectColors colors) => switch (this) {
        NotificationCategory.likes => (
            glyph: Icons.favorite_rounded,
            tint: colors.actionLike,
          ),
        NotificationCategory.saves => (
            glyph: Icons.bookmark_rounded,
            tint: colors.actionSave,
          ),
        NotificationCategory.reposts => (
            glyph: Icons.repeat_rounded,
            tint: colors.actionRepost,
          ),
        NotificationCategory.commentsAndReplies => (
            glyph: Icons.mode_comment_rounded,
            tint: colors.actionComment,
          ),
        NotificationCategory.mentions => (
            glyph: Icons.alternate_email_rounded,
            tint: colors.accentDefault,
          ),
        NotificationCategory.follows => (
            glyph: Icons.person_add_rounded,
            tint: colors.accentDefault,
          ),
        NotificationCategory.messages => (
            glyph: Icons.forum_rounded,
            tint: colors.actionComment,
          ),
        NotificationCategory.calls => (
            glyph: Icons.call_rounded,
            tint: colors.semanticInfo,
          ),
        NotificationCategory.recommendations => (
            glyph: Icons.explore_rounded,
            tint: colors.accentDefault,
          ),
        NotificationCategory.matches => (
            glyph: Icons.auto_awesome_rounded,
            tint: colors.matchHigh,
          ),
        NotificationCategory.system => (
            glyph: Icons.shield_moon_outlined,
            tint: colors.textSecondary,
          ),
      };

  /// Human copy for the filter rail chip and the empty-state sentence.
  String get label => switch (this) {
        NotificationCategory.likes => 'Likes',
        NotificationCategory.saves => 'Saves',
        NotificationCategory.reposts => 'Reposts',
        NotificationCategory.commentsAndReplies => 'Comments & replies',
        NotificationCategory.mentions => 'Mentions',
        NotificationCategory.follows => 'Follows',
        NotificationCategory.messages => 'Messages',
        NotificationCategory.calls => 'Calls',
        NotificationCategory.recommendations => 'Recommendations',
        NotificationCategory.matches => 'Taste matches',
        NotificationCategory.system => 'From KLECT',
      };
}
