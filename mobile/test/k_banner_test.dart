import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/design/tokens.g.dart';
import 'package:klect/ui/k_banner.dart';

import 'support/test_harness.dart';

void main() {
  NotificationBannerData data({
    VoidCallback? onTap,
    List<NotificationBannerAction> actions = const <NotificationBannerAction>[],
    String message = 'liked your item',
    bool compact = false,
  }) => NotificationBannerData(
    notificationId: 'n1',
    title: 'aria',
    message: message,
    glyph: Icons.favorite_rounded,
    glyphTint: const Color(0xFFA6323F),
    actions: actions,
    onTap: onTap,
    compact: compact,
  );

  Future<void> pumpHost(
    WidgetTester tester, {
    VoidCallback? onTap,
    List<NotificationBannerAction> actions = const <NotificationBannerAction>[],
    void Function(bool shown)? onShow,
    bool compact = false,
  }) async {
    await pumpKlect(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () {
            final shown = KNotificationBanner.show(
              context,
              data(onTap: onTap, actions: actions, compact: compact),
            );
            onShow?.call(shown);
          },
          child: const Text('fire'),
        ),
      ),
    );
    await tester.tap(find.text('fire'));
    // Settle the enter animation: the dwell is measured from its completion.
    await tester.pumpAndSettle();
  }

  tearDown(KNotificationBanner.debugClear);

  testWidgets('compact notice is minimal, two-line and has no close affordance', (
    tester,
  ) async {
    await pumpKlect(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => KNotificationBanner.show(
            context,
            data(
              compact: true,
              message:
                  'sent a deliberately long notification that must stay compact',
            ),
          ),
          child: const Text('fire compact'),
        ),
      ),
    );
    await tester.tap(find.text('fire compact'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close_rounded), findsNothing);
    expect(find.byIcon(Icons.favorite_rounded), findsNothing);
    final rich = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.textSpan != null,
      ),
    );
    expect(rich.maxLines, 2);
  });

  testWidgets('shows actor, verb and dismisses via the ✕', (tester) async {
    await pumpHost(tester);
    expect(find.text('aria'), findsOneWidget);
    expect(find.text('liked your item'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    // Exit motion, then the entry is removed.
    await tester.pump(KDurations.fast);
    await tester.pumpAndSettle();
    expect(find.text('aria'), findsNothing);
    expect(KNotificationBanner.isMounted, isFalse);
  });

  testWidgets('tap deep-links and removes the banner', (tester) async {
    var opened = false;
    await pumpHost(tester, onTap: () => opened = true);

    await tester.tap(find.text('liked your item'));
    await tester.pump();
    expect(opened, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('aria'), findsNothing);
  });

  testWidgets('auto-dismisses after the dwell', (tester) async {
    await pumpHost(tester);
    expect(find.text('aria'), findsOneWidget);

    await tester.pump(Dwell.banner);
    await tester.pump(KDurations.fast);
    await tester.pumpAndSettle();
    expect(find.text('aria'), findsNothing);
  });

  testWidgets('drops a second notification while one is mounted', (
    tester,
  ) async {
    final results = <bool>[];
    await pumpHost(tester, onShow: results.add);
    expect(results, <bool>[true]);

    await tester.tap(find.text('fire'));
    await tester.pump();
    expect(results, <bool>[true, false]);
    expect(find.text('aria'), findsOneWidget);

    await tester.pump(Dwell.banner);
    await tester.pumpAndSettle();
  });

  testWidgets('a long upward drag dismisses, a small one returns to rest', (
    tester,
  ) async {
    await pumpHost(tester);
    final centre = tester.getCenter(find.text('aria'));

    // Small, slow drag: below both thresholds, so the banner stays.
    final small = await tester.startGesture(centre);
    await small.moveBy(const Offset(0, -Space.s1));
    await tester.pump(KDurations.base);
    await small.up();
    await tester.pumpAndSettle();
    expect(find.text('aria'), findsOneWidget);

    // Slow but long enough to pass 40% of the measured card height.
    final long = await tester.startGesture(centre);
    for (var step = 0; step < 12; step++) {
      await long.moveBy(const Offset(0, -Space.s2));
      await tester.pump(KDurations.instant);
    }
    await long.up();
    await tester.pumpAndSettle();
    expect(find.text('aria'), findsNothing);
  });

  testWidgets('activating an action runs it and removes the banner', (
    tester,
  ) async {
    var followed = false;
    await pumpHost(
      tester,
      actions: <NotificationBannerAction>[
        NotificationBannerAction(
          label: 'Follow back',
          semanticLabel: 'Follow aria back',
          confirmedLabel: 'Following',
          onActivate: () async => followed = true,
        ),
      ],
    );
    expect(find.text('Follow back'), findsOneWidget);

    await tester.tap(find.text('Follow back'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(followed, isTrue);
    expect(find.text('aria'), findsNothing);
  });

  testWidgets('a card tap while an action is in flight does nothing', (
    tester,
  ) async {
    var opened = false;
    final running = Completer<void>();
    await pumpHost(
      tester,
      onTap: () => opened = true,
      actions: <NotificationBannerAction>[
        NotificationBannerAction(
          label: 'Accept',
          semanticLabel: 'Answer the call from aria',
          onActivate: () => running.future,
        ),
      ],
    );

    await tester.tap(find.text('Accept'));
    await tester.pump();
    // The effect has not finished, so the banner is still up — and its card tap
    // must not fire a second effect on top of it.
    await tester.tap(find.text('liked your item'));
    await tester.pump();
    expect(opened, isFalse);

    running.complete();
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    expect(find.text('aria'), findsNothing);
  });

  group('geometry and drag are pure derivations', () {
    test('card width clamps to the readable maximum minus gutters', () {
      expect(notificationBannerCardWidth(1400), Layout.readableMaxWidth);
      expect(notificationBannerCardWidth(360), 360 - Space.s3 * 2);
      expect(notificationBannerCardWidth(0), 0);
    });

    test('translation clamps to the token drag limit', () {
      expect(
        notificationBannerDragTranslation(<double>[-1000]),
        -Drags.bannerLimit,
      );
      expect(notificationBannerDragTranslation(<double>[-10, 40]), 0);
    });

    test('commit follows velocity or 40% of the measured height', () {
      expect(
        notificationBannerDragCommits(
          translation: 0,
          velocity: -Drags.flingVelocityMin,
          cardHeight: 80,
        ),
        isTrue,
      );
      expect(
        notificationBannerDragCommits(
          translation: -32,
          velocity: 0,
          cardHeight: 80,
        ),
        isTrue,
      );
      expect(
        notificationBannerDragCommits(
          translation: -31,
          velocity: 0,
          cardHeight: 80,
        ),
        isFalse,
      );
    });
  });
}
