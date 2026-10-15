import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tap/tap_tracker.dart';
import 'theme.dart';
import 'widgets.dart';

/// Manual mode: tap the pad (or press space/enter) along with the music.
class TapView extends StatefulWidget {
  const TapView({super.key});

  @override
  State<TapView> createState() => _TapViewState();
}

class _TapViewState extends State<TapView> {
  final TapTracker _tracker = TapTracker();
  final FocusNode _focusNode = FocusNode(debugLabel: 'tap pad');
  int _pulse = 0;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _tap(Duration timeStamp) {
    if (_tracker.tap(timeStamp)) {
      HapticFeedback.selectionClick();
      setState(() => _pulse++);
    }
  }

  void _reset() => setState(_tracker.reset);

  /// Time for taps without a precise event timestamp (keyboard, screen
  /// reader). Touches use the timestamp of the touch event instead. Mixing
  /// both in one session just starts a new session (see [TapTracker.tap]).
  Duration _now() => Duration(microseconds: clock.now().microsecondsSinceEpoch);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      _tap(_now());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.backspace) {
      _reset();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _caption => switch (_tracker.taps) {
    0 => 'Tap the circle along with the beat',
    1 => 'Keep tapping…',
    _ => 'Pause for ${_tracker.restartAfter.inSeconds} s to start over',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AdaptiveGap(8, compact: 0),
        BpmReadout(bpm: _tracker.bpm, caption: _caption, dimmed: _tracker.taps < 2),
        const AdaptiveGap(20, compact: 10),
        Row(
          children: [
            Expanded(
              child: StatTile(label: 'Taps', value: '${_tracker.taps}'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(label: 'Recent', value: formatBpm(_tracker.recentBpm)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: StatTile(
                label: 'Peak',
                value: _tracker.taps < 2 ? '–' : formatBpm(_tracker.peakBpm),
              ),
            ),
          ],
        ),
        const AdaptiveGap(8, compact: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                _tracker.previousTaps == 0
                    ? 'No previous session'
                    : 'Previous: ${formatBpm(_tracker.previousBpm)} BPM · '
                          '${_tracker.previousTaps} taps · '
                          'peak ${formatBpm(_tracker.previousPeakBpm)}',
                key: const Key('previous-session'),
                style: theme.textTheme.bodySmall!.copyWith(
                  color: BpmColors.textMuted,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _tracker.taps == 0 ? null : _reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
          ],
        ),
      ],
    );

    final pad = Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Semantics(
        button: true,
        label: 'Tap pad',
        hint: 'Tap along with the beat',
        onTap: () => _tap(_now()),
        child: Listener(
          key: const Key('tap-pad'),
          behavior: HitTestBehavior.opaque,
          // React on touch-down (not release) for the most precise timing.
          onPointerDown: (event) => _tap(event.timeStamp),
          child: PulseCircle(
            pulse: _pulse,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app_outlined, size: 40, color: BpmColors.green),
                const SizedBox(height: 8),
                Text(
                  'TAP',
                  style: theme.textTheme.titleMedium!.copyWith(
                    color: BpmColors.green,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return AdaptiveSplit(info: info, pad: pad);
  }
}
