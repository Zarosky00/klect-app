import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/key_value_store.dart';

/// User preferences that live on the device rather than in Postgres.
@immutable
class AppSettings {
  /// Creates a settings snapshot.
  const AppSettings({this.themeMode = ThemeMode.system});

  /// System-following by default, with a manual override.
  final ThemeMode themeMode;

  /// Copy with overrides.
  AppSettings copyWith({ThemeMode? themeMode}) =>
      AppSettings(themeMode: themeMode ?? this.themeMode);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings && other.themeMode == themeMode;

  @override
  int get hashCode => themeMode.hashCode;
}

/// Reads and writes [AppSettings] through the durable key/value store.
class AppSettingsController extends Notifier<AppSettings> {
  /// Storage key for the theme override.
  static const String themeModeKey = 'klect.settings.themeMode';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  AppSettings build() {
    final stored = _store.getString(themeModeKey);
    return AppSettings(themeMode: _parseThemeMode(stored));
  }

  /// Sets and persists the theme override.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _store.setString(themeModeKey, mode.name);
  }

  static ThemeMode _parseThemeMode(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
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
