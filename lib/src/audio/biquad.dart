import 'dart:math' as math;
import 'dart:typed_data';

/// A second-order IIR filter section (direct form I), designed with the
/// formulas from Robert Bristow-Johnson's "Audio EQ Cookbook".
class Biquad {
  Biquad._(this._b0, this._b1, this._b2, this._a1, this._a2);

  /// 12 dB/octave low-pass at [cutoff] Hz.
  factory Biquad.lowPass(double sampleRate, double cutoff, {double q = math.sqrt1_2}) {
    final w = _omega(sampleRate, cutoff);
    final alpha = math.sin(w) / (2 * q);
    final cosW = math.cos(w);
    final a0 = 1 + alpha;
    return Biquad._(
      (1 - cosW) / 2 / a0,
      (1 - cosW) / a0,
      (1 - cosW) / 2 / a0,
      -2 * cosW / a0,
      (1 - alpha) / a0,
    );
  }

  /// 12 dB/octave high-pass at [cutoff] Hz.
  factory Biquad.highPass(double sampleRate, double cutoff, {double q = math.sqrt1_2}) {
    final w = _omega(sampleRate, cutoff);
    final alpha = math.sin(w) / (2 * q);
    final cosW = math.cos(w);
    final a0 = 1 + alpha;
    return Biquad._(
      (1 + cosW) / 2 / a0,
      -(1 + cosW) / a0,
      (1 + cosW) / 2 / a0,
      -2 * cosW / a0,
      (1 - alpha) / a0,
    );
  }

  final double _b0, _b1, _b2, _a1, _a2;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  /// Linear gain of this section at [frequency] Hz.
  double magnitudeAt(double sampleRate, double frequency) {
    final w = 2 * math.pi * frequency / sampleRate;
    // H(e^jw) = (b0 + b1 z^-1 + b2 z^-2) / (1 + a1 z^-1 + a2 z^-2)
    final numRe = _b0 + _b1 * math.cos(w) + _b2 * math.cos(2 * w);
    final numIm = -_b1 * math.sin(w) - _b2 * math.sin(2 * w);
    final denRe = 1 + _a1 * math.cos(w) + _a2 * math.cos(2 * w);
    final denIm = -_a1 * math.sin(w) - _a2 * math.sin(2 * w);
    return math.sqrt((numRe * numRe + numIm * numIm) / (denRe * denRe + denIm * denIm));
  }

  void reset() => _x1 = _x2 = _y1 = _y2 = 0;

  static double _omega(double sampleRate, double cutoff) {
    // Keep the cutoff strictly inside (0, Nyquist) so the design stays stable.
    final nyquist = sampleRate / 2;
    final f = cutoff.clamp(1.0, nyquist * 0.99);
    return 2 * math.pi * f / sampleRate;
  }
}

/// Band-pass made of a 4th-order Butterworth high-pass followed by a
/// 4th-order Butterworth low-pass (24 dB/octave on both sides).
///
/// A cutoff of null disables that side of the band.
class BandFilter {
  BandFilter({required this.sampleRate, required double? highPassHz, required double? lowPassHz})
    : _sections = [
        if (highPassHz != null)
          for (final q in _butterworth4Q) Biquad.highPass(sampleRate, highPassHz, q: q),
        if (lowPassHz != null)
          for (final q in _butterworth4Q) Biquad.lowPass(sampleRate, lowPassHz, q: q),
      ];

  // Q values of the two sections of a 4th-order Butterworth filter.
  static const _butterworth4Q = [0.5411961001461970, 1.3065629648763766];

  final double sampleRate;
  final List<Biquad> _sections;

  /// Filters [samples] in place.
  void processInPlace(Float64List samples) {
    for (final section in _sections) {
      for (var i = 0; i < samples.length; i++) {
        samples[i] = section.process(samples[i]);
      }
    }
  }

  /// Linear gain of the whole filter at [frequency] Hz.
  double magnitudeAt(double frequency) =>
      _sections.fold(1.0, (gain, s) => gain * s.magnitudeAt(sampleRate, frequency));

  void reset() {
    for (final s in _sections) {
      s.reset();
    }
  }
}
