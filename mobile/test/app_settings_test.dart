import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/settings/app_settings.dart';
import 'package:klect/core/storage/key_value_store.dart';

void main() {
  test(
    'sound defaults on while haptics default off and persist independently',
    () async {
      final store = MemoryKeyValueStore();
      final container = ProviderContainer.test(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      final controller = container.read(appSettingsProvider.notifier);

      expect(
        container.read(appSettingsProvider).interactionSoundsEnabled,
        isTrue,
      );
      expect(container.read(appSettingsProvider).hapticsEnabled, isFalse);

      await controller.setInteractionSoundsEnabled(false);
      await controller.setHapticsEnabled(true);
      await controller.setThemeMode(ThemeMode.light);

      expect(
        store.getString(AppSettingsController.interactionSoundsKey),
        'false',
      );
      expect(store.getString(AppSettingsController.hapticsKey), 'true');
      expect(store.getString(AppSettingsController.themeModeKey), 'light');

      final restored = ProviderContainer.test(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      ).read(appSettingsProvider);
      expect(restored.interactionSoundsEnabled, isFalse);
      expect(restored.hapticsEnabled, isTrue);
      expect(restored.themeMode, ThemeMode.light);
    },
  );

  test('explicit persisted false values are not replaced by defaults', () {
    final store = MemoryKeyValueStore(<String, String>{
      AppSettingsController.interactionSoundsKey: 'false',
      AppSettingsController.hapticsKey: 'false',
    });
    final settings = ProviderContainer.test(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    ).read(appSettingsProvider);

    expect(settings.interactionSoundsEnabled, isFalse);
    expect(settings.hapticsEnabled, isFalse);
  });
}
