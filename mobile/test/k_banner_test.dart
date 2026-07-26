import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/ui/k_banner.dart';

import 'support/test_harness.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    VoidCallback? onTap,
  }) async {
    await pumpKlect(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => KBanner.show(
            context,
            title: 'aria',
            message: 'liked your item',
            icon: Icons.favorite_rounded,
            onTap: onTap,
          ),
          child: const Text('fire'),
        ),
      ),
    );
    await tester.tap(find.text('fire'));
    await tester.pump();
    await tester.pump(KDurations.medium);
  }

  testWidgets('shows actor, verb and dismisses via the ✕', (tester) async {
    await pumpHost(tester);
    expect(find.text('aria'), findsOneWidget);
    expect(find.text('liked your item'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    // Exit motion, then the entry is removed.
    await tester.pump(KDurations.fast);
    await tester.pumpAndSettle();
    expect(find.text('aria'), findsNothing);
  });

  testWidgets('tap deep-links and removes the banner', (tester) async {
    var opened = false;
    await pumpHost(tester, onTap: () => opened = true);

    await tester.tap(find.text('liked your item'));
    await tester.pump();
    expect(opened, isTrue);
    expect(find.text('aria'), findsNothing);
  });

  testWidgets('auto-dismisses after the dwell', (tester) async {
    await pumpHost(tester);
    expect(find.text('aria'), findsOneWidget);

    await tester.pump(KBanner.dwell);
    await tester.pump(KDurations.fast);
    await tester.pumpAndSettle();
    expect(find.text('aria'), findsNothing);
  });
}
