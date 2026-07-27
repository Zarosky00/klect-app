import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/klect_api.dart';
import '../models/models.dart';
import '../storage/key_value_store.dart';
import '../supabase.dart';

/// Bundled typography choices.
enum FontPack { editorial, modern, readable }

/// Feed density and spacing.
enum ContentDensity { compact, comfortable }

/// Motion preference layered on top of the operating-system setting.
enum MotionPreference { system, full, reduced }

/// Pulse card composition.
enum PulseLayoutPreference { balanced, mediaForward }

/// User preferences that live on the device rather than in Postgres.
@immutable
class AppSettings {
  /// Creates a settings snapshot.
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.interactionSoundsEnabled = true,
    this.hapticsEnabled = false,
    this.oled = false,
    this.fontPack = FontPack.editorial,
    this.textScale = 1,
    this.density = ContentDensity.comfortable,
    this.motion = MotionPreference.system,
    this.highContrast = false,
    this.pulseLayout = PulseLayoutPreference.mediaForward,
    this.dataSaver = false,
    this.autoplayMedia = true,
  });

  /// System-following by default, with a manual override.
  final ThemeMode themeMode;

  /// Whether the platform-native in-app tap sound may play.
  final bool interactionSoundsEnabled;

  /// Whether accepted in-app taps may use the light platform haptic.
  final bool hapticsEnabled;

  /// Uses true-black page backgrounds while dark mode is active.
  final bool oled;

  /// Bundled, offline-safe type family selection.
  final FontPack fontPack;

  /// App multiplier applied on top of the operating system's text scale.
  final double textScale;

  /// Compact or comfortable information density.
  final ContentDensity density;

  /// Motion override. System remains the default.
  final MotionPreference motion;

  /// Strengthens type and contrast without hiding semantic colours.
  final bool highContrast;

  /// Balanced or media-forward Pulse composition.
  final PulseLayoutPreference pulseLayout;

  /// Requests smaller media and avoids eager playback.
  final bool dataSaver;

  /// Whether eligible media may autoplay.
  final bool autoplayMedia;

  /// Copy with overrides.
  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? interactionSoundsEnabled,
    bool? hapticsEnabled,
    bool? oled,
    FontPack? fontPack,
    double? textScale,
    ContentDensity? density,
    MotionPreference? motion,
    bool? highContrast,
    PulseLayoutPreference? pulseLayout,
    bool? dataSaver,
    bool? autoplayMedia,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    interactionSoundsEnabled:
        interactionSoundsEnabled ?? this.interactionSoundsEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
    oled: oled ?? this.oled,
    fontPack: fontPack ?? this.fontPack,
    textScale: textScale ?? this.textScale,
    density: density ?? this.density,
    motion: motion ?? this.motion,
    highContrast: highContrast ?? this.highContrast,
    pulseLayout: pulseLayout ?? this.pulseLayout,
    dataSaver: dataSaver ?? this.dataSaver,
    autoplayMedia: autoplayMedia ?? this.autoplayMedia,
  );

  /// Versioned server payload stored in `user_preferences.appearance`.
  Map<String, dynamic> toAppearanceJson() => <String, dynamic>{
    'theme': oled ? 'oled' : themeMode.name,
    'font_pack': fontPack.name,
    'text_scale': textScale,
    'density': density.name,
    'motion': motion.name,
    'high_contrast': highContrast,
    'pulse_layout': pulseLayout == PulseLayoutPreference.mediaForward
        ? 'media_forward'
        : 'balanced',
    'data_saver': dataSaver,
    'autoplay_media': autoplayMedia,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.themeMode == themeMode &&
          other.interactionSoundsEnabled == interactionSoundsEnabled &&
          other.hapticsEnabled == hapticsEnabled &&
          other.oled == oled &&
          other.fontPack == fontPack &&
          other.textScale == textScale &&
          other.density == density &&
          other.motion == motion &&
          other.highContrast == highContrast &&
          other.pulseLayout == pulseLayout &&
          other.dataSaver == dataSaver &&
          other.autoplayMedia == autoplayMedia;

  @override
  int get hashCode => Object.hash(
    themeMode,
    interactionSoundsEnabled,
    hapticsEnabled,
    oled,
    fontPack,
    textScale,
    density,
    motion,
    highContrast,
    pulseLayout,
    dataSaver,
    autoplayMedia,
  );
}

/// Reads and writes [AppSettings] through the durable key/value store.
class AppSettingsController extends Notifier<AppSettings> {
  /// Storage key for the theme override.
  static const String themeModeKey = 'klect.settings.themeMode';

  /// Storage key for interaction sounds.
  static const String interactionSoundsKey = 'klect.settings.interactionSounds';

  /// Storage key for interaction haptics.
  static const String hapticsKey = 'klect.settings.haptics';
  static const String oledKey = 'klect.settings.oled';
  static const String fontPackKey = 'klect.settings.fontPack';
  static const String textScaleKey = 'klect.settings.textScale';
  static const String densityKey = 'klect.settings.density';
  static const String motionKey = 'klect.settings.motion';
  static const String highContrastKey = 'klect.settings.highContrast';
  static const String pulseLayoutKey = 'klect.settings.pulseLayout';
  static const String dataSaverKey = 'klect.settings.dataSaver';
  static const String autoplayKey = 'klect.settings.autoplay';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);
  String? _hydratedUser;

  @override
  AppSettings build() {
    final local = AppSettings(
      themeMode: _parseThemeMode(_store.getString(themeModeKey)),
      interactionSoundsEnabled: _parseEnabled(
        _store.getString(interactionSoundsKey),
        defaultValue: true,
      ),
      hapticsEnabled: _parseEnabled(
        _store.getString(hapticsKey),
        defaultValue: false,
      ),
      oled: _parseEnabled(_store.getString(oledKey), defaultValue: false),
      fontPack: _enumByName(
        FontPack.values,
        _store.getString(fontPackKey),
        FontPack.editorial,
      ),
      textScale: double.tryParse(_store.getString(textScaleKey) ?? '') ?? 1,
      density: _enumByName(
        ContentDensity.values,
        _store.getString(densityKey),
        ContentDensity.comfortable,
      ),
      motion: _enumByName(
        MotionPreference.values,
        _store.getString(motionKey),
        MotionPreference.system,
      ),
      highContrast: _parseEnabled(
        _store.getString(highContrastKey),
        defaultValue: false,
      ),
      pulseLayout: _enumByName(
        PulseLayoutPreference.values,
        _store.getString(pulseLayoutKey),
        PulseLayoutPreference.mediaForward,
      ),
      dataSaver: _parseEnabled(
        _store.getString(dataSaverKey),
        defaultValue: false,
      ),
      autoplayMedia: _parseEnabled(
        _store.getString(autoplayKey),
        defaultValue: true,
      ),
    );
    // Unit tests and lightweight previews intentionally do not bootstrap the
    // Supabase SDK. Local appearance preferences must remain usable there.
    final userId = KlectSupabase.isInitialised
        ? ref.watch(currentUserIdProvider)
        : null;
    if (userId != null && userId != _hydratedUser) {
      _hydratedUser = userId;
      unawaited(_hydrateRemote(userId));
    }
    return local;
  }

  /// Sets and persists the theme override.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode, oled: false);
    await _store.setString(themeModeKey, mode.name);
    await _store.setString(oledKey, 'false');
    unawaited(_syncRemote());
  }

  /// Enables the OLED theme.
  Future<void> setOled(bool enabled) async {
    state = state.copyWith(
      oled: enabled,
      themeMode: enabled ? ThemeMode.dark : state.themeMode,
    );
    await _store.setString(oledKey, '$enabled');
    if (enabled) await _store.setString(themeModeKey, ThemeMode.dark.name);
    unawaited(_syncRemote());
  }

  /// Enables or disables the platform-native tap sound.
  Future<void> setInteractionSoundsEnabled(bool enabled) async {
    state = state.copyWith(interactionSoundsEnabled: enabled);
    await _store.setString(interactionSoundsKey, '$enabled');
  }

  /// Enables or disables platform haptic feedback.
  Future<void> setHapticsEnabled(bool enabled) async {
    state = state.copyWith(hapticsEnabled: enabled);
    await _store.setString(hapticsKey, '$enabled');
  }

  /// Applies one bundled font pack.
  Future<void> setFontPack(FontPack value) =>
      _setEnum(fontPackKey, value, state.copyWith(fontPack: value));

  /// Applies a multiplier without replacing the OS accessibility scale.
  Future<void> setTextScale(double value) async {
    final clamped = value.clamp(0.9, 1.2);
    state = state.copyWith(textScale: clamped);
    await _store.setString(textScaleKey, '$clamped');
    unawaited(_syncRemote());
  }

  /// Applies compact or comfortable spacing.
  Future<void> setDensity(ContentDensity value) =>
      _setEnum(densityKey, value, state.copyWith(density: value));

  /// Applies the motion preference.
  Future<void> setMotion(MotionPreference value) =>
      _setEnum(motionKey, value, state.copyWith(motion: value));

  /// Enables the high-contrast presentation.
  Future<void> setHighContrast(bool value) =>
      _setBool(highContrastKey, value, state.copyWith(highContrast: value));

  /// Chooses the Pulse layout.
  Future<void> setPulseLayout(PulseLayoutPreference value) =>
      _setEnum(pulseLayoutKey, value, state.copyWith(pulseLayout: value));

  /// Enables data saving.
  Future<void> setDataSaver(bool value) =>
      _setBool(dataSaverKey, value, state.copyWith(dataSaver: value));

  /// Enables media autoplay.
  Future<void> setAutoplayMedia(bool value) =>
      _setBool(autoplayKey, value, state.copyWith(autoplayMedia: value));

  /// Restores curated defaults while preserving sound/haptic choices.
  Future<void> resetAppearance() async {
    final defaults = AppSettings(
      interactionSoundsEnabled: state.interactionSoundsEnabled,
      hapticsEnabled: state.hapticsEnabled,
    );
    state = defaults;
    await Future.wait<void>(<Future<void>>[
      _store.setString(themeModeKey, defaults.themeMode.name),
      _store.setString(oledKey, '${defaults.oled}'),
      _store.setString(fontPackKey, defaults.fontPack.name),
      _store.setString(textScaleKey, '${defaults.textScale}'),
      _store.setString(densityKey, defaults.density.name),
      _store.setString(motionKey, defaults.motion.name),
      _store.setString(highContrastKey, '${defaults.highContrast}'),
      _store.setString(pulseLayoutKey, defaults.pulseLayout.name),
      _store.setString(dataSaverKey, '${defaults.dataSaver}'),
      _store.setString(autoplayKey, '${defaults.autoplayMedia}'),
    ]);
    unawaited(_syncRemote());
  }

  Future<void> _setBool(String key, bool value, AppSettings next) async {
    state = next;
    await _store.setString(key, '$value');
    unawaited(_syncRemote());
  }

  Future<void> _setEnum(String key, Enum value, AppSettings next) async {
    state = next;
    await _store.setString(key, value.name);
    unawaited(_syncRemote());
  }

  Future<void> _hydrateRemote(String userId) async {
    try {
      final row = await ref
          .read(klectApiProvider)
          .client
          .from('user_preferences')
          .select('appearance')
          .eq('user_id', userId)
          .maybeSingle();
      if (row == null ||
          !KlectSupabase.isInitialised ||
          ref.read(currentUserIdProvider) != userId) {
        return;
      }
      final appearance = asMap(row['appearance']);
      if (appearance.isEmpty) return;
      final remote = state.copyWith(
        themeMode: _parseThemeMode(asStringOrNull(appearance['theme'])),
        oled: appearance['theme'] == 'oled',
        fontPack: _enumByName(
          FontPack.values,
          asStringOrNull(appearance['font_pack']),
          state.fontPack,
        ),
        textScale: (appearance['text_scale'] as num?)?.toDouble(),
        density: _enumByName(
          ContentDensity.values,
          asStringOrNull(appearance['density']),
          state.density,
        ),
        motion: _enumByName(
          MotionPreference.values,
          asStringOrNull(appearance['motion']),
          state.motion,
        ),
        highContrast: appearance['high_contrast'] as bool?,
        pulseLayout: appearance['pulse_layout'] == 'balanced'
            ? PulseLayoutPreference.balanced
            : PulseLayoutPreference.mediaForward,
        dataSaver: appearance['data_saver'] as bool?,
        autoplayMedia: appearance['autoplay_media'] as bool?,
      );
      state = remote;
      await _persistAppearance(remote);
    } on Object {
      // Older servers may not have the additive preferences migration yet.
    }
  }

  Future<void> _syncRemote() async {
    if (!KlectSupabase.isInitialised ||
        ref.read(currentUserIdProvider) == null) {
      return;
    }
    try {
      await ref
          .read(klectApiProvider)
          .client
          .rpc<dynamic>(
            'save_appearance_preferences',
            params: <String, dynamic>{
              'p_version': 1,
              'p_appearance': state.toAppearanceJson(),
            },
          );
    } on Object {
      // Local preference remains authoritative until connectivity returns.
    }
  }

  Future<void> _persistAppearance(AppSettings value) =>
      Future.wait<void>(<Future<void>>[
        _store.setString(themeModeKey, value.themeMode.name),
        _store.setString(oledKey, '${value.oled}'),
        _store.setString(fontPackKey, value.fontPack.name),
        _store.setString(textScaleKey, '${value.textScale}'),
        _store.setString(densityKey, value.density.name),
        _store.setString(motionKey, value.motion.name),
        _store.setString(highContrastKey, '${value.highContrast}'),
        _store.setString(pulseLayoutKey, value.pulseLayout.name),
        _store.setString(dataSaverKey, '${value.dataSaver}'),
        _store.setString(autoplayKey, '${value.autoplayMedia}'),
      ]);

  static ThemeMode _parseThemeMode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  static bool _parseEnabled(String? value, {required bool defaultValue}) =>
      switch (value) {
        'true' => true,
        'false' => false,
        _ => defaultValue,
      };

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
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
