import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/settings/app_settings.dart';
import 'package:klect/core/storage/key_value_store.dart';

import 'support/recording_feedback_driver.dart';

void main() {
  const target = 'item:item-1';

  InteractionFeedbackEvent event({
    InteractionFeedbackAction action = InteractionFeedbackAction.like,
    InteractionFeedbackResult result = InteractionFeedbackResult.intent,
    bool? active = true,
    String id = 'event-1',
  }) => InteractionFeedbackEvent(
    id: id,
    action: action,
    result: result,
    targetKey: target,
    active: active,
  );

  group('feedback policy', () {
    const enabled = AppSettings();

    test('intent is tactile while confirmation is sonic', () {
      final intent = feedbackDirectiveFor(event(), enabled);
      expect(intent.haptic, InteractionFeedbackHaptic.light);
      expect(intent.sound, isNull);

      final confirmed = feedbackDirectiveFor(
        event(result: InteractionFeedbackResult.confirmed),
        enabled,
      );
      expect(confirmed.sound, InteractionFeedbackSound.like);
      expect(confirmed.haptic, isNull);
    });

    test('undo, local focus, queue and failure have distinct policy', () {
      expect(
        feedbackDirectiveFor(
          event(result: InteractionFeedbackResult.confirmed, active: false),
          enabled,
        ).sound,
        InteractionFeedbackSound.undo,
      );

      final immersive = feedbackDirectiveFor(
        event(
          action: InteractionFeedbackAction.immersiveOpen,
          result: InteractionFeedbackResult.confirmed,
          active: null,
        ),
        enabled,
      );
      expect(immersive.sound, InteractionFeedbackSound.focus);
      expect(immersive.haptic, InteractionFeedbackHaptic.light);

      expect(
        feedbackDirectiveFor(
          event(result: InteractionFeedbackResult.queued),
          enabled,
        ).isEmpty,
        isTrue,
      );

      final failed = feedbackDirectiveFor(
        event(result: InteractionFeedbackResult.failed),
        enabled,
      );
      expect(failed.sound, InteractionFeedbackSound.error);
      expect(failed.haptic, InteractionFeedbackHaptic.medium);
    });

    test('separate settings disable their respective channels', () {
      final soundOff = feedbackDirectiveFor(
        event(result: InteractionFeedbackResult.confirmed),
        const AppSettings(interactionSoundsEnabled: false),
      );
      expect(soundOff.sound, isNull);

      final hapticsOff = feedbackDirectiveFor(
        event(),
        const AppSettings(hapticsEnabled: false),
      );
      expect(hapticsOff.haptic, isNull);
    });
  });

  group('feedback controller', () {
    test(
      'begin and resolve share an id and produce one effect per phase',
      () async {
        final driver = RecordingFeedbackDriver();
        final container = ProviderContainer.test(
          overrides: [
            interactionFeedbackDriverProvider.overrideWithValue(driver),
            keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
          ],
        );
        final controller = container.read(interactionFeedbackProvider.notifier);

        final id = controller.begin(
          action: InteractionFeedbackAction.like,
          targetKey: target,
          active: true,
        );
        await Future<void>.delayed(Duration.zero);
        expect(driver.haptics, <InteractionFeedbackHaptic>[
          InteractionFeedbackHaptic.light,
        ]);
        expect(container.read(interactionFeedbackProvider)?.id, id);

        await controller.resolve(
          id: id,
          action: InteractionFeedbackAction.like,
          result: InteractionFeedbackResult.confirmed,
          targetKey: target,
          active: true,
        );
        expect(driver.sounds, <InteractionFeedbackSound>[
          InteractionFeedbackSound.like,
        ]);
        expect(
          container.read(interactionFeedbackProvider)?.result,
          InteractionFeedbackResult.confirmed,
        );
      },
    );

    test(
      'cooldown suppresses duplicate effects but still delivers the event',
      () async {
        final driver = RecordingFeedbackDriver();
        final container = ProviderContainer.test(
          overrides: [
            interactionFeedbackDriverProvider.overrideWithValue(driver),
            keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
          ],
        );
        final controller = container.read(interactionFeedbackProvider.notifier);

        await controller.dispatch(
          event(result: InteractionFeedbackResult.confirmed),
        );
        await controller.dispatch(
          event(result: InteractionFeedbackResult.confirmed, id: 'event-2'),
        );

        expect(driver.sounds, hasLength(1));
        expect(container.read(interactionFeedbackProvider)?.id, 'event-2');
      },
    );

    test('persisted opt-outs prevent platform effects', () async {
      final driver = RecordingFeedbackDriver();
      final container = ProviderContainer.test(
        overrides: [
          interactionFeedbackDriverProvider.overrideWithValue(driver),
          keyValueStoreProvider.overrideWithValue(
            MemoryKeyValueStore(<String, String>{
              AppSettingsController.interactionSoundsKey: 'false',
              AppSettingsController.hapticsKey: 'false',
            }),
          ),
        ],
      );

      await container
          .read(interactionFeedbackProvider.notifier)
          .dispatch(event(result: InteractionFeedbackResult.failed));

      expect(driver.sounds, isEmpty);
      expect(driver.haptics, isEmpty);
    });
  });
}
