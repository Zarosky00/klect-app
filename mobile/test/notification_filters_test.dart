import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/features/notifications/notification_category.dart';
import 'package:klect/features/notifications/notification_filters.dart';
import 'package:klect/features/notifications/notification_preferences.dart';

NotificationModel row(
  String id,
  NotificationType type, {
  bool unread = false,
}) => NotificationModel(
  id: id,
  type: type,
  readAt: unread ? null : DateTime.utc(2026, 3, 1),
);

void main() {
  const enabled = NotificationPreferenceSet.allEnabled;

  final rows = <NotificationModel>[
    row('1', NotificationType.like, unread: true),
    row('2', NotificationType.message, unread: true),
    row('3', NotificationType.comment),
    row('4', NotificationType.like),
    row('5', NotificationType.reply, unread: true),
  ];

  List<String> ids(Iterable<NotificationModel> list) =>
      <String>[for (final entry in list) entry.id];

  group('filterNotifications', () {
    test('All keeps every row in the given order', () {
      expect(
        ids(filterNotifications(rows, null, enabled)),
        <String>['1', '2', '3', '4', '5'],
      );
    });

    test('a category keeps only its own rows, order preserved', () {
      expect(
        ids(filterNotifications(rows, NotificationCategory.likes, enabled)),
        <String>['1', '4'],
      );
      // `comment` and `reply` read as one category.
      expect(
        ids(
          filterNotifications(
            rows,
            NotificationCategory.commentsAndReplies,
            enabled,
          ),
        ),
        <String>['3', '5'],
      );
    });

    test('a single category is a subsequence of All', () {
      final all = ids(filterNotifications(rows, null, enabled));
      for (final category in NotificationCategory.values) {
        final single = ids(filterNotifications(rows, category, enabled));
        var cursor = 0;
        for (final id in single) {
          cursor = all.indexOf(id, cursor);
          expect(cursor, isNonNegative, reason: '$category broke the order');
          cursor += 1;
        }
      }
    });

    test('applying a selection twice equals applying it once', () {
      const selection = NotificationCategory.likes;
      final once = filterNotifications(rows, selection, enabled);
      expect(ids(filterNotifications(once, selection, enabled)), ids(once));
    });

    test('a suppressed category is removed under every selection', () {
      const muted = NotificationPreferenceSet(<NotificationCategory>{
        NotificationCategory.likes,
      });
      expect(
        ids(filterNotifications(rows, null, muted)),
        <String>['2', '3', '5'],
      );
      expect(
        filterNotifications(rows, NotificationCategory.likes, muted),
        isEmpty,
      );
    });

    test('an empty input yields an empty list', () {
      expect(
        filterNotifications(const <NotificationModel>[], null, enabled),
        isEmpty,
      );
    });
  });

  group('unreadCountsByCategory', () {
    test('counts unread rows per category and is total', () {
      final counts = unreadCountsByCategory(rows);
      expect(counts.length, NotificationCategory.values.length);
      expect(counts[NotificationCategory.likes], 1);
      expect(counts[NotificationCategory.messages], 1);
      expect(counts[NotificationCategory.commentsAndReplies], 1);
      expect(counts[NotificationCategory.calls], 0);
    });

    test('a read row never counts, whatever its roll-up count', () {
      final counts = unreadCountsByCategory(<NotificationModel>[
        const NotificationModel(
          id: 'r',
          type: NotificationType.like,
          count: 12,
        ).markRead(),
      ]);
      expect(counts[NotificationCategory.likes], 0);
    });

    test('a rolled-up unread row counts once', () {
      final counts = unreadCountsByCategory(<NotificationModel>[
        const NotificationModel(
          id: 'r',
          type: NotificationType.like,
          count: 12,
        ),
      ]);
      expect(counts[NotificationCategory.likes], 1);
    });
  });

  group('notificationCountLabel', () {
    test('renders nothing at zero or below', () {
      expect(notificationCountLabel(0), isNull);
      expect(notificationCountLabel(-3), isNull);
    });

    test('renders 1..99 as digits and above 99 as 99+', () {
      expect(notificationCountLabel(1), '1');
      expect(notificationCountLabel(99), '99');
      expect(notificationCountLabel(100), '99+');
      expect(notificationCountLabel(4821), '99+');
    });
  });
}
