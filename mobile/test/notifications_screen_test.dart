import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/design/tokens.g.dart';
import 'package:klect/features/notifications/notification_category.dart';
import 'package:klect/features/notifications/notifications_screen.dart';
import 'package:klect/ui/ui.dart';

import 'support/test_harness.dart';

void main() {
  group('notificationFilterProvider', () {
    test('a fresh session starts at All', () {
      final container = ProviderContainer.test();
      expect(container.read(notificationFilterProvider), isNull);
    });

    test('holds the selection for the rest of the session', () {
      final container = ProviderContainer.test();
      container
          .read(notificationFilterProvider.notifier)
          .select(NotificationCategory.calls);
      // Reading it again is what reopening the Alert Center does (4.9).
      expect(
        container.read(notificationFilterProvider),
        NotificationCategory.calls,
      );

      container.read(notificationFilterProvider.notifier).select(null);
      expect(container.read(notificationFilterProvider), isNull);
    });
  });

  group('NotificationFilterRail', () {
    testWidgets('renders All plus the 11 categories with 44pt hit targets',
        (tester) async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      await pumpKlect(
        tester,
        const NotificationFilterRail(),
        container: container,
      );

      expect(find.byType(KChip), findsNWidgets(12));
      final labels = <String>[
        'All',
        for (final category in NotificationCategory.values) category.label,
      ];
      for (final label in labels) {
        final chip = find.text(label);
        expect(chip, findsOneWidget, reason: 'missing the $label chip');
        final target = find.ancestor(
          of: chip,
          matching: find.byType(KPressable),
        );
        final size = tester.getSize(target.first);
        expect(size.height, greaterThanOrEqualTo(Layout.tapTargetMin));
        expect(size.width, greaterThanOrEqualTo(Layout.tapTargetMin));
      }
    });

    testWidgets('a tap selects the category and moves the indicator',
        (tester) async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      await pumpKlect(
        tester,
        const NotificationFilterRail(),
        container: container,
      );

      final state = tester.state<NotificationFilterRailState>(
        find.byType(NotificationFilterRail),
      );
      final origin = state.indicatorRect;
      expect(origin, isNotNull);

      await tester.ensureVisible(find.text('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Messages'));
      await tester.pump();

      expect(
        container.read(notificationFilterProvider),
        NotificationCategory.messages,
      );
      expect(state.indicatorTravel.value, 0);

      await tester.pump(KDurations.deliberate);
      expect(state.indicatorTravel.value, 1);
      expect(state.indicatorRect!.left, isNot(origin!.left));
    });

    testWidgets('renders unread counts as tabular digits, capped at 99+',
        (tester) async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      await pumpKlect(
        tester,
        const NotificationFilterRail(
          unreadCounts: <NotificationCategory, int>{
            NotificationCategory.likes: 7,
            NotificationCategory.messages: 240,
            NotificationCategory.calls: 0,
          },
        ),
        container: container,
      );

      expect(find.text('7'), findsOneWidget);
      expect(find.text('240'), findsNothing);
      expect(find.text('99+'), findsOneWidget);
      // Zero and absent both render no badge at all.
      expect(find.text('0'), findsNothing);

      final digits = tester.widget<Text>(find.text('7'));
      expect(
        digits.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('re-activating the selected chip still animates',
        (tester) async {
      final container = ProviderContainer.test();
      addTearDown(container.dispose);
      await pumpKlect(
        tester,
        const NotificationFilterRail(),
        container: container,
      );

      final state = tester.state<NotificationFilterRailState>(
        find.byType(NotificationFilterRail),
      );
      expect(state.indicatorTravel.value, 1, reason: 'settled on first frame');

      // `All` is already selected, so the selection does not change — the
      // indicator must still confirm the tap (4.8).
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(state.indicatorTravel.value, 0);
      expect(container.read(notificationFilterProvider), isNull);

      await tester.pump(KDurations.deliberate);
      expect(state.indicatorTravel.value, 1);
    });
  });
}
