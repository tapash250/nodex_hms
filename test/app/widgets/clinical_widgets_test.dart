/// Tests for the shared clinical widget library (Module 45).
///
/// These components are the vocabulary the rest of the app uses to state a
/// clinical fact, so the tests are about honesty rather than looks: a badge
/// states its word, a metric says when it left its range, a sparkline refuses
/// to invent a trend from one reading, and the GCS total always equals its
/// parts.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/widgets/clinical_widgets.dart';
import 'package:nodex_hms/domain/beds/bed.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('status badges', () {
    testWidgets('state their words, not only their colour', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const ClinicalStatusBadge(
            label: 'Critical result',
            tone: ClinicalTone.critical,
          ),
        ),
      );
      expect(find.text('Critical result'), findsOneWidget);
    });

    testWidgets('a bed badge reads its state from the registry', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const BedStatusBadge(status: BedStatus.maintenance)),
      );
      expect(find.text('Out of service'), findsOneWidget);
    });

    testWidgets('a critical tone uses the error container', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const ClinicalStatusBadge(
            label: 'Critical',
            tone: ClinicalTone.critical,
          ),
        ),
      );
      final BuildContext context = tester.element(find.text('Critical'));
      final ColorScheme scheme = Theme.of(context).colorScheme;
      final Container container = tester.widget<Container>(
        find.ancestor(
          of: find.text('Critical'),
          matching: find.byType(Container),
        ),
      );
      expect(
        (container.decoration! as BoxDecoration).color,
        scheme.errorContainer,
      );
    });

    testWidgets('tones are distinct within a theme', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const SizedBox()));
      final ColorScheme scheme = Theme.of(tester.element(find.byType(SizedBox)))
          .colorScheme;
      final Set<Color> backgrounds = ClinicalTone.values
          .map((ClinicalTone tone) => tone.background(scheme))
          .toSet();
      expect(backgrounds.length, greaterThan(1));
      for (final ClinicalTone tone in ClinicalTone.values) {
        expect(tone.foreground(scheme), isNot(tone.background(scheme)));
      }
    });
  });

  group('metric tiles', () {
    testWidgets('report a value above its range', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const ClinicalMetricTile(
            label: 'Heart rate',
            value: 128,
            unit: 'bpm',
            referenceLow: 60,
            referenceHigh: 100,
          ),
        ),
      );
      expect(find.text('128 bpm'), findsOneWidget);
      expect(find.text('above range'), findsOneWidget);
    });

    testWidgets('report a value below its range', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const ClinicalMetricTile(
            label: 'SpO₂',
            value: 89,
            unit: '%',
            referenceLow: 94,
            referenceHigh: 100,
          ),
        ),
      );
      expect(find.text('below range'), findsOneWidget);
    });

    testWidgets('say nothing about a value inside its range', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const ClinicalMetricTile(
            label: 'Temperature',
            value: 36.8,
            unit: '°C',
            referenceLow: 36.1,
            referenceHigh: 37.2,
          ),
        ),
      );
      expect(find.textContaining('range'), findsNothing);
      expect(find.byIcon(Icons.trending_up), findsNothing);
      expect(find.byIcon(Icons.trending_down), findsNothing);
    });

    testWidgets('a fall in saturation worsens and is marked', (
      WidgetTester tester,
    ) async {
      const ClinicalMetricTile tile = ClinicalMetricTile(
        label: 'SpO₂',
        value: 88,
        previous: 92,
        referenceLow: 94,
        referenceHigh: 100,
      );
      expect(tile.isOutOfRange, isTrue);
      expect(tile.isWorsening, isTrue);
      await tester.pumpWidget(_host(tile));
      expect(find.byIcon(Icons.trending_down), findsOneWidget);
    });

    testWidgets('a rise in heart rate above the range worsens', (
      WidgetTester tester,
    ) async {
      const ClinicalMetricTile tile = ClinicalMetricTile(
        label: 'Heart rate',
        value: 132,
        previous: 118,
        referenceLow: 60,
        referenceHigh: 100,
      );
      expect(tile.isWorsening, isTrue);
    });

    testWidgets('a falling temperature below the range worsens', (
      WidgetTester tester,
    ) async {
      const ClinicalMetricTile tile = ClinicalMetricTile(
        label: 'Temperature',
        value: 35.4,
        previous: 35.9,
        referenceLow: 36.1,
        referenceHigh: 37.2,
      );
      expect(tile.isWorsening, isTrue);
    });

    testWidgets('a value inside the range is never worsening', (
      WidgetTester tester,
    ) async {
      const ClinicalMetricTile tile = ClinicalMetricTile(
        label: 'Heart rate',
        value: 90,
        previous: 70,
        referenceLow: 60,
        referenceHigh: 100,
      );
      expect(tile.isWorsening, isFalse);
    });
  });

  group('sparklines', () {
    testWidgets('draw nothing but a statement when there are no readings', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const VitalSparkline(values: <num>[], label: 'Pulse')),
      );
      expect(find.text('No data'), findsOneWidget);
      expect(
        const VitalSparkline(values: <num>[], label: 'Pulse').semanticLabel,
        'Pulse: no readings',
      );
    });

    testWidgets('a single reading is a point, not a trend', (
      WidgetTester tester,
    ) async {
      const VitalSparkline spark = VitalSparkline(
        values: <num>[37.4],
        label: 'Temperature',
        unit: '°C',
      );
      await tester.pumpWidget(_host(spark));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(spark.semanticLabel, 'Temperature: 1 readings, latest 37.4 °C');
    });

    testWidgets('say when the latest reading left the range', (
      WidgetTester tester,
    ) async {
      const VitalSparkline spark = VitalSparkline(
        values: <num>[96, 94, 89],
        label: 'SpO₂',
        unit: '%',
        referenceLow: 94,
        referenceHigh: 100,
      );
      expect(spark.lastIsOutOfRange, isTrue);
      await tester.pumpWidget(_host(spark));
      expect(
        spark.semanticLabel,
        'SpO₂: 3 readings, latest 89 %, outside the reference range',
      );
    });

    testWidgets('a series inside its range is not critical', (
      WidgetTester tester,
    ) async {
      const VitalSparkline spark = VitalSparkline(
        values: <num>[72, 80, 76],
        label: 'Heart rate',
        referenceLow: 60,
        referenceHigh: 100,
      );
      expect(spark.lastIsOutOfRange, isFalse);
    });

    testWidgets('the painter asks to be repainted when the series changes', (
      WidgetTester tester,
    ) async {
      const VitalSparklinePainter a = VitalSparklinePainter(
        values: <num>[1, 2],
        lineColor: Color(0xFF000000),
        bandColor: Color(0x11000000),
      );
      const VitalSparklinePainter b = VitalSparklinePainter(
        values: <num>[1, 2, 3],
        lineColor: Color(0xFF000000),
        bandColor: Color(0x11000000),
      );
      expect(b.shouldRepaint(a), isTrue);
      expect(a.shouldRepaint(a), isFalse);
    });
  });

  group('GCS calculator', () {
    testWidgets('the total is the sum of its parts', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const GcsCalculator(eye: 3, verbal: 4, motor: 5)),
      );
      expect(find.text('12 · Moderate'), findsOneWidget);
    });

    testWidgets('an intact patient totals fifteen', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const GcsCalculator()));
      expect(find.text('15 · Mild'), findsOneWidget);
    });

    testWidgets('dragging the eye slider raises the total and reports it', (
      WidgetTester tester,
    ) async {
      int? reportedEye;
      await tester.pumpWidget(
        _host(
          GcsCalculator(
            eye: 1,
            verbal: 1,
            motor: 1,
            onChanged: (int eye, int verbal, int motor) => reportedEye = eye,
          ),
        ),
      );
      expect(find.text('3 · Severe'), findsOneWidget);

      final Offset slider = tester.getCenter(find.byType(Slider).first);
      await tester.dragFrom(slider, const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(reportedEye, greaterThan(1));
      expect(find.text('Severe'), findsNothing);
    });

    testWidgets('the bands follow the clinical thresholds', (
      WidgetTester tester,
    ) async {
      expect(GcsCalculator.bandFor(3), 'Severe');
      expect(GcsCalculator.bandFor(8), 'Severe');
      expect(GcsCalculator.bandFor(9), 'Moderate');
      expect(GcsCalculator.bandFor(12), 'Moderate');
      expect(GcsCalculator.bandFor(13), 'Mild');
      expect(GcsCalculator.bandFor(15), 'Mild');
      expect(GcsCalculator.toneFor(8), ClinicalTone.critical);
      expect(GcsCalculator.toneFor(12), ClinicalTone.warning);
      expect(GcsCalculator.toneFor(13), ClinicalTone.success);
    });

    testWidgets('the declared bounds are the scale bounds', (
      WidgetTester tester,
    ) async {
      expect(GcsCalculator.minimumTotal, 3);
      expect(GcsCalculator.maximumTotal, 15);
      await tester.pumpWidget(_host(const SizedBox()));
      expect(GcsCalculator.minimumTotal, lessThan(GcsCalculator.maximumTotal));
    });

    testWidgets('a disabled calculator accepts no input', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const GcsCalculator(enabled: false, eye: 2)),
      );
      final List<Slider> sliders = tester
          .widgetList<Slider>(find.byType(Slider))
          .toList(growable: false);
      expect(sliders, hasLength(3));
      for (final Slider slider in sliders) {
        expect(slider.onChanged, isNull);
      }
    });

    testWidgets('an out-of-range component is clamped rather than trusted', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const GcsCalculator(eye: 9, verbal: 9, motor: 9)),
      );
      expect(find.text('15 · Mild'), findsOneWidget);
    });

    testWidgets('a new component value from the parent is adopted', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_host(const GcsCalculator(eye: 4)));
      expect(find.text('15 · Mild'), findsOneWidget);
      await tester.pumpWidget(_host(const GcsCalculator(eye: 1)));
      expect(find.text('12 · Moderate'), findsOneWidget);
    });
  });
}
