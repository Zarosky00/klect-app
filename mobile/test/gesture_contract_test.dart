import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/ui/ui.dart';

import 'support/test_harness.dart';

void main() {
  setUpAll(useOfflineFonts);

  group('KGestureRegion', () {
    testWidgets('a single tap fires immediately — no double-tap penalty',
        (tester) async {
      var taps = 0;
      var doubles = 0;

      await pumpKlect(
        tester,
        KGestureRegion(
          onTap: () => taps++,
          onDoubleTap: () => doubles++,
          child: const SizedBox(width: 200, height: 200),
        ),
      );

      await tester.tap(find.byType(KGestureRegion));
      // No pump beyond the tap: the callback must already have run.
      expect(taps, 1);
      expect(doubles, 0);

      // Let the window elapse so the pending timer does not leak.
      await tester.pump(KMotion.doubleTapWindow);
      await tester.pump();
    });

    testWidgets('a second tap inside the window escalates', (tester) async {
      var taps = 0;
      var doubles = 0;
      var settled = 0;

      await pumpKlect(
        tester,
        KGestureRegion(
          onTap: () => taps++,
          onDoubleTap: () => doubles++,
          onTapSettled: () => settled++,
          child: const SizedBox(width: 200, height: 200),
        ),
      );

      await tester.tap(find.byType(KGestureRegion));
      await tester.pump(KMotion.doubleTapWindow ~/ 2);
      await tester.tap(find.byType(KGestureRegion));

      expect(taps, 1, reason: 'the second tap escalates, it does not re-tap');
      expect(doubles, 1);

      await tester.pump(KMotion.doubleTapWindow);
      expect(settled, 0, reason: 'the escalation cancelled the settle timer');
    });

    testWidgets('a lone tap settles once the window elapses', (tester) async {
      var settled = 0;

      await pumpKlect(
        tester,
        KGestureRegion(
          onTap: () {},
          onTapSettled: () => settled++,
          child: const SizedBox(width: 200, height: 200),
        ),
      );

      await tester.tap(find.byType(KGestureRegion));
      expect(settled, 0);

      await tester.pump(KMotion.doubleTapWindow);
      await tester.pump();
      expect(settled, 1);
    });

    testWidgets('a long press opens the peek and cancels the tap window',
        (tester) async {
      var peeks = 0;
      var settled = 0;

      await pumpKlect(
        tester,
        KGestureRegion(
          onTap: () {},
          onLongPress: () => peeks++,
          onTapSettled: () => settled++,
          child: const SizedBox(width: 200, height: 200),
        ),
      );

      await tester.longPress(find.byType(KGestureRegion));
      await tester.pump(KMotion.doubleTapWindow);
      await tester.pump();

      expect(peeks, 1);
      expect(settled, 0);
    });
  });

  group('KPressable', () {
    testWidgets('reports a tap', (tester) async {
      var taps = 0;
      await pumpKlect(
        tester,
        KPressable(
          onTap: () => taps++,
          child: const SizedBox(width: 120, height: 60),
        ),
      );
      await tester.tap(find.byType(KPressable));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('honours reduced motion by dropping the scale travel',
        (tester) async {
      await pumpKlect(
        tester,
        KPressable(
          onTap: () {},
          child: const SizedBox(width: 120, height: 60),
        ),
        disableAnimations: true,
      );

      expect(find.byType(AnimatedOpacity), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(KPressable),
          matching: find.byType(Transform),
        ),
        findsNothing,
      );
    });
  });
}
