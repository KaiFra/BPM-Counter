import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bpmcounter/src/audio/detector_settings.dart';
import 'package:bpmcounter/src/audio/tempo_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/signals.dart';

/// Feeds [signal] in chunks like a microphone stream would.
int feed(TempoDetector detector, Float64List signal, {int chunk = 2048}) {
  var beats = 0;
  for (var i = 0; i < signal.length; i += chunk) {
    beats += detector.addSamples(
      Float64List.sublistView(signal, i, math.min(signal.length, i + chunk)),
    );
  }
  return beats;
}

Float64List mix(Float64List a, Float64List b) =>
    Float64List.fromList([for (var i = 0; i < math.min(a.length, b.length); i++) a[i] + b[i]]);

TempoDetector detector([
  DetectorSettings settings = DetectorSettings.defaults,
  double rate = 44100,
]) => TempoDetector(sampleRate: rate, settings: settings);

void main() {
  group('TempoDetector', () {
    for (final bpm in [65.0, 87.5, 100.0, 118.0, 124.0, 128.0, 140.0, 160.0, 174.0]) {
      test('detects a ${bpm.toStringAsFixed(1)} BPM drum loop', () {
        final d = detector();
        feed(d, drumLoop(bpm: bpm, seconds: 10, hatLevel: 0.4));
        final estimate = d.estimate()!;
        expect(estimate.bpm, closeTo(bpm, 0.3));
        expect(estimate.confidence, greaterThan(0.5));
      });
    }

    test('works at 48 kHz', () {
      final d = detector(DetectorSettings.defaults, 48000);
      feed(d, drumLoop(bpm: 132, seconds: 10, sampleRate: 48000));
      expect(d.estimate()!.bpm, closeTo(132, 0.3));
    });

    test('result does not depend on the chunk size', () {
      final signal = drumLoop(bpm: 111, seconds: 8);
      final a = detector(), b = detector();
      feed(a, signal, chunk: 333);
      feed(b, signal, chunk: 8192);
      expect(a.estimate()!.bpm, closeTo(b.estimate()!.bpm, 1e-9));
    });

    test('is independent of the input volume', () {
      final loud = detector(), quiet = detector();
      feed(loud, drumLoop(bpm: 123, seconds: 8, kickLevel: 0.9, noiseLevel: 0.01));
      feed(quiet, drumLoop(bpm: 123, seconds: 8, kickLevel: 0.009, noiseLevel: 0.0001));
      expect(quiet.estimate()!.bpm, closeTo(loud.estimate()!.bpm, 0.2));
    });

    test('copes with a lot of background noise', () {
      final d = detector();
      feed(d, drumLoop(bpm: 126, seconds: 10, noiseLevel: 0.5));
      final estimate = d.estimate()!;
      expect(estimate.bpm, closeTo(126, 0.5));
      expect(estimate.confidence, greaterThan(0.3));
    });

    test('needs a few seconds of audio before the first estimate', () {
      final d = detector();
      feed(d, drumLoop(bpm: 120, seconds: 2));
      expect(d.estimate(), isNull);
      feed(d, drumLoop(bpm: 120, seconds: 2));
      expect(d.estimate(), isNotNull);
    });

    test('returns nothing for silence', () {
      final d = detector();
      feed(d, Float64List(44100 * 6));
      expect(d.estimate(), isNull);
    });

    test('noise has a low confidence', () {
      final d = detector(const DetectorSettings(highPassHz: null, lowPassHz: null));
      feed(d, whiteNoise(8));
      final estimate = d.estimate();
      expect(estimate == null || estimate.confidence < TempoSmoother().minConfidence, isTrue);
    });

    test('a steady tone is not a beat', () {
      final d = detector();
      feed(d, sine(80, 8));
      final estimate = d.estimate();
      expect(estimate == null || estimate.confidence < 0.1, isTrue);
    });

    test('the noise gate ignores signals below it', () {
      final settings = DetectorSettings.defaults.copyWith(noiseGateDb: -30);
      final d = detector(settings);
      // Kick peaks at about -50 dBFS, well below the gate.
      feed(d, drumLoop(bpm: 120, seconds: 8, kickLevel: 0.003, noiseLevel: 0));
      expect(d.estimate(), isNull);
      expect(d.levelDb, lessThan(-30));
    });

    test('filters pick the instrument: kick vs hi-hat at different tempos', () {
      final kick = drumLoop(bpm: 100, seconds: 10, noiseLevel: 0);
      final hats = drumLoop(
        bpm: 150,
        seconds: 10,
        kickLevel: 0,
        hatLevel: 0.6,
        offBeatHatsPerBeat: 1,
        noiseLevel: 0,
      );
      final song = mix(kick, hats);

      final bass = detector(FilterPreset.kickBass.applyTo(DetectorSettings.defaults));
      feed(bass, song);
      expect(bass.estimate()!.bpm, closeTo(100, 0.3));

      final treble = detector(FilterPreset.hiHats.applyTo(DetectorSettings.defaults));
      feed(treble, song);
      expect(treble.estimate()!.bpm, closeTo(150, 0.3));
    });

    test('the tempo range resolves half/double tempo', () {
      final signal = drumLoop(bpm: 190, seconds: 10);

      final wide = detector();
      feed(wide, signal);
      // Ambiguous: with the default range half tempo is preferred.
      expect(wide.estimate()!.bpm, closeTo(95, 0.3));

      final fast = detector(DetectorSettings.defaults.copyWith(minBpm: 120, maxBpm: 240));
      feed(fast, signal);
      expect(fast.estimate()!.bpm, closeTo(190, 0.5));
    });

    test('follows a tempo change within the analysis window', () {
      final d = detector();
      feed(d, drumLoop(bpm: 100, seconds: 8));
      expect(d.estimate()!.bpm, closeTo(100, 0.3));
      feed(d, drumLoop(bpm: 135, seconds: 8));
      expect(d.estimate()!.bpm, closeTo(135, 0.3));
    });

    test('reports one beat per kick', () {
      final d = detector();
      final beats = feed(d, drumLoop(bpm: 120, seconds: 10, noiseLevel: 0.01));
      expect(beats, inInclusiveRange(18, 21));
    });

    test('changing the filter restarts the analysis', () {
      final d = detector();
      feed(d, drumLoop(bpm: 120, seconds: 6));
      expect(d.estimate(), isNotNull);

      d.settings = d.settings.copyWith(maxBpm: 180); // range only: keeps data
      expect(d.estimate(), isNotNull);

      d.settings = FilterPreset.fullRange.applyTo(d.settings);
      expect(d.framesProcessed, 0);
      expect(d.estimate(), isNull);
    });

    test('recentEnvelope pads with zeros until enough data exists', () {
      final d = detector();
      feed(d, drumLoop(bpm: 120, seconds: 0.5));
      final envelope = d.recentEnvelope(400);
      expect(envelope.length, 400);
      expect(envelope.take(250).every((v) => v == 0), isTrue);
      expect(envelope.any((v) => v > 0), isTrue);
    });
  });

  group('TempoSmoother', () {
    test('median of the last estimates ignores outliers', () {
      final s = TempoSmoother(size: 5);
      for (final bpm in [120.0, 121.0, 60.0, 119.0, 120.5]) {
        s.add(TempoEstimate(bpm, 0.8));
      }
      expect(s.value, 120.0);
    });

    test('ignores estimates with low confidence', () {
      final s = TempoSmoother(minConfidence: 0.2);
      expect(s.add(const TempoEstimate(100, 0.1)), isNull);
      expect(s.add(null), isNull);
      expect(s.add(const TempoEstimate(128, 0.5)), 128);
      expect(s.add(const TempoEstimate(90, 0.05)), 128);
    });

    test('switches to a new tempo once it dominates', () {
      final s = TempoSmoother(size: 5);
      for (var i = 0; i < 5; i++) {
        s.add(const TempoEstimate(100, 0.9));
      }
      s.add(const TempoEstimate(140, 0.9));
      s.add(const TempoEstimate(140, 0.9));
      expect(s.value, 100);
      s.add(const TempoEstimate(140, 0.9));
      expect(s.value, 140);
      s.reset();
      expect(s.value, isNull);
    });
  });

  group('Pcm16Decoder', () {
    test('decodes little-endian signed 16-bit samples', () {
      final bytes = Uint8List.fromList([0x00, 0x00, 0xFF, 0x7F, 0x00, 0x80, 0xFF, 0xFF]);
      final samples = Pcm16Decoder().convert(bytes);
      expect(samples, [0.0, 32767 / 32768, -1.0, -1 / 32768]);
    });

    test('keeps a sample that is split across chunks', () {
      final decoder = Pcm16Decoder();
      expect(decoder.convert(Uint8List.fromList([0x00, 0x40, 0x34])), [0.5]);
      expect(decoder.convert(Uint8List.fromList([0x12])), [0x1234 / 32768]);
      expect(decoder.convert(Uint8List.fromList([0x00])), isEmpty);
      expect(decoder.convert(Uint8List.fromList([0xC0, 0x00, 0x00])), [-0.5, 0.0]);
    });

    test('works on views with an odd offset', () {
      final backing = Uint8List.fromList([0xAA, 0x00, 0x40]);
      final view = Uint8List.sublistView(backing, 1);
      expect(Pcm16Decoder().convert(view), [0.5]);
    });
  });
}
