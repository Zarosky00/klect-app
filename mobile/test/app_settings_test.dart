import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klect/core/settings/app_settings.dart';
import 'package:klect/core/storage/key_value_store.dart';

void main() {
  test(
    'sound and haptic preferences default on and persist independently',
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
      expect(container.read(appSettingsProvider).hapticsEnabled, isTrue);

      await controller.setInteractionSoundsEnabled(false);
      await controller.setHapticsEnabled(false);
      await controller.setThemeMode(ThemeMode.light);

      expect(
        store.getString(AppSettingsController.interactionSoundsKey),
        'false',
      );
      expect(store.getString(AppSettingsController.hapticsKey), 'false');
      expect(store.getString(AppSettingsController.themeModeKey), 'light');

      final restored = ProviderContainer.test(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      ).read(appSettingsProvider);
      expect(restored.interactionSoundsEnabled, isFalse);
      expect(restored.hapticsEnabled, isFalse);
      expect(restored.themeMode, ThemeMode.light);
    },
  );
}
