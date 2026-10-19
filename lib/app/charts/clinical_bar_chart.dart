/// Clinical bar chart (Module 49).
///
/// Counts against a limit: beds per ward, specimens per bench, cases per
/// clinic. A bar that passes its limit is marked rather than left for the
/// reader to compare against an axis, because the number that matters in an
/// occupancy graph is the one that broke the capacity.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';

/// One bar of a chart.
@immutable
final class ChartBar {
  /// Declares a bar.
  const ChartBar({
    required this.label,
    required this.value,
    this.tone = ClinicalTone.info,
    this.caption,
  });

  /// What the bar counts.
  final String label;

  /// The count.
  final double value;

  /// How the bar is coloured.
  final ClinicalTone tone;

  /// Optional caption under the label.
  final String? caption;
}

/// A bar chart.
class ClinicalBarChart extends StatelessWidget {
  /// Creates a chart.
  const ClinicalBarChart({
    required this.bars,
    this.height = 168,
    this.threshold,
    this.thresholdLabel,
    this.showValues = true,
    this.valueLabelBuilder,
    super.key,
  });

  /// The bars to draw.
  final List<ChartBar> bars;

  /// Height of the chart.
  final double height;

  /// The limit a bar is measured against.
  final double? threshold;

  /// Caption for the limit.
  final String? thresholdLabel;

  /// Whether to print the value above each bar.
  final bool showValues;

  /// Formats a value for display.
  final String Function(num value)? valueLabelBuilder;

  /// The sentence a screen reader reads instead of the drawing.
  String get semanticSummary {
    if (bars.isEmpty) return 'No chart data';
    final String limit = threshold == null
        ? ''
        : ', limit ${_format(threshold!)}';
    return bars
        .map(
          (ChartBar bar) =>
              '${bar.label}: ${_format(bar.value)}$limit'
              '${threshold != null && bar.value > threshold! ? ', over limit' : ''}',
        )
        .join('; ');
  }

  String _format(num value) =>
      valueLabelBuilder?.call(value) ??
      (value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(1));

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: semanticSummary,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: ClinicalBarChartPainter(
            bars: bars,
            threshold: threshold,
            showValues: showValues,
            scheme: theme.colorScheme,
            valueLabelBuilder: valueLabelBuilder,
          ),
        ),
      ),
    );
  }
}

/// Draws a bar chart.
class ClinicalBarChartPainter extends CustomPainter {
  /// Creates the painter.
  const ClinicalBarChartPainter({
    required this.bars,
    required this.scheme,
    this.threshold,
    this.showValues = true,
    this.valueLabelBuilder,
  });

  /// The bars to draw.
  final List<ChartBar> bars;

  /// The limit a bar is measured against.
  final double? threshold;

  /// Whether to print the value above each bar.
  final bool showValues;

  /// Theme colours.
  final ColorScheme scheme;

  /// Formats a value for display.
  final String Function(num value)? valueLabelBuilder;

  /// Gutter reserved for the labels under the bars.
  static const double bottomGutter = 26;

  /// Space above the tallest bar.
  static const double topPadding = 16;

  /// The area the bars are drawn in.
  static Rect plotRectFor(Size size) =>
      Rect.fromLTRB(0, topPadding, size.width, size.height - bottomGutter);

  /// Where each bar sits.
  ///
  /// Exposed so the geometry can be checked without a screen.
  static List<Rect> barRects({
    required List<ChartBar> bars,
    required Rect plot,
    required double maxValue,
  }) {
    if (bars.isEmpty) return const <Rect>[];
    final double slot = plot.width / bars.length;
    final double barWidth = slot * 0.62;
    return <Rect>[
      for (int i = 0; i < bars.length; i++)
        Rect.fromLTWH(
          plot.left + slot * i + (slot - barWidth) / 2,
          maxValue <= 0
              ? plot.bottom
              : plot.bottom - (bars[i].value / maxValue) * plot.height,
          barWidth,
          maxValue <= 0 ? 0 : (bars[i].value / maxValue) * plot.height,
        ),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final Rect plot = plotRectFor(size);
    if (plot.width <= 0 || plot.height <= 0) return;

    final double limit = threshold ?? 0;
    double maxValue = limit;
    for (final ChartBar bar in bars) {
      if (bar.value > maxValue) maxValue = bar.value;
    }
    if (maxValue <= 0) maxValue = 1;

    final Paint axis = Paint()
      ..color = scheme.outline.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      axis,
    );

    if (threshold != null) {
      final double y = plot.bottom - (limit / maxValue) * plot.height;
      final Paint limitPaint = Paint()
        ..color = scheme.error.withValues(alpha: 0.7)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), limitPaint);
    }

    final List<Rect> rects = barRects(
      bars: bars,
      plot: plot,
      maxValue: maxValue,
    );
    for (int i = 0; i < bars.length; i++) {
      final ChartBar bar = bars[i];
      final bool over = threshold != null && bar.value > threshold!;
      final Color colour = over ? scheme.error : bar.tone.foreground(scheme);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rects[i], const Radius.circular(4)),
        Paint()..color = colour,
      );
      if (showValues) {
        _text(
          canvas,
          _format(bar.value),
          Offset(rects[i].center.dx, rects[i].top - 13),
          align: TextAlign.center,
        );
      }
      _text(
        canvas,
        bar.label,
        Offset(rects[i].center.dx, plot.bottom + 4),
        align: TextAlign.center,
        color: scheme.onSurfaceVariant,
      );
      if (bar.caption != null) {
        _text(
          canvas,
          bar.caption!,
          Offset(rects[i].center.dx, plot.bottom + 15),
          align: TextAlign.center,
          color: scheme.onSurfaceVariant,
        );
      }
    }
  }

  String _format(num value) =>
      valueLabelBuilder?.call(value) ??
      (value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(1));

  void _text(
    Canvas canvas,
    String value,
    Offset at, {
    TextAlign align = TextAlign.left,
    Color? color,
  }) {
    if (value.isEmpty) return;
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(fontSize: 10, color: color ?? scheme.onSurface),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    final double dx = switch (align) {
      TextAlign.right => at.dx - painter.width,
      TextAlign.center => at.dx - painter.width / 2,
      _ => at.dx,
    };
    painter.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(ClinicalBarChartPainter oldDelegate) =>
      oldDelegate.bars != bars ||
      oldDelegate.threshold != threshold ||
      oldDelegate.showValues != showValues ||
      oldDelegate.scheme != scheme;
}
