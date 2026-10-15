import 'dart:math' as math;
import 'dart:typed_data';

/// Synthetic test signals for the tempo detector.

/// A drum-like pattern: a decaying low "kick" on every beat, optionally a
/// high-frequency "hi-hat" on the off-beats, plus white noise.
Float64List drumLoop({
  required double bpm,
  required double seconds,
  double sampleRate = 44100,
  double kickHz = 60,
  double kickLevel = 0.8,
  double hatLevel = 0,
  double noiseLevel = 0.02,
  double offBeatHatsPerBeat = 2,
  int seed = 1,
}) {
  final random = math.Random(seed);
  final n = (seconds * sampleRate).round();
  final out = Float64List(n);
  final beat = 60 / bpm;
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final sinceBeat = t % beat;
    var v = kickLevel * math.exp(-sinceBeat * 25) * math.sin(2 * math.pi * kickHz * sinceBeat);
    if (hatLevel > 0) {
      final hatPeriod = beat / offBeatHatsPerBeat;
      final sinceHat = (t + hatPeriod / 2) % hatPeriod;
      v += hatLevel * math.exp(-sinceHat * 80) * (random.nextDouble() * 2 - 1);
    }
    v += noiseLevel * (random.nextDouble() * 2 - 1);
    out[i] = v;
  }
  return out;
}

Float64List sine(double hz, double seconds, {double sampleRate = 44100, double amplitude = 0.5}) {
  final n = (seconds * sampleRate).round();
  return Float64List.fromList([
    for (var i = 0; i < n; i++) amplitude * math.sin(2 * math.pi * hz * i / sampleRate),
  ]);
}

Float64List whiteNoise(
  double seconds, {
  double sampleRate = 44100,
  double amplitude = 0.3,
  int seed = 7,
}) {
  final random = math.Random(seed);
  final n = (seconds * sampleRate).round();
  return Float64List.fromList([
    for (var i = 0; i < n; i++) amplitude * (random.nextDouble() * 2 - 1),
  ]);
}

double rms(Float64List samples, {int skip = 0}) {
  var sum = 0.0;
  for (var i = skip; i < samples.length; i++) {
    sum += samples[i] * samples[i];
  }
  return math.sqrt(sum / (samples.length - skip));
}
