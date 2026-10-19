/// Tests for the chart engine (Module 49).
///
/// The engine draws vectors, so the tests are about the geometry and the
/// sentences rather than about pixels: where a value lands, what the chart
/// says about it, and what a screen reader is told instead of the drawing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/charts/chart_geometry.dart';
import 'package:nodex_hms/app/charts/clinical_bar_chart.dart';
import 'package:nodex_hms/app/charts/clinical_line_chart.dart';
import 'package:nodex_hms/app/charts/real_time_strip.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 300, child: child)),
);

void main() {
  group('the scale', () {
    test('places a value between the ends of the scale', () {
      const ChartScale scale = ChartScale(min: 0, max: 100);
      expect(scale.fraction(0), 0);
      expect(scale.fraction(50), 0.5);
      expect(scale.fraction(100), 1);
    });

    test('clamps a value outside the scale', () {
      const ChartScale scale = ChartScale(min: 10, max: 20);
      expect(scale.fraction(0), 0);
      expect(scale.fraction(30), 1);
    });

    test('answers the middle when the ends are the same value', () {
      const ChartScale scale = ChartScale(min: 5, max: 5);
      expect(scale.fraction(5), 0.5);
    });

    test('covers a series with a little air above and below', () {
      final ChartScale scale = ChartScale.covering(<num>[10, 20]);
      expect(scale.min, lessThan(10));
      expect(scale.max, greaterThan(20));
    });

    test('gives a flat series a range to sit in', () {
      final ChartScale scale = ChartScale.covering(<num>[7, 7, 7]);
      expect(scale.max, greaterThan(scale.min));
      expect(scale.fraction(7), 0.5);
    });

    test('an empty series still has a scale', () {
      final ChartScale scale = ChartScale.covering(<num>[]);
      expect(scale.max, greaterThan(scale.min));
    });
  });

  group('the line chart', () {
    test('puts the highest value at the top of the plot', () {
      const Rect plot = Rect.fromLTRB(0, 0, 100, 50);
      const ChartScale scale = ChartScale(min: 0, max: 10);
      final List<Offset> offsets = ClinicalLineChartPainter.projectPoints(
        points: <ChartPoint>[
          const ChartPoint(0, 0),
          const ChartPoint(1, 10),
          const ChartPoint(2, 5),
        ],
        plot: plot,
        valueScale: scale,
        xMin: 0,
        xMax: 2,
      );
      expect(offsets[0].dy, plot.bottom);
      expect(offsets[1].dy, plot.top);
      expect(offsets[2].dy, closeTo(plot.bottom - plot.height * 0.5, 0.01));
    });

    test('spreads the points across the plot', () {
      const Rect plot = Rect.fromLTRB(0, 0, 100, 50);
      final List<Offset> offsets = ClinicalLineChartPainter.projectPoints(
        points: <ChartPoint>[const ChartPoint(0, 1), const ChartPoint(10, 1)],
        plot: plot,
        valueScale: const ChartScale(min: 0, max: 2),
        xMin: 0,
        xMax: 10,
      );
      expect(offsets.first.dx, plot.left);
      expect(offsets.last.dx, plot.right);
    });

    test('a single point sits in the middle of the plot', () {
      const Rect plot = Rect.fromLTRB(0, 0, 100, 50);
      final List<Offset> offsets = ClinicalLineChartPainter.projectPoints(
        points: <ChartPoint>[const ChartPoint(3, 1)],
        plot: plot,
        valueScale: const ChartScale(min: 0, max: 2),
        xMin: 0,
        xMax: 10,
      );
      expect(offsets.single.dx, closeTo(plot.center.dx, 0.01));
    });

    test('no points means no offsets', () {
      final List<Offset> offsets = ClinicalLineChartPainter.projectPoints(
        points: const <ChartPoint>[],
        plot: const Rect.fromLTRB(0, 0, 10, 10),
        valueScale: const ChartScale(min: 0, max: 1),
        xMin: 0,
        xMax: 1,
      );
      expect(offsets, isEmpty);
    });

    test('reads the horizontal extent of a series', () {
      final (double, double) extent = ClinicalLineChartPainter.xExtentOf(
        <ChartPoint>[const ChartPoint(2, 1), const ChartPoint(8, 3)],
      );
      expect(extent.$1, 2);
      expect(extent.$2, 8);
    });

    test('a series of one point still has an extent', () {
      final (double, double) extent = ClinicalLineChartPainter.xExtentOf(
        <ChartPoint>[const ChartPoint(4, 1)],
      );
      expect(extent.$2, greaterThan(extent.$1));
    });

    testWidgets('says what it is showing to a screen reader', (
      WidgetTester tester,
    ) async {
      const ClinicalLineChart chart = ClinicalLineChart(
        series: <ChartSeries>[
          ChartSeries(
            label: 'Haemoglobin',
            points: <ChartPoint>[ChartPoint(0, 11.4), ChartPoint(1, 12.1)],
          ),
        ],
        unit: 'g/dL',
      );
      expect(
        chart.semanticSummary,
        'Haemoglobin: 2 readings, latest 12.1 g/dL',
      );
      await tester.pumpWidget(_host(chart));
      expect(
        find.bySemanticsLabel('Haemoglobin: 2 readings, latest 12.1 g/dL'),
        findsOneWidget,
      );
    });

    testWidgets('says so when there is nothing to draw', (
      WidgetTester tester,
    ) async {
      const ClinicalLineChart chart = ClinicalLineChart(
        series: <ChartSeries>[
          ChartSeries(label: 'Haemoglobin', points: <ChartPoint>[]),
        ],
      );
      expect(chart.semanticSummary, 'Haemoglobin: no readings');
      await tester.pumpWidget(_host(chart));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('a reference band widens the value scale', (
      WidgetTester tester,
    ) async {
      const ClinicalLineChart chart = ClinicalLineChart(
        series: <ChartSeries>[
          ChartSeries(
            label: 'Haemoglobin',
            points: <ChartPoint>[ChartPoint(0, 12), ChartPoint(1, 12)],
          ),
        ],
        bands: <ChartBand>[ChartBand(from: 11, to: 15)],
      );
      expect(chart.valueScale.min, lessThanOrEqualTo(11));
      expect(chart.valueScale.max, greaterThanOrEqualTo(15));
      await tester.pumpWidget(_host(chart));
      expect(tester.takeException(), isNull);
    });
  });

  group('the bar chart', () {
    test('scales the bars to the largest value', () {
      final List<Rect> rects = ClinicalBarChartPainter.barRects(
        bars: const <ChartBar>[
          ChartBar(label: 'A', value: 2),
          ChartBar(label: 'B', value: 4),
        ],
        plot: const Rect.fromLTRB(0, 0, 100, 50),
        maxValue: 4,
      );
      expect(rects[0].height, closeTo(25, 0.01));
      expect(rects[1].height, closeTo(50, 0.01));
      expect(rects[1].bottom, 50);
    });

    test('a bar of no value has no height', () {
      final List<Rect> rects = ClinicalBarChartPainter.barRects(
        bars: const <ChartBar>[ChartBar(label: 'A', value: 0)],
        plot: const Rect.fromLTRB(0, 0, 100, 50),
        maxValue: 4,
      );
      expect(rects.single.height, 0);
    });

    test('no bars means no rectangles', () {
      final List<Rect> rects = ClinicalBarChartPainter.barRects(
        bars: const <ChartBar>[],
        plot: const Rect.fromLTRB(0, 0, 100, 50),
        maxValue: 4,
      );
      expect(rects, isEmpty);
    });

    test('says when a bar is over its limit', () {
      const ClinicalBarChart chart = ClinicalBarChart(
        bars: <ChartBar>[
          ChartBar(label: 'ICU', value: 12),
          ChartBar(label: 'Ward 3', value: 4),
        ],
        threshold: 10,
      );
      expect(
        chart.semanticSummary,
        'ICU: 12, limit 10, over limit; '
        'Ward 3: 4, limit 10',
      );
    });

    testWidgets('draws a limit line and the bars', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const ClinicalBarChart(
            bars: <ChartBar>[ChartBar(label: 'ICU', value: 12)],
            threshold: 10,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('the real-time strip', () {
    test('shows only the most recent samples', () {
      const RealTimeStrip strip = RealTimeStrip(
        samples: <double>[1, 2, 3, 4, 5],
        window: 3,
      );
      expect(strip.windowed, <double>[3, 4, 5]);
    });

    test('keeps every sample when there are fewer than the window', () {
      const RealTimeStrip strip = RealTimeStrip(
        samples: <double>[1, 2],
        window: 10,
      );
      expect(strip.windowed, <double>[1, 2]);
    });

    test('puts the newest sample at the right-hand edge', () {
      final List<Offset> offsets = RealTimeStripPainter.projectSamples(
        samples: const <double>[1, 2, 3],
        size: const Size(100, 20),
      );
      expect(offsets.last.dx, 100);
      expect(offsets.first.dx, 0);
    });

    test('a flat signal sits in the middle of the strip', () {
      final List<Offset> offsets = RealTimeStripPainter.projectSamples(
        samples: const <double>[5, 5, 5],
        size: const Size(100, 20),
      );
      expect(offsets.first.dy, 10);
    });

    test('a single sample sits in the middle of the strip', () {
      final List<Offset> offsets = RealTimeStripPainter.projectSamples(
        samples: const <double>[5],
        size: const Size(100, 20),
      );
      expect(offsets.single.dx, 100);
      expect(offsets.single.dy, 10);
    });

    testWidgets('says how many samples the strip holds', (
      WidgetTester tester,
    ) async {
      const RealTimeStrip strip = RealTimeStrip(
        samples: <double>[70, 72, 74],
        label: 'Heart rate',
        unit: 'bpm',
      );
      expect(strip.semanticLabel, 'Heart rate: 3 samples, latest 74 bpm');
      await tester.pumpWidget(_host(strip));
      expect(
        find.bySemanticsLabel('Heart rate: 3 samples, latest 74 bpm'),
        findsOneWidget,
      );
    });

    testWidgets('an empty strip says so', (WidgetTester tester) async {
      const RealTimeStrip strip = RealTimeStrip(
        samples: <double>[],
        label: 'Heart rate',
      );
      expect(strip.semanticLabel, 'Heart rate: no samples');
      await tester.pumpWidget(_host(strip));
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('the chart tone', () {
    test('a chart borrows the shared clinical tones', () {
      const ChartSeries series = ChartSeries(
        label: 'Haemoglobin',
        points: <ChartPoint>[],
        tone: ClinicalTone.critical,
      );
      expect(series.tone, ClinicalTone.critical);
    });
  });
}
