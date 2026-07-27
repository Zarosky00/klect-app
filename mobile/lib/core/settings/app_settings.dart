import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/key_value_store.dart';

/// User preferences that live on the device rather than in Postgres.
@immutable
class AppSettings {
  /// Creates a settings snapshot.
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.interactionSoundsEnabled = true,
    this.hapticsEnabled = true,
  });

  /// System-following by default, with a manual override.
  final ThemeMode themeMode;

  /// Whether quiet interaction confirmation sounds may play.
  final bool interactionSoundsEnabled;

  /// Whether selected interactions may use platform haptics.
  final bool hapticsEnabled;

  /// Copy with overrides.
  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? interactionSoundsEnabled,
    bool? hapticsEnabled,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    interactionSoundsEnabled:
        interactionSoundsEnabled ?? this.interactionSoundsEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.themeMode == themeMode &&
          other.interactionSoundsEnabled == interactionSoundsEnabled &&
          other.hapticsEnabled == hapticsEnabled;

  @override
  int get hashCode =>
      Object.hash(themeMode, interactionSoundsEnabled, hapticsEnabled);
}

/// Reads and writes [AppSettings] through the durable key/value store.
class AppSettingsController extends Notifier<AppSettings> {
  /// Storage key for the theme override.
  static const String themeModeKey = 'klect.settings.themeMode';

  /// Storage key for interaction sounds.
  static const String interactionSoundsKey = 'klect.settings.interactionSounds';

  /// Storage key for interaction haptics.
  static const String hapticsKey = 'klect.settings.haptics';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  AppSettings build() {
    return AppSettings(
      themeMode: _parseThemeMode(_store.getString(themeModeKey)),
      interactionSoundsEnabled: _parseEnabled(
        _store.getString(interactionSoundsKey),
      ),
      hapticsEnabled: _parseEnabled(_store.getString(hapticsKey)),
    );
  }

  /// Sets and persists the theme override.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _store.setString(themeModeKey, mode.name);
  }

  /// Enables or disables the bundled interaction cues.
  Future<void> setInteractionSoundsEnabled(bool enabled) async {
    state = state.copyWith(interactionSoundsEnabled: enabled);
    await _store.setString(interactionSoundsKey, '$enabled');
  }

  /// Enables or disables platform haptic feedback.
  Future<void> setHapticsEnabled(bool enabled) async {
    state = state.copyWith(hapticsEnabled: enabled);
    await _store.setString(hapticsKey, '$enabled');
  }

  static ThemeMode _parseThemeMode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static bool _parseEnabled(String? value) => value != 'false';
}

/// App-wide device preferences.
final appSettingsProvider =
    NotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
      name: 'appSettings',
    );

/// The theme mode `MaterialApp` should use.
final themeModeProvider = Provider<ThemeMode>(
  (ref) => ref.watch(appSettingsProvider).themeMode,
  name: 'themeMode',
);
