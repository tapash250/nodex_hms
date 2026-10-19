/// Clinical line chart (Module 49).
///
/// A trend curve for a lab analyte, a vital or a count over time. The chart
/// draws vectors, so it is cheap enough to redraw on every reading, and it
/// says what it is showing to a screen reader rather than leaving the picture
/// to speak for itself.
library;

import 'package:flutter/material.dart';
import 'package:nodex_hms/app/charts/chart_geometry.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';

/// How a label sits against the point it belongs to.
enum _VerticalAlign {
  /// The label hangs below the anchor.
  top,

  /// The label is centred on the anchor.
  middle,

  /// The label ends at the anchor.
  bottom,
}

/// One line of a chart.
@immutable
final class ChartSeries {
  /// Declares a series.
  const ChartSeries({
    required this.label,
    required this.points,
    this.tone = ClinicalTone.info,
  });

  /// What the series measures.
  final String label;

  /// The points, in the order they were recorded.
  final List<ChartPoint> points;

  /// How the series is coloured.
  final ClinicalTone tone;
}

/// A trend chart.
class ClinicalLineChart extends StatelessWidget {
  /// Creates a chart.
  const ClinicalLineChart({
    required this.series,
    this.height = 168,
    this.yTickCount = 4,
    this.bands = const <ChartBand>[],
    this.showGrid = true,
    this.fill = true,
    this.unit,
    this.yLabelBuilder,
    this.xLabelBuilder,
    super.key,
  });

  /// The lines to draw.
  final List<ChartSeries> series;

  /// Height of the chart.
  final double height;

  /// How many horizontal grid lines to draw.
  final int yTickCount;

  /// Shaded ranges on the value axis.
  final List<ChartBand> bands;

  /// Whether to draw the grid.
  final bool showGrid;

  /// Whether to shade under a single series.
  final bool fill;

  /// Unit of measure, stated in the accessibility summary.
  final String? unit;

  /// Formats a value for the vertical axis.
  final String Function(num value)? yLabelBuilder;

  /// Formats a position for the horizontal axis.
  final String Function(ChartPoint point)? xLabelBuilder;

  /// The value axis, derived from the series and the bands.
  ChartScale get valueScale {
    final List<num> values = <num>[
      for (final ChartSeries line in series)
        for (final ChartPoint point in line.points) point.y,
      for (final ChartBand band in bands) ...<num>[band.from, band.to],
    ];
    return ChartScale.covering(values);
  }

  /// The sentence a screen reader reads instead of the drawing.
  String get semanticSummary {
    if (series.isEmpty) return 'No chart data';
    final String unitPart = unit == null ? '' : ' $unit';
    return series
        .map(
          (ChartSeries line) => line.points.isEmpty
              ? '${line.label}: no readings'
              : '${line.label}: ${line.points.length} readings, latest '
                    '${_trim(line.points.last.y)}$unitPart',
        )
        .join('; ');
  }

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ChartScale scale = valueScale;

    return Semantics(
      label: semanticSummary,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: ClinicalLineChartPainter(
            series: series,
            valueScale: scale,
            bands: bands,
            showGrid: showGrid,
            yTickCount: yTickCount,
            fill: fill,
            scheme: scheme,
            yLabelBuilder: yLabelBuilder,
            xLabelBuilder: xLabelBuilder,
          ),
        ),
      ),
    );
  }
}

/// Draws a trend chart.
class ClinicalLineChartPainter extends CustomPainter {
  /// Creates the painter.
  const ClinicalLineChartPainter({
    required this.series,
    required this.valueScale,
    required this.scheme,
    this.bands = const <ChartBand>[],
    this.showGrid = true,
    this.yTickCount = 4,
    this.fill = true,
    this.yLabelBuilder,
    this.xLabelBuilder,
  });

  /// The lines to draw.
  final List<ChartSeries> series;

  /// The value axis.
  final ChartScale valueScale;

  /// Shaded ranges.
  final List<ChartBand> bands;

  /// Whether to draw the grid.
  final bool showGrid;

  /// How many horizontal grid lines to draw.
  final int yTickCount;

  /// Whether to shade under a single series.
  final bool fill;

  /// Theme colours.
  final ColorScheme scheme;

  /// Formats a value for the vertical axis.
  final String Function(num value)? yLabelBuilder;

  /// Formats a position for the horizontal axis.
  final String Function(ChartPoint point)? xLabelBuilder;

  /// Gutter reserved for the value labels.
  static const double leftGutter = 46;

  /// Gutter reserved for the horizontal labels.
  static const double bottomGutter = 20;

  /// Space above the plot.
  static const double topPadding = 10;

  /// Space to the right of the plot.
  static const double rightPadding = 10;

  /// The area the series are drawn in.
  static Rect plotRectFor(Size size) => Rect.fromLTRB(
    leftGutter,
    topPadding,
    size.width - rightPadding,
    size.height - bottomGutter,
  );

  /// Where each point of a series lands on the canvas.
  ///
  /// Exposed so the geometry can be checked without a screen: a chart that
  /// puts its highest point at the bottom is wrong in a way a picture hides.
  ///
  /// A single point has no place on the axis — there is nothing to compare it
  /// with — so it is drawn in the middle of the plot rather than at an edge
  /// that would imply a position it does not have.
  static List<Offset> projectPoints({
    required List<ChartPoint> points,
    required Rect plot,
    required ChartScale valueScale,
    required double xMin,
    required double xMax,
  }) {
    if (points.isEmpty) return const <Offset>[];
    final double xSpan = xMax - xMin;
    final bool single = points.length == 1;
    return <Offset>[
      for (final ChartPoint point in points)
        Offset(
          single
              ? plot.center.dx
              : xSpan == 0
              ? plot.center.dx
              : plot.left + (point.x - xMin) / xSpan * plot.width,
          plot.bottom - valueScale.fraction(point.y) * plot.height,
        ),
    ];
  }

  /// The horizontal extent of a set of points.
  static (double, double) xExtentOf(Iterable<ChartPoint> points) {
    if (points.isEmpty) return (0, 1);
    double low = double.infinity;
    double high = double.negativeInfinity;
    for (final ChartPoint point in points) {
      if (point.x < low) low = point.x;
      if (point.x > high) high = point.x;
    }
    if (low == high) high = low + 1;
    return (low, high);
  }

  String _formatValue(num value) =>
      yLabelBuilder?.call(value) ??
      (value == value.roundToDouble()
          ? value.toInt().toString()
          : value.toStringAsFixed(1));

  @override
  void paint(Canvas canvas, Size size) {
    final Rect plot = plotRectFor(size);
    if (plot.width <= 0 || plot.height <= 0) return;

    final Paint grid = Paint()
      ..color = scheme.outlineVariant.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    final Paint axis = Paint()
      ..color = scheme.outline.withValues(alpha: 0.8)
      ..strokeWidth = 1;

    if (showGrid) {
      for (int i = 0; i <= yTickCount; i++) {
        final double fraction = i / yTickCount;
        final double y = plot.bottom - fraction * plot.height;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
        final num value = valueScale.min + fraction * valueScale.span;
        _text(
          canvas,
          _formatValue(value),
          Offset(plot.left - 6, y),
          align: TextAlign.right,
          vertical: _VerticalAlign.middle,
          color: scheme.onSurfaceVariant,
        );
      }
    }

    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      axis,
    );

    // Reference bands sit under the grid so a point inside a band still reads
    // as a point.
    for (final ChartBand band in bands) {
      final double top =
          plot.bottom - valueScale.fraction(band.to) * plot.height;
      final double bottom =
          plot.bottom - valueScale.fraction(band.from) * plot.height;
      canvas.drawRect(
        Rect.fromLTRB(plot.left, top, plot.right, bottom),
        Paint()..color = scheme.secondaryContainer.withValues(alpha: 0.45),
      );
    }

    double xMin = double.infinity;
    double xMax = double.negativeInfinity;
    for (final ChartSeries line in series) {
      for (final ChartPoint point in line.points) {
        if (point.x < xMin) xMin = point.x;
        if (point.x > xMax) xMax = point.x;
      }
    }
    if (xMin == double.infinity) {
      xMin = 0;
      xMax = 1;
    }
    if (xMin == xMax) xMax = xMin + 1;

    for (final ChartSeries line in series) {
      if (line.points.isEmpty) continue;
      final List<Offset> offsets = projectPoints(
        points: line.points,
        plot: plot,
        valueScale: valueScale,
        xMin: xMin,
        xMax: xMax,
      );
      final Color colour = line.tone.foreground(scheme);
      final Path path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (int i = 1; i < offsets.length; i++) {
        path.lineTo(offsets[i].dx, offsets[i].dy);
      }
      if (fill && series.length == 1) {
        final Path area = Path.from(path)
          ..lineTo(offsets.last.dx, plot.bottom)
          ..lineTo(offsets.first.dx, plot.bottom)
          ..close();
        canvas.drawPath(
          area,
          Paint()..color = line.tone.background(scheme).withValues(alpha: 0.6),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      final Offset last = offsets.last;
      canvas.drawCircle(last, 3.2, Paint()..color = colour);
    }

    // The horizontal axis carries the first and the last reading, because a
    // label for every point is noise at phone width.
    final List<ChartPoint> allPoints = <ChartPoint>[
      for (final ChartSeries line in series) ...line.points,
    ];
    if (allPoints.isNotEmpty) {
      final ChartPoint first = allPoints.first;
      final ChartPoint last = allPoints.last;
      _text(
        canvas,
        xLabelBuilder?.call(first) ?? first.label ?? '',
        Offset(plot.left, plot.bottom + 4),
        color: scheme.onSurfaceVariant,
      );
      if (allPoints.length > 1) {
        _text(
          canvas,
          xLabelBuilder?.call(last) ?? last.label ?? '',
          Offset(plot.right, plot.bottom + 4),
          align: TextAlign.right,
          color: scheme.onSurfaceVariant,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at, {
    TextAlign align = TextAlign.left,
    _VerticalAlign vertical = _VerticalAlign.top,
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
    final double dy = switch (vertical) {
      _VerticalAlign.middle => at.dy - painter.height / 2,
      _VerticalAlign.bottom => at.dy - painter.height,
      _VerticalAlign.top => at.dy,
    };
    painter.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(ClinicalLineChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.valueScale.min != valueScale.min ||
      oldDelegate.valueScale.max != valueScale.max ||
      oldDelegate.bands != bands ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.fill != fill ||
      oldDelegate.scheme != scheme;
}
