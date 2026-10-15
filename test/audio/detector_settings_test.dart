import 'package:bpmcounter/src/audio/detector_settings.dart';
import 'package:bpmcounter/src/audio/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('DetectorSettings', () {
    test('defaults focus on kick and bass', () {
      expect(FilterPreset.kickBass.matches(DetectorSettings.defaults), isTrue);
      expect(DetectorSettings.defaults.normalized(), DetectorSettings.defaults);
    });

    test('normalized clamps values into their ranges', () {
      const wild = DetectorSettings(
        highPassHz: 1,
        lowPassHz: 1e6,
        minBpm: 1,
        maxBpm: 1000,
        noiseGateDb: 10,
      );
      final n = wild.normalized();
      expect(n.highPassHz, DetectorSettings.highPassMin);
      expect(n.lowPassHz, DetectorSettings.lowPassMax);
      expect(n.minBpm, DetectorSettings.bpmLimitMin);
      expect(n.maxBpm, DetectorSettings.bpmLimitMax);
      expect(n.noiseGateDb, DetectorSettings.noiseGateMax);
    });

    test('normalized keeps the high-pass below the low-pass', () {
      const crossed = DetectorSettings(highPassHz: 3000, lowPassHz: 1000);
      final n = crossed.normalized();
      expect(n.highPassHz!, lessThan(n.lowPassHz!));
      expect(n.highPassHz, 3000);
    });

    test('normalized swaps a reversed tempo range and keeps one octave', () {
      final swapped = DetectorSettings.defaults.copyWith(minBpm: 180, maxBpm: 90).normalized();
      expect(swapped.minBpm, 90);
      expect(swapped.maxBpm, 180);

      final narrow = DetectorSettings.defaults.copyWith(minBpm: 120, maxBpm: 130).normalized();
      expect(narrow.minBpm, 120);
      expect(narrow.maxBpm, 240);

      final top = DetectorSettings.defaults.copyWith(minBpm: 250, maxBpm: 300).normalized();
      expect(top.maxBpm, 300);
      expect(top.minBpm, 150);
    });

    test('map round trip keeps disabled filters', () {
      const settings = DetectorSettings(
        highPassHz: 120,
        lowPassHz: null,
        minBpm: 80,
        maxBpm: 180,
        noiseGateDb: -50,
      );
      expect(DetectorSettings.fromMap(settings.toMap()), settings);
      expect(settings.toMap().containsKey('lowPassHz'), isFalse);
    });

    test('presets only change the filters', () {
      final custom = DetectorSettings.defaults.copyWith(minBpm: 90, maxBpm: 190, noiseGateDb: -40);
      final hats = FilterPreset.hiHats.applyTo(custom);
      expect(hats.highPassHz, 5000);
      expect(hats.lowPassHz, isNull);
      expect(hats.minBpm, 90);
      expect(hats.noiseGateDb, -40);
      expect(FilterPreset.values.where((p) => p.matches(hats)), [FilterPreset.hiHats]);
    });

    test('copyWith can disable a filter', () {
      final off = DetectorSettings.defaults.copyWith(lowPassHz: () => null);
      expect(off.lowPassHz, isNull);
      expect(FilterPreset.fullRange.matches(off), isTrue);
    });
  });

  group('PreferencesSettingsStore', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    });

    test('returns the defaults when nothing was saved', () async {
      expect(await PreferencesSettingsStore().load(), DetectorSettings.defaults);
    });

    test('saves and loads settings, including disabled filters', () async {
      const settings = DetectorSettings(
        highPassHz: null,
        lowPassHz: null,
        minBpm: 70,
        maxBpm: 160,
        noiseGateDb: -45,
      );
      await PreferencesSettingsStore().save(settings);
      expect(await PreferencesSettingsStore().load(), settings);

      const other = DetectorSettings(highPassHz: 4000, lowPassHz: 12000);
      await PreferencesSettingsStore().save(other);
      expect(await PreferencesSettingsStore().load(), other);
    });

    test('ignores incomplete data', () async {
      await SharedPreferencesAsync().setDouble('detector.minBpm', 100);
      expect(await PreferencesSettingsStore().load(), DetectorSettings.defaults);
    });
  });
}
