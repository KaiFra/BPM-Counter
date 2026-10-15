import 'package:flutter/material.dart';

import 'theme.dart';

/// Formats a tempo for display: one decimal, or a dash when unknown.
String formatBpm(double? bpm) => bpm == null ? '–' : bpm.toStringAsFixed(1);

/// The large tempo number.
class BpmReadout extends StatelessWidget {
  const BpmReadout({super.key, required this.bpm, this.caption, this.dimmed = false});

  final double? bpm;
  final String? caption;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = dimmed ? BpmColors.textMuted : Colors.white;
    return Semantics(
      liveRegion: true,
      label: bpm == null ? 'No tempo yet' : '${formatBpm(bpm)} beats per minute',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: theme.textTheme.displayLarge!.copyWith(
                    fontSize: CompactLayout.of(context) ? 68 : 88,
                    fontWeight: FontWeight.w300,
                    height: 1,
                    color: color,
                    fontFeatures: tabularFigures,
                  ),
                  child: Text(formatBpm(bpm), key: const Key('bpm-value')),
                ),
                const SizedBox(width: 8),
                Text(
                  'BPM',
                  style: theme.textTheme.titleLarge!.copyWith(
                    color: BpmColors.green,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            // Always two lines high, so a changing caption never moves the
            // rest of the page.
            SizedBox(
              height: _captionHeight(context, theme.textTheme.bodyMedium!),
              child: Text(
                caption!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium!.copyWith(color: BpmColors.textMuted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

double _captionHeight(BuildContext context, TextStyle style) {
  final fontSize = MediaQuery.textScalerOf(context).scale(style.fontSize ?? 14);
  return 2 * fontSize * (style.height ?? 1.45) + 2;
}

/// A small labelled value, e.g. "Taps 12".
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.footnote});

  final String label;
  final String value;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall!.copyWith(
                color: BpmColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: theme.textTheme.titleLarge!.copyWith(fontFeatures: tabularFigures),
              ),
            ),
            if (footnote != null)
              Text(
                footnote!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall!.copyWith(color: BpmColors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// The big round pad. Flashes and ripples whenever [pulse] changes.
class PulseCircle extends StatefulWidget {
  const PulseCircle({super.key, required this.pulse, required this.child, this.active = true});

  /// Change this value to trigger a pulse.
  final int pulse;
  final Widget child;

  /// Inactive circles are drawn dimmer.
  final bool active;

  @override
  State<PulseCircle> createState() => _PulseCircleState();
}

class _PulseCircleState extends State<PulseCircle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: 1,
  );

  @override
  void didUpdateWidget(PulseCircle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse != oldWidget.pulse) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          painter: _PulsePainter(
            progress: Curves.easeOutCubic.transform(_controller.value),
            active: widget.active,
          ),
          child: child,
        ),
        child: Center(child: widget.child),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.progress, required this.active});

  final double progress;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final flash = 1 - progress;
    final strength = active ? 1.0 : 0.5;

    // Expanding ring.
    if (progress < 1) {
      canvas.drawCircle(
        center,
        radius * (0.78 + 0.22 * progress),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = BpmColors.green.withValues(alpha: 0.6 * flash),
      );
    }
    // Pad body with a soft glow towards the edge.
    final body = radius * 0.78;
    canvas.drawCircle(
      center,
      body,
      Paint()
        ..shader = RadialGradient(
          colors: [
            BpmColors.green.withValues(alpha: (0.10 + 0.25 * flash) * strength),
            BpmColors.green.withValues(alpha: (0.22 + 0.35 * flash) * strength),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: body)),
    );
    canvas.drawCircle(
      center,
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = BpmColors.green.withValues(alpha: (0.5 + 0.5 * flash) * strength),
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.progress != progress || old.active != active;
}

/// Whether the page is short and the content should use its compact sizes
/// (smaller numbers, tighter spacing). Set by [AdaptiveSplit].
class CompactLayout extends InheritedWidget {
  const CompactLayout({super.key, required this.compact, required super.child});

  final bool compact;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CompactLayout>()?.compact ?? false;

  @override
  bool updateShouldNotify(CompactLayout old) => old.compact != compact;
}

/// Lays out [info] and [pad] as one page that never scrolls: in a column on
/// portrait screens and side by side on wide ones (landscape phones,
/// tablets, foldables, desktop windows).
///
/// The info keeps its natural size and the round pad takes the space that
/// is left. Only if the info alone would not fit (tiny screens, very large
/// text) it is scaled down instead of scrolling.
class AdaptiveSplit extends StatelessWidget {
  const AdaptiveSplit({super.key, required this.info, required this.pad});

  final Widget info;
  final Widget pad;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > constraints.maxHeight * 1.1;
        final horizontal = constraints.maxWidth > 600 ? 32.0 : 16.0;
        final compact = wide ? constraints.maxHeight < 480 : constraints.maxHeight < 720;
        final padding = EdgeInsets.symmetric(horizontal: horizontal, vertical: compact ? 8 : 12);

        Widget fitted(double width) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: info),
        );

        final Widget content;
        if (wide) {
          final columnWidth = (constraints.maxWidth - 2 * horizontal - 24) / 2;
          content = Row(
            children: [
              Expanded(child: Center(child: fitted(columnWidth))),
              const SizedBox(width: 24),
              Expanded(child: Center(child: pad)),
            ],
          );
        } else {
          content = Column(
            children: [
              // At most 60 % for the info, so the pad always stays usable.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.6),
                child: fitted(constraints.maxWidth - 2 * horizontal),
              ),
              SizedBox(height: compact ? 8 : 12),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: pad,
                  ),
                ),
              ),
            ],
          );
        }
        return CompactLayout(
          compact: compact,
          child: Padding(padding: padding, child: content),
        );
      },
    );
  }
}

/// Vertical space that shrinks in a [CompactLayout].
class AdaptiveGap extends StatelessWidget {
  const AdaptiveGap(this.regular, {super.key, required this.compact});

  final double regular;
  final double compact;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: CompactLayout.of(context) ? compact : regular);
}
