import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/api/klect_api.dart';
import '../../core/links.dart';
import '../../core/models/models.dart';
import '../../design/theme.dart';
import '../../ui/ui.dart';
import '../profile/fill_viewport.dart';
import '../profile/profile_queries.dart';
import '../profile/user_actions.dart';
import '../settings/notification_settings_screen.dart';
import 'notification_preferences.dart';
import 'notifications_controller.dart';

/// Icon and colour for one notification type.
///
/// Every action colour is the semantic one: rose for likes, oxblood for saves,
/// mint for reposts, azure for conversation. Moderation and product notices
/// arrive as `system`.
({IconData icon, Color tint}) notificationStyle(
  KlectColors colors,
  NotificationType type,
) =>
    switch (type) {
      NotificationType.like => (
          icon: Icons.favorite_rounded,
          tint: colors.actionLike,
        ),
      NotificationType.save => (
          icon: Icons.bookmark_rounded,
          tint: colors.actionSave,
        ),
      NotificationType.repost => (
          icon: Icons.repeat_rounded,
          tint: colors.actionRepost,
        ),
      NotificationType.comment => (
          icon: Icons.mode_comment_rounded,
          tint: colors.actionComment,
        ),
      NotificationType.reply => (
          icon: Icons.reply_rounded,
          tint: colors.actionComment,
        ),
      NotificationType.mention => (
          icon: Icons.alternate_email_rounded,
          tint: colors.accentDefault,
        ),
      NotificationType.follow => (
          icon: Icons.person_add_rounded,
          tint: colors.accentDefault,
        ),
      NotificationType.message => (
          icon: Icons.forum_rounded,
          tint: colors.actionComment,
        ),
      NotificationType.call => (
          icon: Icons.call_rounded,
          tint: colors.semanticInfo,
        ),
      NotificationType.match => (
          icon: Icons.auto_awesome_rounded,
          tint: colors.matchHigh,
        ),
      NotificationType.system => (
          icon: Icons.shield_moon_outlined,
          tint: colors.textSecondary,
        ),
    };

/// Opens the per-type notification switches. Pushed rather than routed because
/// `lib/router.dart` is owned elsewhere and needs no change for this.
Future<void> openNotificationSettings(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (routeContext) => const NotificationSettingsScreen(),
      ),
    );

/// The Alerts tab.
///
/// Grouped by day, live over realtime, and every row routes to the thing it is
/// actually about. Reading a row marks it read and the tab badge follows.
class NotificationsScreen extends ConsumerWidget {
  /// Creates the screen.
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final notifications = ref.watch(notificationsProvider);
    final muted = ref.watch(notificationPreferencesProvider);
    final controller = ref.read(notificationsProvider.notifier);

    return KScaffold(
      appBar: KFixedAppBar(
        title: 'Alerts',
        actions: <Widget>[
          KIconButton(
            icon: Icons.tune_rounded,
            semanticLabel: 'Notification settings',
            onPressed: () => openNotificationSettings(context),
          ),
          KIconButton(
            icon: Icons.done_all_rounded,
            semanticLabel: 'Mark all as read',
            color: colors.textSecondary,
            onPressed: controller.markAllRead,
          ),
        ],
      ),
      onRefresh: controller.refresh,
      body: notifications.when(
        loading: () => const FillViewport(
          child: KSkeletonList(rows: 6, showMedia: false),
        ),
        error: (error, _) => FillViewport(
          child: KErrorState(
            error: error,
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
        ),
        data: (all) {
          final visible = <NotificationModel>[
            for (final entry in all)
              if (!muted.contains(entry.type)) entry,
          ];
          if (visible.isEmpty) {
            final nothingAtAll = all.isEmpty;
            return FillViewport(
              child: KEmptyState(
                title: nothingAtAll ? 'Nothing yet' : 'All muted',
                message: nothingAtAll
                    ? 'Likes, saves, reposts, comments and new followers land '
                        'here the moment they happen.'
                    : 'Every alert you have is a type you switched off.',
                icon: Icons.notifications_none_rounded,
                actionLabel:
                    nothingAtAll ? 'Go surfing' : 'Notification settings',
                onAction: () => nothingAtAll
                    ? context.go('/surf')
                    : openNotificationSettings(context),
              ),
            );
          }
          return _GroupedList(entries: visible);
        },
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.entries});

  final List<NotificationModel> entries;

  @override
  Widget build(BuildContext context) {
    // The server returns newest-first, so one pass produces the day sections
    // in order without sorting anything.
    final rows = <Widget>[];
    String? currentDay;
    for (final entry in entries) {
      final label = dayLabel(entry.createdAt);
      if (label != currentDay) {
        currentDay = label;
        rows.add(_DayHeader(label: label));
      }
      rows.add(NotificationRow(notification: entry));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Space.s20),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.s5,
          Space.s5,
          Space.s5,
          Space.s2,
        ),
        child: Text(
          label.toUpperCase(),
          style: context.kt.micro.copyWith(color: context.kc.textTertiary),
        ),
      );
}

/// One notification.
class NotificationRow extends ConsumerWidget {
  /// Creates a row.
  const NotificationRow({required this.notification, super.key});

  /// What happened.
  final NotificationModel notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.kc;
    final api = ref.watch(klectApiProvider);
    final style = notificationStyle(colors, notification.type);
    final actor = notification.actor;
    final preview = _preview();

    return KPressable(
      onTap: () => _open(context, ref),
      onLongPress: actor == null
          ? null
          : () => UserActions.showOverflow(context, profile: actor),
      enforceMinTapTarget: false,
      semanticLabel: _semanticLabel(),
      child: Container(
        color: notification.isUnread
            ? colors.accentSubtle
            : colors.bgBase.withValues(alpha: 0),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s5,
          vertical: Space.s3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                KAvatar(
                  imageUrl: avatarUrlOf(api, actor?.avatarPath),
                  name: actor?.name ?? 'KLECT',
                  size: Space.s12,
                ),
                Positioned(
                  right: -Space.s1,
                  bottom: -Space.s1,
                  child: Container(
                    padding: const EdgeInsets.all(Space.s1),
                    decoration: BoxDecoration(
                      color: colors.bgBase,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(style.icon, size: Space.s3, color: style.tint),
                  ),
                ),
              ],
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: _actorLabel(),
                          style: context.kt.bodyStrong,
                        ),
                        TextSpan(
                          text: ' ${_phrase()}',
                          style: context.kt.body
                              .copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (preview != null) ...<Widget>[
                    const SizedBox(height: Space.s1),
                    Text(
                      preview,
                      style: context.kt.callout
                          .copyWith(color: colors.textTertiary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: Space.s1),
                  Text(
                    notification.createdAt == null
                        ? ''
                        : timeago.format(
                            notification.createdAt!,
                            locale: 'en_short',
                          ),
                    style: context.kt.caption
                        .copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
            if (notification.isUnread)
              Container(
                margin: const EdgeInsets.only(top: Space.s2, left: Space.s2),
                width: Space.s2,
                height: Space.s2,
                decoration: BoxDecoration(
                  color: colors.accentDefault,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _actorLabel() {
    final actor = notification.actor;
    if (actor == null) return 'KLECT';
    if (notification.isGrouped) {
      final others = notification.count - 1;
      return '${actor.name} and $others other${others == 1 ? '' : 's'}';
    }
    return actor.name;
  }

  String _entityNoun() => switch (notification.entityType) {
        EntityType.collection => 'collection',
        EntityType.subcollection => 'subcollection',
        EntityType.item => 'item',
        EntityType.post => 'post',
        EntityType.comment => 'comment',
        null => 'work',
      };

  String _phrase() => switch (notification.type) {
        NotificationType.like => 'liked your ${_entityNoun()}',
        NotificationType.save => 'saved your ${_entityNoun()}',
        NotificationType.repost => 'reposted your ${_entityNoun()}',
        NotificationType.comment => 'commented on your ${_entityNoun()}',
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

  String? _preview() {
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

  String _semanticLabel() {
    final when = notification.createdAt == null
        ? ''
        : ', ${timeago.format(notification.createdAt!)}';
    final unread = notification.isUnread ? ', unread' : '';
    return '${_actorLabel()} ${_phrase()}$when$unread';
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    await ref.read(notificationsProvider.notifier).markRead(notification.id);
    if (!context.mounted) return;
    final destination = _destination();
    if (destination == null) return;
    await context.push(destination);
  }

  /// Where this notification points. Null means "nothing to open".
  String? _destination() => switch (notification.type) {
        NotificationType.message || NotificationType.call =>
          notification.conversationId == null
              ? null
              : '/messages/${notification.conversationId}',
        NotificationType.follow || NotificationType.match =>
          notification.actor == null
              ? null
              : KlectLinks.profilePath(notification.actor!.username),
        _ => _entityDestination(),
      };

  String? _entityDestination() {
    final type = notification.entityType;
    final id = notification.entityId;
    if (type == null || id == null) return null;
    // A comment lives inside the thing it is about; without the parent there is
    // nowhere sensible to land.
    if (type == EntityType.comment) return null;
    return KlectLinks.closeupPath(type, id);
  }
}

/// `Today` / `Yesterday` / weekday / `4 Jul` — four shapes, no `intl`.
String dayLabel(DateTime? moment) {
  if (moment == null) return 'Earlier';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(moment.year, moment.month, moment.day);
  final difference = today.difference(day).inDays;
  if (difference <= 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  if (difference < 7) return _weekdays[day.weekday - 1];
  if (day.year == today.year) return '${day.day} ${_months[day.month - 1]}';
  return '${day.day} ${_months[day.month - 1]} ${day.year}';
}

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
