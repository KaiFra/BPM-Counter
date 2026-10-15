import 'package:bpmcounter/src/audio/detector_settings.dart';
import 'package:bpmcounter/src/audio/listen_controller.dart';
import 'package:bpmcounter/src/audio/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_audio_input.dart';
import '../support/signals.dart';

void main() {
  late FakeAudioInput input;
  late MemorySettingsStore store;
  late ListenController controller;

  setUp(() {
    input = FakeAudioInput();
    store = MemorySettingsStore();
    controller = ListenController(input: input, store: store);
  });

  tearDown(() => controller.dispose());

  test('starts idle without touching the microphone', () {
    expect(controller.status, ListenStatus.idle);
    expect(input.permissionRequests, 0);
    expect(controller.bpm, isNull);
  });

  test('detects the tempo from the input stream', () async {
    await controller.start();
    expect(controller.status, ListenStatus.listening);
    expect(input.startedWithSampleRate, 44100);

    input.emit(drumLoop(bpm: 122, seconds: 2));
    await pumpEventQueue();
    expect(controller.bpm, isNull);
    expect(controller.warmUp, inExclusiveRange(0.5, 1));

    input.emit(drumLoop(bpm: 122, seconds: 6));
    await pumpEventQueue();
    expect(controller.bpm, closeTo(122, 0.3));
    expect(controller.confidence, greaterThan(0.5));
    expect(controller.beats, greaterThan(10));
    expect(controller.envelope.length, ListenController.graphLength);
  });

  test('stop releases the microphone and toggle restarts', () async {
    await controller.toggle();
    expect(input.isRunning, isTrue);
    await controller.toggle();
    expect(controller.status, ListenStatus.idle);
    expect(input.isRunning, isFalse);
    await controller.toggle();
    expect(controller.status, ListenStatus.listening);
  });

  test('reports a denied permission', () async {
    input.grantPermission = false;
    await controller.start();
    expect(controller.status, ListenStatus.permissionDenied);
    expect(input.isRunning, isFalse);

    // Asking again works once the user allows it.
    input.grantPermission = true;
    await controller.start();
    expect(controller.status, ListenStatus.listening);
  });

  test('reports stream errors', () async {
    await controller.start();
    input.fail(StateError('mic busy'));
    await pumpEventQueue();
    expect(controller.status, ListenStatus.error);
    expect(controller.errorMessage, contains('mic busy'));
    expect(input.isRunning, isFalse);
  });

  test('loads stored settings on init', () async {
    store.settings = FilterPreset.hiHats.applyTo(DetectorSettings.defaults);
    await controller.init();
    expect(controller.settings, store.settings);
  });

  test('settings changes apply immediately and are saved', () async {
    await controller.start();
    input.emit(drumLoop(bpm: 120, seconds: 6));
    await pumpEventQueue();
    expect(controller.bpm, isNotNull);

    final full = FilterPreset.fullRange.applyTo(controller.settings);
    await controller.updateSettings(full);
    expect(controller.settings, full);
    expect(store.settings, full);
    // A new filter means a new analysis.
    expect(controller.bpm, isNull);

    input.emit(drumLoop(bpm: 120, seconds: 6));
    await pumpEventQueue();
    expect(controller.bpm, closeTo(120, 0.3));
  });

  test('settings are normalized before saving', () async {
    await controller.updateSettings(DetectorSettings.defaults.copyWith(minBpm: 200, maxBpm: 100));
    expect(store.settings.minBpm, 100);
    expect(store.settings.maxBpm, 200);
  });

  test('dispose releases the input', () async {
    final other = FakeAudioInput();
    final c = ListenController(input: other, store: store);
    await c.start();
    c.dispose();
    await pumpEventQueue();
    expect(other.disposed, isTrue);
    expect(other.isRunning, isFalse);
  });
}
