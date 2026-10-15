import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../audio/detector_settings.dart';
import '../audio/listen_controller.dart';
import 'filter_sheet.dart';
import 'theme.dart';
import 'widgets.dart';

/// Automatic mode: detects the tempo from the microphone.
class ListenView extends StatefulWidget {
  const ListenView({super.key, required this.controller});

  final ListenController controller;

  @override
  State<ListenView> createState() => _ListenViewState();
}

class _ListenViewState extends State<ListenView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Never keep capturing in the background. While starting, a system
    // dialog (permission, screen capture consent) may be in front.
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (widget.controller.status != ListenStatus.starting) widget.controller.stop();
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _buildContent(context, widget.controller),
    );
  }

  Widget _buildContent(BuildContext context, ListenController c) {
    final theme = Theme.of(context);
    final listening = c.isListening;

    final info = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.phoneAudioAvailable) _SourceSelector(controller: c) else const SizedBox(height: 8),
        BpmReadout(bpm: c.bpm, caption: _caption(c), dimmed: !listening || c.confidence < 0.2),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 56,
                  child: CustomPaint(
                    key: const Key('envelope-graph'),
                    painter: EnvelopePainter(listening ? c.envelope : null),
                  ),
                ),
                const SizedBox(height: 10),
                LevelMeter(levelDb: listening ? c.levelDb : null, gateDb: c.settings.noiseGateDb),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                describeFilter(c.settings),
                key: const Key('filter-summary'),
                style: theme.textTheme.bodySmall!.copyWith(color: BpmColors.textMuted),
              ),
            ),
            FilledButton.tonalIcon(
              key: const Key('open-filters'),
              onPressed: () => showFilterSheet(context, c),
              icon: const Icon(Icons.tune),
              label: const Text('Filters'),
            ),
          ],
        ),
      ],
    );

    final pad = Semantics(
      button: true,
      label: listening ? 'Stop listening' : 'Start listening',
      excludeSemantics: true,
      onTap: c.toggle,
      child: GestureDetector(
        key: const Key('listen-pad'),
        behavior: HitTestBehavior.opaque,
        onTap: c.toggle,
        child: PulseCircle(
          pulse: c.beats,
          active: listening,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                c.source == AudioSource.phoneAudio
                    ? Icons.graphic_eq
                    : (listening ? Icons.mic : Icons.mic_none),
                size: 40,
                color: BpmColors.green,
              ),
              const SizedBox(height: 8),
              Text(
                listening || c.status == ListenStatus.starting ? 'STOP' : 'LISTEN',
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
    );

    return AdaptiveSplit(info: info, pad: pad);
  }

  String _caption(ListenController c) {
    final phone = c.source == AudioSource.phoneAudio;
    switch (c.status) {
      case ListenStatus.idle:
        return phone
            ? 'Play music in any app, then tap the circle'
            : 'Tap the circle to start listening';
      case ListenStatus.starting:
        return phone ? 'Waiting for permission to capture…' : 'Starting microphone…';
      case ListenStatus.permissionDenied:
        return 'Microphone access was denied. Allow it under Settings › Apps › '
            'BPM Counter › Permissions, or use the tap mode.';
      case ListenStatus.error:
        return phone
            ? 'Phone audio could not be captured (${c.errorMessage}).'
            : 'The microphone could not be used (${c.errorMessage}).';
      case ListenStatus.listening:
        if (c.warmUp < 1) return 'Listening… ${(c.warmUp * 100).round()} %';
        if (phone && !(c.levelDb > LevelMeter.floorDb)) {
          return 'No sound – nothing playing, or the app blocks capture (see ?)';
        }
        if (c.bpm == null) return 'No clear beat yet – try other filters';
        return 'Confidence ${(c.confidence * 100).round()} %';
    }
  }
}

/// Microphone / phone audio switch with a help button for the limitations.
class _SourceSelector extends StatelessWidget {
  const _SourceSelector({required this.controller});

  final ListenController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Icons only where there is room (not on very small phones).
                final icons = constraints.maxWidth >= 300;
                return SegmentedButton<AudioSource>(
                  key: const Key('source-selector'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [
                    ButtonSegment(
                      value: AudioSource.microphone,
                      icon: icons ? const Icon(Icons.mic_none, size: 18) : null,
                      label: const Text('Microphone', maxLines: 1, softWrap: false),
                    ),
                    ButtonSegment(
                      value: AudioSource.phoneAudio,
                      icon: icons ? const Icon(Icons.graphic_eq, size: 18) : null,
                      label: const Text('Phone audio', maxLines: 1, softWrap: false),
                    ),
                  ],
                  selected: {controller.source},
                  onSelectionChanged: (selection) => controller.setSource(selection.first),
                );
              },
            ),
          ),
          IconButton(
            key: const Key('source-help'),
            tooltip: 'About phone audio',
            icon: const Icon(Icons.help_outline),
            color: BpmColors.textMuted,
            onPressed: () => showPhoneAudioHelp(context),
          ),
        ],
      ),
    );
  }
}

Future<void> showPhoneAudioHelp(BuildContext context) {
  final theme = Theme.of(context);
  Widget point(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 7, right: 10),
          child: Icon(Icons.circle, size: 6, color: BpmColors.green),
        ),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    ),
  );
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: BpmColors.surfaceHigh,
      title: const Text('Phone audio'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            point('Analyses what other apps play – no room noise, works with headphones.'),
            point(
              'Android asks to allow screen recording each time. Only the sound is '
              'analysed; nothing is stored or sent.',
            ),
            point(
              'Some apps, often streaming apps with copy protection, block this. '
              'The level then stays empty – use the microphone.',
            ),
            point(
              'Capturing stops when you leave BPM Counter: start the music first, '
              'then come back.',
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ),
  );
}

/// Human-readable summary of the filter band, e.g. "Kick & bass · below 200 Hz".
String describeFilter(DetectorSettings s) {
  final hp = s.highPassHz, lp = s.lowPassHz;
  final band = switch ((hp, lp)) {
    (null, null) => 'all frequencies',
    (final h?, null) => 'above ${formatHz(h)}',
    (null, final l?) => 'below ${formatHz(l)}',
    (final h?, final l?) => '${formatHz(h)} – ${formatHz(l)}',
  };
  final preset = FilterPreset.values.where((p) => p.matches(s)).firstOrNull;
  final range = '${s.minBpm.round()}–${s.maxBpm.round()} BPM';
  return [if (preset != null) preset.label, band, range].join(' · ');
}

String formatHz(double hz) =>
    hz < 1000 ? '${hz.round()} Hz' : '${(hz / 1000).toStringAsFixed(hz < 10000 ? 1 : 0)} kHz';

/// Scrolling graph of the onset envelope: every spike is a detected hit.
class EnvelopePainter extends CustomPainter {
  EnvelopePainter(this.envelope);

  final Float64List? envelope;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = Paint()
      ..color = BpmColors.outline
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), baseline);
    final values = envelope;
    if (values == null || values.isEmpty) return;

    var peak = 6.0; // dB; keeps quiet noise from filling the graph
    for (final v in values) {
      peak = math.max(peak, v);
    }
    final path = Path()..moveTo(0, size.height);
    final step = size.width / (values.length - 1);
    for (var i = 0; i < values.length; i++) {
      path.lineTo(i * step, size.height * (1 - values[i] / peak));
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [BpmColors.greenBright, BpmColors.green.withValues(alpha: 0.15)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(EnvelopePainter old) => true;
}

/// Input level of the filtered signal with a marker for the noise gate.
class LevelMeter extends StatelessWidget {
  const LevelMeter({super.key, required this.levelDb, required this.gateDb});

  static const floorDb = -90.0;

  final double? levelDb;
  final double gateDb;

  @override
  Widget build(BuildContext context) {
    double fraction(double db) => ((db - floorDb) / -floorDb).clamp(0.0, 1.0);
    final level = levelDb;
    final theme = Theme.of(context);
    return Row(
      children: [
        Text('Level', style: theme.textTheme.labelSmall!.copyWith(color: BpmColors.textMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: BpmColors.surfaceHigh,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    if (level != null && level.isFinite)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        width: width * fraction(level),
                        decoration: BoxDecoration(
                          color: level < gateDb ? BpmColors.textMuted : BpmColors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    Positioned(
                      left: width * fraction(gateDb) - 1,
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.white70),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 56,
          child: Text(
            level == null || !level.isFinite ? '– dB' : '${level.round()} dB',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall!.copyWith(
              color: BpmColors.textMuted,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ],
    );
  }
}
