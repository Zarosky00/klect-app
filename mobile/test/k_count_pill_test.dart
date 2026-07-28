import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/api/klect_api.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/design/theme.dart';
import 'package:klect/ui/ui.dart';

import 'support/fake_api.dart';
import 'support/recording_feedback_driver.dart';
import 'support/test_harness.dart';

void main() {
  setUpAll(useOfflineFonts);

  group('formatCount', () {
    test('is exact below a thousand', () {
      expect(formatCount(0), '0');
      expect(formatCount(7), '7');
      expect(formatCount(999), '999');
    });

    test('abbreviates thousands and millions', () {
      expect(formatCount(1000), '1.0K');
      expect(formatCount(1200), '1.2K');
      expect(formatCount(12000), '12K');
      expect(formatCount(1500000), '1.5M');
      expect(formatCount(23000000), '23M');
    });
  });

  group('KCountPill', () {
    testWidgets('keeps icon mutation and count navigation independent', (
      tester,
    ) async {
      var iconTaps = 0;
      var countTaps = 0;
      await pumpKlect(
        tester,
        KCountPill(
          icon: Icons.repeat_rounded,
          count: 12,
          iconSemanticLabel: 'Repost or quote',
          countSemanticLabel: '12 reposts, view activity',
          onIconTap: () => iconTaps++,
          onCountTap: () => countTaps++,
        ),
      );

      await tester.tap(find.byIcon(Icons.repeat_rounded));
      await tester.pump();
      expect(iconTaps, 1);
      expect(countTaps, 0);

      await tester.tap(find.text('1').first);
      await tester.pump();
      expect(iconTaps, 1);
      expect(countTaps, 1);
    });

    testWidgets('shows the seeded count', (tester) async {
      await pumpKlect(
        tester,
        const KCountPill(
          icon: Icons.favorite_border_rounded,
          count: 5,
          semanticLabel: 'Like, 5',
        ),
      );
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('rolls to the incremented value and drops the old digit', (
      tester,
    ) async {
      await pumpKlect(
        tester,
        const KCountPill(icon: Icons.favorite_border_rounded, count: 5),
      );
      expect(find.text('5'), findsOneWidget);

      await pumpKlect(
        tester,
        const KCountPill(icon: Icons.favorite_rounded, count: 6, active: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('6'), findsOneWidget);
      expect(find.text('5'), findsNothing);
    });

    testWidgets(
      'an optimistic like increments the pill before the RPC settles',
      (tester) async {
        const entity = EntityRef.item('item-1');
        final api = FakeKlectApi(likeCount: 5);
        final container = ProviderContainer.test(
          overrides: [
            klectApiProvider.overrideWithValue(api),
            interactionFeedbackDriverProvider.overrideWithValue(
              RecordingFeedbackDriver(),
            ),
            keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
          ],
        );
        container
            .read(interactionSeedStoreProvider)
            .put(entity, const InteractionState(likeCount: 5, hydrated: true));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: KlectThemeData.dark(),
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    final state = ref.watch(interactionProvider(entity));
                    return Center(
                      child: KCountPill(
                        icon: Icons.favorite_border_rounded,
                        activeIcon: Icons.favorite_rounded,
                        count: state.likeCount,
                        active: state.liked,
                        semanticLabel: 'Like',
                        onTap: ref
                            .read(interactionProvider(entity).notifier)
                            .toggleLike,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );

        expect(find.text('5'), findsOneWidget);

        await tester.tap(find.byType(KCountPill));
        // One frame — the RPC has not resolved yet.
        await tester.pump();
        expect(
          find.text('6'),
          findsOneWidget,
          reason: 'the delta lands on finger-lift, not on the response',
        );

        await tester.pumpAndSettle();
        expect(find.text('6'), findsOneWidget);
        expect(api.likeCalls, 1);
        expect(api.serverLikeCount, 6);
      },
    );

    testWidgets('an undone like rolls back down', (tester) async {
      await pumpKlect(
        tester,
        const KCountPill(icon: Icons.favorite_rounded, count: 10, active: true),
      );
      expect(find.text('1'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      await pumpKlect(
        tester,
        const KCountPill(icon: Icons.favorite_border_rounded, count: 9),
      );
      await tester.pumpAndSettle();

      expect(find.text('9'), findsOneWidget);
    });
  });
}
