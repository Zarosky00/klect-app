import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/interactions/interactions.dart';
import 'package:klect/core/settings/app_settings.dart';
import 'package:klect/core/storage/key_value_store.dart';
import 'package:klect/design/motion.dart';
import 'package:klect/features/surf/widgets/entity_gesture_card.dart';

import 'support/recording_feedback_driver.dart';
import 'support/test_harness.dart';

void main() {
  const entity = EntityRef.item('item-1');

  testWidgets('single card tap receives the native sound and haptic once', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(driver),
        keyValueStoreProvider.overrideWithValue(
          MemoryKeyValueStore(<String, String>{
            AppSettingsController.hapticsKey: 'true',
          }),
        ),
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
    expect(driver.taps, hasLength(1));
    expect(driver.taps.single.sound, isTrue);
    expect(driver.taps.single.haptic, isTrue);
    await tester.pump(KMotion.doubleTapWindow);
  });

  testWidgets('double tap produces one identical effect per accepted tap', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(driver),
        keyValueStoreProvider.overrideWithValue(
          MemoryKeyValueStore(<String, String>{
            AppSettingsController.hapticsKey: 'true',
          }),
        ),
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
    expect(driver.taps, hasLength(2));
    expect(driver.taps.every((tap) => tap.sound && tap.haptic), isTrue);
  });

  testWidgets('long press Peek uses the same native tap feedback', (
    tester,
  ) async {
    final driver = RecordingFeedbackDriver();
    final container = ProviderContainer.test(
      overrides: [
        interactionFeedbackDriverProvider.overrideWithValue(driver),
        keyValueStoreProvider.overrideWithValue(
          MemoryKeyValueStore(<String, String>{
            AppSettingsController.hapticsKey: 'true',
          }),
        ),
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

    expect(driver.taps, hasLength(1));
    expect(driver.taps.single.sound, isTrue);
    expect(driver.taps.single.haptic, isTrue);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
  });
}
