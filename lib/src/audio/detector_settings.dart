import 'dart:math' as math;

/// User-adjustable settings for the microphone tempo detection.
class DetectorSettings {
  const DetectorSettings({
    required this.highPassHz,
    required this.lowPassHz,
    this.minBpm = 60,
    this.maxBpm = 200,
    this.noiseGateDb = -60,
  });

  /// Default: listen to kick drum and bass, which carry the beat in most music.
  static const defaults = DetectorSettings(highPassHz: null, lowPassHz: 200);

  // Slider limits. A high-pass at its minimum or a low-pass at its maximum
  // means "off".
  static const highPassMin = 20.0;
  static const highPassMax = 5000.0;
  static const lowPassMin = 60.0;
  static const lowPassMax = 16000.0;
  static const bpmLimitMin = 30.0;
  static const bpmLimitMax = 300.0;
  static const noiseGateMin = -90.0;
  static const noiseGateMax = -20.0;

  /// High-pass cutoff in Hz, or null when disabled.
  final double? highPassHz;

  /// Low-pass cutoff in Hz, or null when disabled.
  final double? lowPassHz;

  /// Tempo search range. Narrowing it avoids "half" or "double" tempo results.
  final double minBpm;
  final double maxBpm;

  /// Signals quieter than this (in dB full scale, after filtering) are ignored.
  final double noiseGateDb;

  DetectorSettings copyWith({
    double? Function()? highPassHz,
    double? Function()? lowPassHz,
    double? minBpm,
    double? maxBpm,
    double? noiseGateDb,
  }) {
    return DetectorSettings(
      highPassHz: highPassHz != null ? highPassHz() : this.highPassHz,
      lowPassHz: lowPassHz != null ? lowPassHz() : this.lowPassHz,
      minBpm: minBpm ?? this.minBpm,
      maxBpm: maxBpm ?? this.maxBpm,
      noiseGateDb: noiseGateDb ?? this.noiseGateDb,
    );
  }

  /// Returns a copy with every value inside its allowed range and a
  /// consistent order (min below max, high-pass below low-pass).
  DetectorSettings normalized() {
    var hp = highPassHz?.clamp(highPassMin, highPassMax).toDouble();
    var lp = lowPassHz?.clamp(lowPassMin, lowPassMax).toDouble();
    if (hp != null && lp != null && hp >= lp) {
      // Keep at least half an octave of pass band.
      lp = math.min(lowPassMax, hp * math.sqrt2);
      if (hp >= lp) hp = lp / math.sqrt2;
    }
    var lo = minBpm.clamp(bpmLimitMin, bpmLimitMax).toDouble();
    var hi = maxBpm.clamp(bpmLimitMin, bpmLimitMax).toDouble();
    if (lo > hi) (lo, hi) = (hi, lo);
    // The range must hold at least one full octave, otherwise some tempos
    // have no representation in it at all.
    if (hi < lo * 2) {
      hi = math.min(bpmLimitMax, lo * 2);
      lo = hi / 2;
    }
    return DetectorSettings(
      highPassHz: hp,
      lowPassHz: lp,
      minBpm: lo,
      maxBpm: hi,
      noiseGateDb: noiseGateDb.clamp(noiseGateMin, noiseGateMax).toDouble(),
    );
  }

  Map<String, double> toMap() => {
    'highPassHz': ?highPassHz,
    'lowPassHz': ?lowPassHz,
    'minBpm': minBpm,
    'maxBpm': maxBpm,
    'noiseGateDb': noiseGateDb,
  };

  factory DetectorSettings.fromMap(Map<String, double?> map) {
    return DetectorSettings(
      highPassHz: map['highPassHz'],
      lowPassHz: map['lowPassHz'],
      minBpm: map['minBpm'] ?? defaults.minBpm,
      maxBpm: map['maxBpm'] ?? defaults.maxBpm,
      noiseGateDb: map['noiseGateDb'] ?? defaults.noiseGateDb,
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      other is DetectorSettings &&
      other.highPassHz == highPassHz &&
      other.lowPassHz == lowPassHz &&
      other.minBpm == minBpm &&
      other.maxBpm == maxBpm &&
      other.noiseGateDb == noiseGateDb;

  @override
  int get hashCode => Object.hash(highPassHz, lowPassHz, minBpm, maxBpm, noiseGateDb);

  @override
  String toString() =>
      'DetectorSettings(hp: $highPassHz, lp: $lowPassHz, '
      'bpm: $minBpm-$maxBpm, gate: $noiseGateDb dB)';
}

/// Filter presets for typical sources. Tempo range and noise gate are kept.
enum FilterPreset {
  fullRange('Full range', null, null),
  kickBass('Kick & bass', null, 200),
  snare('Snare & claps', 150, 3000),
  hiHats('Hi-hats', 5000, null);

  const FilterPreset(this.label, this.highPassHz, this.lowPassHz);

  final String label;
  final double? highPassHz;
  final double? lowPassHz;

  DetectorSettings applyTo(DetectorSettings settings) =>
      settings.copyWith(highPassHz: () => highPassHz, lowPassHz: () => lowPassHz);

  bool matches(DetectorSettings settings) =>
      settings.highPassHz == highPassHz && settings.lowPassHz == lowPassHz;
}
