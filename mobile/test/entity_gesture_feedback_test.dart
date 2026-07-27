import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/features/surf/widgets/entity_gesture_card.dart';

import 'support/recording_feedback_driver.dart';
import 'support/test_harness.dart';

void main() {
  const entity = EntityRef.item('item-1');

  testWidgets('single card tap is tactile but intentionally silent', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(driver),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    var opens = 0;
    await pumpKlect(
      tester,
      KEntityGestureCard(
        entity: entity,
        title: 'Camera',
        onOpen: () => opens++,
        child: const SizedBox(width: 200, height: 200),
      ),
      container: container,
    );

    await tester.tap(find.byType(KEntityGestureCard));
    await tester.pump();

    expect(opens, 1);
    expect(driver.haptics, <InteractionFeedbackHaptic>[
      InteractionFeedbackHaptic.selection,
    ]);
    expect(driver.sounds, isEmpty);
    await tester.pump(KMotion.doubleTapWindow);
  });

  testWidgets('double tap adds a matching immersive focus cue', (tester) async {
    final driver = RecordingFeedbackDriver();
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(driver),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    var opens = 0;
    var immersiveOpens = 0;
    await pumpKlect(
      tester,
      KEntityGestureCard(
        entity: entity,
        title: 'Camera',
        onOpen: () => opens++,
        onImmersive: () => immersiveOpens++,
        child: const SizedBox(width: 200, height: 200),
      ),
      container: container,
    );

    await tester.tap(find.byType(KEntityGestureCard));
    await tester.pump(KMotion.doubleTapWindow ~/ 2);
    await tester.tap(find.byType(KEntityGestureCard));
    await tester.pump();

    expect(opens, 1);
    expect(immersiveOpens, 1);
    expect(
      driver.haptics,
      containsAll(<InteractionFeedbackHaptic>[
        InteractionFeedbackHaptic.selection,
        InteractionFeedbackHaptic.light,
      ]),
    );
    expect(driver.sounds, contains(InteractionFeedbackSound.focus));
  });

  testWidgets('long press Peek uses the focus cue and medium haptic', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(driver),
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
      ],
    );
    await pumpKlect(
      tester,
      const KEntityGestureCard(
        entity: entity,
        title: 'Camera',
        child: SizedBox(width: 200, height: 200),
      ),
      container: container,
    );

    await tester.longPress(find.byType(KEntityGestureCard));
    await tester.pump();

    expect(driver.haptics, contains(InteractionFeedbackHaptic.medium));
    expect(driver.sounds, contains(InteractionFeedbackSound.focus));

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
  });
}
