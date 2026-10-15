import 'package:shared_preferences/shared_preferences.dart';

import 'detector_settings.dart';

/// Persists [DetectorSettings] between app launches.
abstract class SettingsStore {
  Future<DetectorSettings> load();
  Future<void> save(DetectorSettings settings);
}

/// Stores the settings in the app's private SharedPreferences.
class PreferencesSettingsStore implements SettingsStore {
  PreferencesSettingsStore([SharedPreferencesAsync? preferences])
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  static const _prefix = 'detector.';
  static const _keys = ['highPassHz', 'lowPassHz', 'minBpm', 'maxBpm', 'noiseGateDb'];
  // Disabled filters are stored as this value, because a missing key means
  // "use the default".
  static const _off = -1.0;

  @override
  Future<DetectorSettings> load() async {
    // [save] always writes every key, so one missing key means "never saved".
    final values = <String, double?>{};
    for (final key in _keys) {
      final value = await _preferences.getDouble('$_prefix$key');
      if (value == null) return DetectorSettings.defaults;
      values[key] = value == _off ? null : value;
    }
    return DetectorSettings.fromMap(values);
  }

  @override
  Future<void> save(DetectorSettings settings) async {
    final map = settings.toMap();
    for (final key in _keys) {
      await _preferences.setDouble('$_prefix$key', map[key] ?? _off);
    }
  }
}

/// Keeps settings in memory only (tests, or if storage is unavailable).
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.settings = DetectorSettings.defaults]);

  DetectorSettings settings;

  @override
  Future<DetectorSettings> load() async => settings;

  @override
  Future<void> save(DetectorSettings settings) async => this.settings = settings;
}
