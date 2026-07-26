import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tiny durable key/value abstraction.
///
/// Everything that must survive a cold start — the offline action queue, the
/// theme override — writes through this. It exists so tests can substitute an
/// in-memory map instead of mocking a platform channel.
abstract class KeyValueStore {
  /// Reads a value, or null.
  String? getString(String key);

  /// Writes a value.
  Future<void> setString(String key, String value);

  /// Deletes a key.
  Future<void> remove(String key);
}

/// [KeyValueStore] backed by `shared_preferences`.
class PrefsKeyValueStore implements KeyValueStore {
  /// Wraps an already-loaded [SharedPreferences] instance.
  const PrefsKeyValueStore(this._prefs);

  /// Loads the platform store. Call once from `main()`.
  static Future<PrefsKeyValueStore> load() async =>
      PrefsKeyValueStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _prefs.remove(key);
  }
}

/// [KeyValueStore] backed by a plain map — the default, and what tests use.
class MemoryKeyValueStore implements KeyValueStore {
  /// Creates an empty in-memory store.
  MemoryKeyValueStore([Map<String, String>? seed])
      : _values = <String, String>{...?seed};

  final Map<String, String> _values;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}

/// The durable store. `main()` overrides this with [PrefsKeyValueStore];
/// leaving the in-memory default means a widget test never touches a plugin.
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => MemoryKeyValueStore(),
  name: 'keyValueStore',
);
