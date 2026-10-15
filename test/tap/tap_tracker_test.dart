import 'package:bpmcounter/src/tap/tap_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps [count] times every [intervalMs], starting at [startMs].
void tapSteadily(
  TapTracker tracker, {
  required int count,
  required int intervalMs,
  int startMs = 0,
}) {
  for (var i = 0; i < count; i++) {
    tracker.tap(Duration(milliseconds: startMs + i * intervalMs));
  }
}

void main() {
  group('TapTracker', () {
    test('needs two taps for a tempo', () {
      final tracker = TapTracker();
      expect(tracker.bpm, isNull);
      expect(tracker.recentBpm, isNull);
      tracker.tap(Duration.zero);
      expect(tracker.taps, 1);
      expect(tracker.bpm, isNull);
      tracker.tap(const Duration(milliseconds: 500));
      expect(tracker.bpm, closeTo(120, 1e-9));
    });

    test('averages a steady beat', () {
      final tracker = TapTracker();
      tapSteadily(tracker, count: 17, intervalMs: 469); // ~128 BPM
      expect(tracker.taps, 17);
      expect(tracker.bpm, closeTo(60000 / 469, 1e-9));
    });

    test('average evens out jitter', () {
      final tracker = TapTracker();
      const offsets = [0, 12, -15, 8, -5, 14, -10, 3, -7, 0];
      for (var i = 0; i < offsets.length; i++) {
        tracker.tap(Duration(milliseconds: i * 500 + offsets[i]));
      }
      // First and last tap are exactly on the grid -> exactly 120.
      expect(tracker.bpm, closeTo(120, 1e-9));
    });

    test('recent tempo follows changes faster than the average', () {
      final tracker = TapTracker(recentTaps: 5);
      tapSteadily(tracker, count: 10, intervalMs: 600); // 100 BPM
      tapSteadily(tracker, count: 5, intervalMs: 400, startMs: 9 * 600 + 400); // 150 BPM
      expect(tracker.recentBpm, closeTo(150, 1e-9));
      expect(tracker.bpm, lessThan(120));
    });

    test('tracks the peak of the average', () {
      final tracker = TapTracker();
      tapSteadily(tracker, count: 3, intervalMs: 400); // 150
      tracker.tap(const Duration(milliseconds: 800 + 1000));
      expect(tracker.peakBpm, closeTo(150, 1e-9));
      expect(tracker.bpm, lessThan(150));
    });

    test('ignores taps that come too fast (double touch)', () {
      final tracker = TapTracker(minInterval: const Duration(milliseconds: 100));
      expect(tracker.tap(Duration.zero), isTrue);
      expect(tracker.tap(const Duration(milliseconds: 30)), isFalse);
      expect(tracker.tap(const Duration(milliseconds: 500)), isTrue);
      expect(tracker.taps, 2);
      expect(tracker.bpm, closeTo(120, 1e-9));
    });

    test('reset keeps the session as previous values', () {
      final tracker = TapTracker();
      tapSteadily(tracker, count: 9, intervalMs: 500);
      tracker.reset();
      expect(tracker.taps, 0);
      expect(tracker.bpm, isNull);
      expect(tracker.peakBpm, 0);
      expect(tracker.previousTaps, 9);
      expect(tracker.previousBpm, closeTo(120, 1e-9));
      expect(tracker.previousPeakBpm, closeTo(120, 1e-9));

      // Resetting an empty session keeps the last real one.
      tracker.reset();
      expect(tracker.previousTaps, 9);
    });

    test('a long pause starts a new session automatically', () {
      final tracker = TapTracker(restartAfter: const Duration(seconds: 3));
      tapSteadily(tracker, count: 5, intervalMs: 500);
      expect(tracker.wouldRestart(const Duration(milliseconds: 2000 + 3001)), isTrue);
      expect(tracker.wouldRestart(const Duration(milliseconds: 2000 + 2999)), isFalse);

      tracker.tap(const Duration(seconds: 10));
      expect(tracker.taps, 1);
      expect(tracker.previousTaps, 5);
      expect(tracker.previousBpm, closeTo(120, 1e-9));
      tracker.tap(const Duration(milliseconds: 10750));
      expect(tracker.bpm, closeTo(80, 1e-9));
    });

    test('slow tempos within the restart limit still work', () {
      final tracker = TapTracker(restartAfter: const Duration(seconds: 3));
      tapSteadily(tracker, count: 4, intervalMs: 2000); // 30 BPM
      expect(tracker.taps, 4);
      expect(tracker.bpm, closeTo(30, 1e-9));
    });

    test('a timestamp from the past starts a new session', () {
      final tracker = TapTracker();
      tapSteadily(tracker, count: 4, intervalMs: 500, startMs: 100000);
      expect(tracker.wouldRestart(const Duration(seconds: 1)), isTrue);
      expect(tracker.tap(const Duration(seconds: 1)), isTrue);
      expect(tracker.taps, 1);
      expect(tracker.previousTaps, 4);
      tracker.tap(const Duration(milliseconds: 1500));
      expect(tracker.bpm, closeTo(120, 1e-9));
    });
  });
}
