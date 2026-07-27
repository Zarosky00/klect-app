import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/feedback/interaction_feedback.dart';
import 'package:klect/core/settings/app_settings.dart';
import 'package:klect/core/storage/key_value_store.dart';

import 'support/recording_feedback_driver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer harness(
    RecordingFeedbackDriver driver, {
    Map<String, String> stored = const <String, String>{},
  }) => ProviderContainer.test(
    overrides: [
      interactionFeedbackDriverProvider.overrideWithValue(driver),
      keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore(stored)),
    ],
  );

  group('native tap feedback', () {
    test('one accepted tap defaults to sound without haptic', () async {
      final driver = RecordingFeedbackDriver();
      final container = harness(driver);

      await container.read(interactionFeedbackProvider.notifier).tap();

      expect(driver.taps, hasLength(1));
      expect(driver.taps.single.sound, isTrue);
      expect(driver.taps.single.haptic, isFalse);
    });

    test('sound and haptic preferences remain independent', () async {
      final soundOff = RecordingFeedbackDriver();
      final soundOffContainer = harness(
        soundOff,
        stored: <String, String>{
          AppSettingsController.interactionSoundsKey: 'false',
          AppSettingsController.hapticsKey: 'true',
        },
      );
      await soundOffContainer.read(interactionFeedbackProvider.notifier).tap();
      expect(soundOff.taps.single.sound, isFalse);
      expect(soundOff.taps.single.haptic, isTrue);

      final hapticOff = RecordingFeedbackDriver();
      final hapticOffContainer = harness(
        hapticOff,
        stored: <String, String>{AppSettingsController.hapticsKey: 'false'},
      );
      await hapticOffContainer.read(interactionFeedbackProvider.notifier).tap();
      expect(hapticOff.taps.single.sound, isTrue);
      expect(hapticOff.taps.single.haptic, isFalse);
    });

    test('both preferences disabled skip the platform boundary', () async {
      final driver = RecordingFeedbackDriver();
      final container = harness(
        driver,
        stored: <String, String>{
          AppSettingsController.interactionSoundsKey: 'false',
          AppSettingsController.hapticsKey: 'false',
        },
      );

      await container.read(interactionFeedbackProvider.notifier).tap();

      expect(driver.taps, isEmpty);
    });

    test('rapid accepted taps are preserved instead of coalesced', () async {
      final driver = RecordingFeedbackDriver();
      final container = harness(driver);
      final controller = container.read(interactionFeedbackProvider.notifier);

      await Future.wait(<Future<void>>[
        for (var index = 0; index < 5; index++) controller.tap(),
      ]);

      expect(driver.taps, hasLength(5));
    });
  });

  group('social outcomes', () {
    test(
      'intent and resolution share an id but create no second effect',
      () async {
        final driver = RecordingFeedbackDriver();
        final container = harness(driver);
        final controller = container.read(interactionFeedbackProvider.notifier);

        await controller.tap();
        final id = controller.begin(
          action: InteractionFeedbackAction.follow,
          targetKey: 'collector-1',
          targetLabel: 'Akash',
          active: true,
        );
        await controller.resolve(
          id: id,
          action: InteractionFeedbackAction.follow,
          result: InteractionFeedbackResult.confirmed,
          targetKey: 'collector-1',
          targetLabel: 'Akash',
          active: true,
        );

        expect(driver.taps, hasLength(1));
        expect(container.read(interactionFeedbackProvider)?.id, id);
        expect(
          container.read(interactionFeedbackProvider)?.result,
          InteractionFeedbackResult.confirmed,
        );
      },
    );

    test('queued and failed resolutions are also platform-silent', () async {
      final driver = RecordingFeedbackDriver();
      final container = harness(driver);
      final controller = container.read(interactionFeedbackProvider.notifier);

      await controller.dispatch(
        const InteractionFeedbackEvent(
          id: 'queued',
          action: InteractionFeedbackAction.like,
          result: InteractionFeedbackResult.queued,
          targetKey: 'post:1',
          active: true,
        ),
      );
      await controller.dispatch(
        const InteractionFeedbackEvent(
          id: 'failed',
          action: InteractionFeedbackAction.save,
          result: InteractionFeedbackResult.failed,
          targetKey: 'post:1',
          active: true,
        ),
      );

      expect(driver.taps, isEmpty);
      expect(container.read(interactionFeedbackProvider)?.id, 'failed');
    });
  });

  group('platform driver', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('Android uses the system click and selection haptic', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      await const PlatformInteractionFeedbackDriver().tap(
        sound: true,
        haptic: true,
      );

      expect(
        calls.map((call) => call.method),
        containsAll(<String>['SystemSound.play', 'HapticFeedback.vibrate']),
      );
      expect(
        calls
            .where((call) => call.method == 'SystemSound.play')
            .single
            .arguments,
        'SystemSoundType.click',
      );
    });

    test('iOS follows native convention and omits a generic click', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await const PlatformInteractionFeedbackDriver().tap(
        sound: true,
        haptic: true,
      );

      expect(calls.where((call) => call.method == 'SystemSound.play'), isEmpty);
      expect(
        calls.where((call) => call.method == 'HapticFeedback.vibrate'),
        hasLength(1),
      );
    });
  });
}
