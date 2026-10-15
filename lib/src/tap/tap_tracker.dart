/// Turns a series of taps into a tempo.
///
/// The main reading is the average tempo since the first tap of the current
/// session, like a classic tap-tempo button: the longer you tap, the more
/// precise it gets. A session ends with [reset] or automatically when the user
/// pauses for longer than [restartAfter]; its numbers stay available as
/// "previous" values.
class TapTracker {
  TapTracker({
    this.restartAfter = const Duration(seconds: 3),
    this.minInterval = const Duration(milliseconds: 100),
    this.recentTaps = 5,
  }) : assert(recentTaps >= 2);

  /// A pause longer than this starts a new session on the next tap.
  final Duration restartAfter;

  /// Taps closer together than this are treated as one (e.g. a double touch).
  final Duration minInterval;

  /// Number of taps used for [recentBpm].
  final int recentTaps;

  final List<Duration> _times = [];
  double _peakBpm = 0;

  int _previousTaps = 0;
  double? _previousBpm;
  double _previousPeakBpm = 0;

  /// Taps in the current session.
  int get taps => _times.length;

  /// Average tempo since the first tap, or null before the second tap.
  double? get bpm {
    if (_times.length < 2) return null;
    return _bpmOver(_times.first, _times.last, _times.length - 1);
  }

  /// Tempo over the last [recentTaps] taps; follows tempo changes quickly.
  double? get recentBpm {
    if (_times.length < 2) return null;
    final first = _times.length > recentTaps ? _times.length - recentTaps : 0;
    return _bpmOver(_times[first], _times.last, _times.length - 1 - first);
  }

  /// Highest average tempo reached in this session.
  double get peakBpm => _peakBpm;

  int get previousTaps => _previousTaps;
  double? get previousBpm => _previousBpm;
  double get previousPeakBpm => _previousPeakBpm;

  /// Whether a tap at [time] would start a new session.
  bool wouldRestart(Duration time) {
    if (_times.isEmpty) return false;
    final sinceLast = time - _times.last;
    return sinceLast.isNegative || sinceLast > restartAfter;
  }

  /// Registers a tap. Returns false if it was ignored as a duplicate.
  bool tap(Duration time) {
    if (_times.isNotEmpty) {
      final sinceLast = time - _times.last;
      // A timestamp from the past means the time source changed (e.g. a
      // screen reader tap after touch taps): start over instead of guessing.
      if (sinceLast.isNegative || sinceLast > restartAfter) {
        reset();
      } else if (sinceLast < minInterval) {
        return false;
      }
    }
    _times.add(time);
    final current = bpm;
    if (current != null && current > _peakBpm) _peakBpm = current;
    return true;
  }

  /// Ends the current session. Its values become the "previous" values,
  /// unless it had no taps at all.
  void reset() {
    if (_times.isNotEmpty) {
      _previousTaps = _times.length;
      _previousBpm = bpm;
      _previousPeakBpm = _peakBpm;
    }
    _times.clear();
    _peakBpm = 0;
  }

  static double _bpmOver(Duration from, Duration to, int intervals) {
    final micros = (to - from).inMicroseconds;
    if (micros <= 0) return 0;
    return intervals * Duration.microsecondsPerMinute / micros;
  }
}
