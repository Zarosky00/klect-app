import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/api/klect_api.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/models/models.dart';
import 'package:klect/features/surf/data/closeup_providers.dart';
import 'package:klect/features/surf/widgets/entity_gesture_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/test_harness.dart';

void main() {
  const entity = EntityRef(EntityType.post, 'post-1');

  ProviderContainer containerWithPhotos(int count) {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    return ProviderContainer.test(
      overrides: [
        klectApiProvider.overrideWithValue(KlectApi(client)),
        postMediaProvider.overrideWith(
          (ref, id) async => <ImmersiveMedia>[
            for (var i = 0; i < count; i++)
              ImmersiveMedia(path: 'media/p$i.jpg', altText: 'Photo $i'),
          ],
        ),
      ],
    );
  }

  testWidgets('held finger scrubs the peek deck and the route keeps it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final container = containerWithPhotos(3);
    addTearDown(container.dispose);

    await pumpKlect(
      tester,
      const KEntityGestureCard(
        entity: entity,
        title: 'Set',
        peekGallery: true,
        child: SizedBox(width: 200, height: 200),
      ),
      container: container,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(KEntityGestureCard)),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel(RegExp('^Photo 1 of 3')), findsOneWidget);

    // Drag left without lifting: the deck follows the finger.
    var stamp = const Duration(seconds: 1);
    for (var i = 0; i < 10; i++) {
      stamp += const Duration(milliseconds: 16);
      await gesture.moveBy(const Offset(-15, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.bySemanticsLabel(RegExp('^Photo 2 of 3')), findsOneWidget);

    // Lift mid-flick: the route takes over and momentum carries one page on.
    await gesture.up(timeStamp: stamp + const Duration(milliseconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('Like'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Photo 3 of 3')), findsOneWidget);

    // After lifting, a regular swipe pages back.
    final swipe = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel(RegExp('^Photo 3 of 3'))),
    );
    stamp += const Duration(seconds: 1);
    for (var i = 0; i < 14; i++) {
      stamp += const Duration(milliseconds: 16);
      await swipe.moveBy(const Offset(15, 0), timeStamp: stamp);
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Rest the finger so the release carries no momentum.
    stamp += const Duration(milliseconds: 300);
    await swipe.moveBy(Offset.zero, timeStamp: stamp);
    await swipe.up(timeStamp: stamp);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Photo 2 of 3')), findsOneWidget);

    // The barrier still dismisses.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Like'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a plain long press without gallery still opens the peek', (
    tester,
  ) async {
    final container = containerWithPhotos(3);
    addTearDown(container.dispose);
    await pumpKlect(
      tester,
      const KEntityGestureCard(
        entity: entity,
        title: 'Set',
        child: SizedBox(width: 200, height: 200),
      ),
      container: container,
    );

    await tester.longPress(find.byType(KEntityGestureCard));
    await tester.pumpAndSettle();
    expect(find.text('Like'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'Photo \d of')), findsNothing);
  });
}
