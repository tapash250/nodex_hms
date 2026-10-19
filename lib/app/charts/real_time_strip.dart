/// Real-time vital strip (Module 49).
///
/// A monitor strip: the last few seconds of a signal, drawn as it arrives.
/// The widget is stateless on purpose — the caller owns the samples — so a
/// monitor can push a new reading by rebuilding one small widget rather than
/// by driving a painter from a timer inside the view.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';

/// A scrolling strip of samples.
class RealTimeStrip extends StatelessWidget {
  /// Creates a strip.
  const RealTimeStrip({
    required this.samples,
    this.height = 56,
    this.window = 120,
    this.tone = ClinicalTone.info,
    this.label,
    this.unit,
    super.key,
  });

  /// The samples, oldest first.
  final List<double> samples;

  /// Height of the strip.
  final double height;

  /// How many of the most recent samples the strip shows.
  final int window;

  /// Colour family of the trace.
  final ClinicalTone tone;

  /// What the signal measures, used for the accessibility label.
  final String? label;

  /// Unit of measure.
  final String? unit;

  /// The samples the strip currently shows.
  List<double> get windowed => samples.length <= window
      ? samples
      : samples.sublist(samples.length - window);

  /// The sentence a screen reader reads instead of the trace.
  String get semanticLabel {
    final String subject = label ?? 'Signal';
    final List<double> shown = windowed;
    if (shown.isEmpty) return '$subject: no samples';
    final String unitPart = unit == null ? '' : ' $unit';
    return '$subject: ${shown.length} samples, latest '
        '${shown.last.toStringAsFixed(0)}$unitPart';
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: RealTimeStripPainter(
            samples: windowed,
            colour: tone.foreground(scheme),
            background: tone.background(scheme).withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// Draws a scrolling strip of samples.
class RealTimeStripPainter extends CustomPainter {
  /// Creates the painter.
  const RealTimeStripPainter({
    required this.samples,
    required this.colour,
    required this.background,
  });

  /// The samples to draw, oldest first.
  final List<double> samples;

  /// Colour of the trace.
  final Color colour;

  /// Colour behind the trace.
  final Color background;

  /// Where each sample sits on the canvas.
  ///
  /// Exposed so the geometry can be checked without a screen: the newest
  /// sample belongs at the right-hand edge, because that is where a monitor
  /// puts it.
  static List<Offset> projectSamples({
    required List<double> samples,
    required Size size,
  }) {
    if (samples.isEmpty) return const <Offset>[];
    double low = samples.first;
    double high = samples.first;
    for (final double sample in samples) {
      if (sample < low) low = sample;
      if (sample > high) high = sample;
    }
    final double span = high - low;
    final double step = samples.length == 1
        ? 0
        : size.width / (samples.length - 1);
    return <Offset>[
      for (int i = 0; i < samples.length; i++)
        Offset(
          samples.length == 1 ? size.width : step * i,
          span == 0
              ? size.height / 2
              : size.height - ((samples[i] - low) / span) * size.height,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final List<Offset> offsets = projectSamples(samples: samples, size: size);
    if (offsets.isEmpty) return;
    final Path path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (int i = 1; i < offsets.length; i++) {
      path.lineTo(offsets[i].dx, offsets[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(RealTimeStripPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.colour != colour ||
      oldDelegate.background != background;
}
