import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/detector_settings.dart';
import '../audio/listen_controller.dart';
import 'listen_view.dart' show formatHz;
import 'theme.dart';

Future<void> showFilterSheet(BuildContext context, ListenController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => FilterSheet(controller: controller),
  );
}

/// High/low pass, tempo range and noise gate settings. Changes apply
/// immediately, so the effect can be heard (seen) while listening.
class FilterSheet extends StatelessWidget {
  const FilterSheet({super.key, required this.controller});

  final ListenController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.settings;
        void update(DetectorSettings next) => controller.updateSettings(next);
        final theme = Theme.of(context);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Audio filters', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Narrow the sound down to the instrument that carries the beat.',
                style: theme.textTheme.bodyMedium!.copyWith(color: BpmColors.textMuted),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in FilterPreset.values)
                    ChoiceChip(
                      label: Text(preset.label),
                      selected: preset.matches(s),
                      onSelected: (_) => update(preset.applyTo(s)),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _LogSlider(
                key: const Key('high-pass-slider'),
                label: 'High-pass',
                help: 'Removes everything below this frequency',
                value: s.highPassHz,
                min: DetectorSettings.highPassMin,
                max: DetectorSettings.highPassMax,
                offAtMin: true,
                onChanged: (hz) => update(s.copyWith(highPassHz: () => hz)),
              ),
              _LogSlider(
                key: const Key('low-pass-slider'),
                label: 'Low-pass',
                help: 'Removes everything above this frequency',
                value: s.lowPassHz,
                min: DetectorSettings.lowPassMin,
                max: DetectorSettings.lowPassMax,
                offAtMin: false,
                onChanged: (hz) => update(s.copyWith(lowPassHz: () => hz)),
              ),
              const SizedBox(height: 8),
              _SettingHeader(
                label: 'Tempo range',
                value: '${s.minBpm.round()} – ${s.maxBpm.round()} BPM',
                help: 'Narrow it if the result is half or double the real tempo',
              ),
              RangeSlider(
                key: const Key('bpm-range-slider'),
                values: RangeValues(s.minBpm, s.maxBpm),
                min: DetectorSettings.bpmLimitMin,
                max: DetectorSettings.bpmLimitMax,
                divisions: ((DetectorSettings.bpmLimitMax - DetectorSettings.bpmLimitMin) / 5)
                    .round(),
                labels: RangeLabels('${s.minBpm.round()}', '${s.maxBpm.round()}'),
                onChanged: (range) => update(s.copyWith(minBpm: range.start, maxBpm: range.end)),
              ),
              const SizedBox(height: 8),
              _SettingHeader(
                label: 'Noise gate',
                value: '${s.noiseGateDb.round()} dB',
                help: 'Sounds quieter than this are ignored',
              ),
              Slider(
                key: const Key('noise-gate-slider'),
                value: s.noiseGateDb,
                min: DetectorSettings.noiseGateMin,
                max: DetectorSettings.noiseGateMax,
                divisions: (DetectorSettings.noiseGateMax - DetectorSettings.noiseGateMin).round(),
                label: '${s.noiseGateDb.round()} dB',
                onChanged: (db) => update(s.copyWith(noiseGateDb: db)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const Key('reset-filters'),
                  onPressed: s == DetectorSettings.defaults
                      ? null
                      : () => update(DetectorSettings.defaults),
                  icon: const Icon(Icons.settings_backup_restore),
                  label: const Text('Defaults'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingHeader extends StatelessWidget {
  const _SettingHeader({required this.label, required this.value, required this.help});

  final String label;
  final String value;
  final String help;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
            Text(
              value,
              style: theme.textTheme.titleSmall!.copyWith(
                color: BpmColors.green,
                fontFeatures: tabularFigures,
              ),
            ),
          ],
        ),
        Text(help, style: theme.textTheme.bodySmall!.copyWith(color: BpmColors.textMuted)),
      ],
    );
  }
}

/// A frequency slider on a logarithmic scale. One end of the scale means
/// "off": the minimum for a high-pass, the maximum for a low-pass.
class _LogSlider extends StatelessWidget {
  const _LogSlider({
    super.key,
    required this.label,
    required this.help,
    required this.value,
    required this.min,
    required this.max,
    required this.offAtMin,
    required this.onChanged,
  });

  final String label;
  final String help;
  final double? value;
  final double min;
  final double max;
  final bool offAtMin;
  final ValueChanged<double?> onChanged;

  double _toPosition(double hz) => math.log(hz / min) / math.log(max / min);

  double _toHz(double position) {
    final hz = min * math.pow(max / min, position);
    // Round to 2 significant digits: 47 Hz, 150 Hz, 2200 Hz …
    final magnitude = math.pow(10, (math.log(hz) / math.ln10).floor() - 1);
    return (hz / magnitude).round() * magnitude.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final hz = value;
    final position = hz == null ? (offAtMin ? 0.0 : 1.0) : _toPosition(hz).clamp(0.0, 1.0);
    final text = hz == null ? 'Off' : formatHz(hz);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingHeader(label: label, value: text, help: help),
        Slider(
          value: position,
          divisions: 100,
          label: text,
          onChanged: (p) {
            final off = offAtMin ? p <= 0 : p >= 1;
            onChanged(off ? null : _toHz(p).clamp(min, max).toDouble());
          },
        ),
      ],
    );
  }
}
