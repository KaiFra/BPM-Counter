import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bpmcounter/src/audio/biquad.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/signals.dart';

const sampleRate = 44100.0;

double filteredRms(BandFilter filter, Float64List signal) {
  final copy = Float64List.fromList(signal);
  filter.processInPlace(copy);
  // Skip the first 0.2 s so the filter has settled.
  return rms(copy, skip: (0.2 * sampleRate).round());
}

double toDb(double gain) => 20 * math.log(gain) / math.ln10;

void main() {
  group('Biquad', () {
    test('low-pass is -3 dB at the cutoff and passes DC', () {
      final lp = Biquad.lowPass(sampleRate, 1000);
      expect(toDb(lp.magnitudeAt(sampleRate, 1000)), closeTo(-3.01, 0.05));
      expect(lp.magnitudeAt(sampleRate, 1), closeTo(1, 1e-3));
      expect(toDb(lp.magnitudeAt(sampleRate, 10000)), lessThan(-35));
    });

    test('high-pass is -3 dB at the cutoff and blocks DC', () {
      final hp = Biquad.highPass(sampleRate, 1000);
      expect(toDb(hp.magnitudeAt(sampleRate, 1000)), closeTo(-3.01, 0.05));
      expect(hp.magnitudeAt(sampleRate, 1), lessThan(1e-5));
      expect(hp.magnitudeAt(sampleRate, 15000), closeTo(1, 0.01));
    });

    test('process matches the designed response', () {
      final lp = Biquad.lowPass(sampleRate, 500);
      final signal = sine(2000, 1);
      final out = Float64List.fromList([for (final s in signal) lp.process(s)]);
      final measured = rms(out, skip: 4410) / rms(signal, skip: 4410);
      expect(measured, closeTo(lp.magnitudeAt(sampleRate, 2000), 0.005));
    });

    test('stays stable with cutoffs outside the valid range', () {
      for (final cutoff in [0.0, -5.0, 22050.0, 1e6]) {
        final lp = Biquad.lowPass(sampleRate, cutoff);
        final hp = Biquad.highPass(sampleRate, cutoff);
        final noise = whiteNoise(0.5);
        for (final s in noise) {
          expect(lp.process(s).isFinite, isTrue);
          expect(hp.process(s).isFinite, isTrue);
        }
      }
    });
  });

  group('BandFilter', () {
    test('without cutoffs passes the signal unchanged', () {
      final filter = BandFilter(sampleRate: sampleRate, highPassHz: null, lowPassHz: null);
      final signal = whiteNoise(0.1);
      final copy = Float64List.fromList(signal);
      filter.processInPlace(copy);
      expect(copy, signal);
    });

    test('low-pass keeps the bass and removes the treble', () {
      final filter = BandFilter(sampleRate: sampleRate, highPassHz: null, lowPassHz: 200);
      expect(filteredRms(filter, sine(60, 1)) / rms(sine(60, 1)), closeTo(1, 0.02));
      filter.reset();
      // 24 dB/octave: 3+ octaves above the cutoff is below -70 dB.
      expect(toDb(filteredRms(filter, sine(2000, 1)) / rms(sine(2000, 1))), lessThan(-70));
    });

    test('high-pass keeps the treble and removes the bass', () {
      final filter = BandFilter(sampleRate: sampleRate, highPassHz: 2000, lowPassHz: null);
      expect(filteredRms(filter, sine(8000, 1)) / rms(sine(8000, 1)), closeTo(1, 0.02));
      filter.reset();
      expect(toDb(filteredRms(filter, sine(100, 1)) / rms(sine(100, 1))), lessThan(-90));
    });

    test('4th order Butterworth: -3 dB at each cutoff, -24 dB one octave out', () {
      final lp = BandFilter(sampleRate: sampleRate, highPassHz: null, lowPassHz: 1000);
      expect(toDb(lp.magnitudeAt(1000)), closeTo(-3.01, 0.05));
      expect(toDb(lp.magnitudeAt(2000)), closeTo(-24.1, 0.5));
      final hp = BandFilter(sampleRate: sampleRate, highPassHz: 1000, lowPassHz: null);
      expect(toDb(hp.magnitudeAt(1000)), closeTo(-3.01, 0.05));
      expect(toDb(hp.magnitudeAt(500)), closeTo(-24.1, 0.5));
    });

    test('band-pass combines both sides', () {
      final filter = BandFilter(sampleRate: sampleRate, highPassHz: 300, lowPassHz: 3000);
      expect(filter.magnitudeAt(1000), closeTo(1, 0.02));
      expect(toDb(filter.magnitudeAt(50)), lessThan(-55));
      expect(toDb(filter.magnitudeAt(15000)), lessThan(-50));
    });
  });
}
