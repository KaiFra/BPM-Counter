import 'dart:math' as math;
import 'dart:typed_data';

import 'biquad.dart';
import 'detector_settings.dart';

/// A tempo reading from [TempoDetector.estimate].
class TempoEstimate {
  const TempoEstimate(this.bpm, this.confidence);

  final double bpm;

  /// 0 (noise) .. 1 (perfectly periodic). Readings below ~0.1 are guesses.
  final double confidence;

  @override
  String toString() =>
      'TempoEstimate(${bpm.toStringAsFixed(2)} BPM, '
      'confidence ${confidence.toStringAsFixed(2)})';
}

/// Estimates the tempo of an audio signal.
///
/// 1. The signal runs through the user's [BandFilter] (high/low pass).
/// 2. Every ~5 ms the loudness is measured; rises in loudness ("onsets", like
///    a drum hit) form the onset envelope.
/// 3. The autocorrelation of the last [windowSeconds] of that envelope shows
///    which beat period repeats best. Harmonic weighting and a mild preference
///    for tempos around 120 BPM resolve half/double tempo ambiguities.
///
/// The class is pure Dart and does not know where the samples come from,
/// which keeps it testable with synthetic signals.
class TempoDetector {
  TempoDetector({
    required this.sampleRate,
    required DetectorSettings settings,
    this.windowSeconds = 8,
    this.minSeconds = 3,
  }) : hopSize = math.max(1, (sampleRate / _targetEnvelopeRate).round()),
       _settings = settings.normalized() {
    _capacity = (windowSeconds * envelopeRate).ceil();
    _onsets = Float64List(_capacity);
    _filter = _createFilter();
  }

  static const _targetEnvelopeRate = 200.0;
  static const _energyHops = 4;

  final double sampleRate;
  final double windowSeconds;

  /// Minimum amount of audio before the first estimate.
  final double minSeconds;

  /// Number of samples per envelope frame.
  final int hopSize;

  double get envelopeRate => sampleRate / hopSize;

  DetectorSettings _settings;
  DetectorSettings get settings => _settings;

  late BandFilter _filter;
  late final int _capacity;
  late final Float64List _onsets; // ring buffer
  int _written = 0; // total frames written

  // Partial frame state.
  double _hopEnergy = 0;
  int _hopFill = 0;
  late final Float64List _hopEnergies = Float64List(_energyHops);
  int _hopIndex = 0;
  double _previousDb = double.negativeInfinity;

  // Beat (onset peak) detection state.
  double _onsetAverage = 0;
  int _lastBeatFrame = -1 << 30;
  double _levelDb = double.negativeInfinity;

  /// Loudness of the filtered signal of the last frame, in dB full scale.
  double get levelDb => _levelDb;

  /// Total number of envelope frames analysed so far.
  int get framesProcessed => _written;

  /// Changes the filter/range settings. The analysis restarts because old
  /// envelope data was measured with a different filter.
  set settings(DetectorSettings value) {
    final normalized = value.normalized();
    if (normalized == _settings) return;
    final filterChanged =
        normalized.highPassHz != _settings.highPassHz ||
        normalized.lowPassHz != _settings.lowPassHz ||
        normalized.noiseGateDb != _settings.noiseGateDb;
    _settings = normalized;
    if (filterChanged) {
      _filter = _createFilter();
      reset();
    }
  }

  BandFilter _createFilter() => BandFilter(
    sampleRate: sampleRate,
    highPassHz: _settings.highPassHz,
    lowPassHz: _settings.lowPassHz,
  );

  void reset() {
    _filter.reset();
    _written = 0;
    _hopEnergy = 0;
    _hopFill = 0;
    _hopEnergies.fillRange(0, _energyHops, 0);
    _hopIndex = 0;
    _previousDb = double.negativeInfinity;
    _onsetAverage = 0;
    _lastBeatFrame = -1 << 30;
    _levelDb = double.negativeInfinity;
  }

  /// Feeds samples in the range -1..1. Returns the number of beats (onset
  /// peaks) detected in this chunk, useful to flash a beat indicator.
  int addSamples(Float64List samples) {
    final filtered = Float64List.fromList(samples);
    _filter.processInPlace(filtered);
    var beats = 0;
    for (final s in filtered) {
      _hopEnergy += s * s;
      if (++_hopFill == hopSize) {
        if (_finishFrame(_hopEnergy / hopSize)) beats++;
        _hopEnergy = 0;
        _hopFill = 0;
      }
    }
    return beats;
  }

  bool _finishFrame(double meanSquare) {
    // Measure the level over a sliding window of ~20 ms: long enough to
    // contain full periods of bass notes (no ripple), short enough to keep
    // the attack of a drum hit sharp.
    _hopEnergies[_hopIndex] = meanSquare;
    _hopIndex = (_hopIndex + 1) % _energyHops;
    var energy = 0.0;
    for (final e in _hopEnergies) {
      energy += e;
    }
    energy /= _energyHops;
    _levelDb = 10 * math.log(energy + 1e-12) / math.ln10;

    // Below the noise gate everything counts as silence. Working in dB makes
    // the detection independent of the input volume.
    final db = math.max(_levelDb, _settings.noiseGateDb);
    final onset = _previousDb.isFinite ? math.max(0.0, db - _previousDb) : 0.0;
    _previousDb = db;

    _onsets[_written % _capacity] = onset;
    _written++;

    // Beat indicator: a clear peak over the recent average, at most once per
    // fraction of the fastest allowed beat.
    final refractory = (0.6 * 60 / _settings.maxBpm * envelopeRate).round();
    final isBeat =
        onset > 1.5 && onset > 3 * _onsetAverage && _written - _lastBeatFrame > refractory;
    if (isBeat) _lastBeatFrame = _written;
    _onsetAverage += (onset - _onsetAverage) / envelopeRate; // ~1 s average
    return isBeat;
  }

  /// The most recent [count] onset envelope values, oldest first.
  Float64List recentEnvelope(int count) {
    final n = math.min(count, math.min(_written, _capacity));
    final out = Float64List(count);
    for (var i = 0; i < n; i++) {
      out[count - n + i] = _onsets[(_written - n + i) % _capacity];
    }
    return out;
  }

  /// Current tempo estimate, or null if there is not enough (or no
  /// periodic) signal yet.
  TempoEstimate? estimate() {
    final n = math.min(_written, _capacity);
    if (n < minSeconds * envelopeRate) return null;

    // Chronological copy, lightly smoothed so the autocorrelation peaks get
    // wide enough for sub-frame interpolation, then made zero-mean.
    final raw = Float64List(n);
    for (var i = 0; i < n; i++) {
      raw[i] = _onsets[(_written - n + i) % _capacity];
    }
    const kernel = [1.0, 2.0, 3.0, 2.0, 1.0];
    final x = Float64List(n);
    var mean = 0.0;
    for (var i = 0; i < n; i++) {
      var sum = 0.0, weight = 0.0;
      for (var k = 0; k < kernel.length; k++) {
        final j = i + k - kernel.length ~/ 2;
        if (j < 0 || j >= n) continue;
        sum += raw[j] * kernel[k];
        weight += kernel[k];
      }
      x[i] = sum / weight;
      mean += x[i];
    }
    mean /= n;
    for (var i = 0; i < n; i++) {
      x[i] -= mean;
    }

    final rate = envelopeRate;
    final lagMin = math.max(2, (60 * rate / _settings.maxBpm).floor());
    final lagMax = math.min(n ~/ 2, (60 * rate / _settings.minBpm).ceil());
    if (lagMax <= lagMin) return null;
    final acfLength = math.min(n - 1, 2 * lagMax + 2);

    final r = Float64List(acfLength + 1);
    for (var lag = 0; lag <= acfLength; lag++) {
      var sum = 0.0;
      for (var i = 0; i + lag < n; i++) {
        sum += x[i] * x[i + lag];
      }
      r[lag] = sum / (n - lag); // unbiased
    }
    if (r[0] <= 1e-9) return null; // silence or constant signal

    // Prefer tempos near 120 BPM (log-normal, 1.5 octaves wide), clamped
    // into the user's range.
    final preferred = 120.0.clamp(_settings.minBpm, _settings.maxBpm);
    var bestLag = -1;
    var bestScore = double.negativeInfinity;
    for (var lag = lagMin; lag <= lagMax; lag++) {
      if (r[lag] <= 0) continue;
      // Local maxima only: a beat period is a peak of the autocorrelation.
      if (r[lag] < r[lag - 1] || r[lag] < r[lag + 1]) continue;
      final harmonic = 2 * lag <= acfLength ? math.max(0.0, r[2 * lag]) : 0.0;
      final octaves = math.log(60 * rate / lag / preferred) / math.ln2;
      final prior = math.exp(-0.5 * math.pow(octaves / 1.5, 2));
      final score = (r[lag] + 0.5 * harmonic) * prior;
      if (score > bestScore) {
        bestScore = score;
        bestLag = lag;
      }
    }
    if (bestLag < 0) return null;

    // Parabolic interpolation around the peak for sub-frame precision.
    final a = r[bestLag - 1], b = r[bestLag], c = r[bestLag + 1];
    final denominator = a - 2 * b + c;
    var offset = denominator.abs() > 1e-12 ? 0.5 * (a - c) / denominator : 0.0;
    offset = offset.clamp(-0.5, 0.5);
    final bpm = (60 * rate / (bestLag + offset))
        .clamp(_settings.minBpm, _settings.maxBpm)
        .toDouble();
    final confidence = (b / r[0]).clamp(0.0, 1.0).toDouble();
    return TempoEstimate(bpm, confidence);
  }
}

/// Stabilises the displayed tempo: the median of the last few confident
/// estimates, so a single outlier does not make the number jump.
class TempoSmoother {
  TempoSmoother({this.size = 5, this.minConfidence = 0.1});

  final int size;
  final double minConfidence;
  final List<double> _values = [];

  double? get value {
    if (_values.isEmpty) return null;
    final sorted = [..._values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Adds an estimate and returns the smoothed tempo.
  double? add(TempoEstimate? estimate) {
    if (estimate != null && estimate.confidence >= minConfidence) {
      _values.add(estimate.bpm);
      if (_values.length > size) _values.removeAt(0);
    }
    return value;
  }

  void reset() => _values.clear();
}

/// Converts little-endian 16-bit PCM byte chunks into samples in -1..1.
/// Chunks may split a sample; the odd byte is kept for the next chunk.
class Pcm16Decoder {
  int? _carry;

  Float64List convert(Uint8List bytes) {
    final carry = _carry;
    final data = carry == null
        ? bytes
        : (Uint8List(bytes.length + 1)
            ..[0] = carry
            ..setRange(1, bytes.length + 1, bytes));
    final view = ByteData.sublistView(data);
    final out = Float64List(data.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = view.getInt16(2 * i, Endian.little) / 32768.0;
    }
    _carry = data.length.isOdd ? data.last : null;
    return out;
  }

  void reset() => _carry = null;
}
