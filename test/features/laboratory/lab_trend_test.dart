/// Tests for laboratory trends (Module 49).
///
/// A trend is only worth drawing when it says something: two readings are a
/// direction, one reading is a measurement, and a textual result is neither.
/// These tests pin which results become a curve and which do not.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/features/laboratory/lab_trend.dart';

LabResult _result({
  required String analyteCode,
  required String analyteName,
  required DateTime at,
  double? value,
  String? text,
  String? unit,
  String? reference,
}) => LabResult(
  id: '$analyteCode-${at.millisecondsSinceEpoch}',
  tenantId: 'tenant-1',
  labOrderId: 'order-1',
  specimenId: 'specimen-1',
  analyteCode: analyteCode,
  analyteName: analyteName,
  status: LabResultStatus.verified,
  enteredBy: 'tech-1',
  enteredAt: at,
  valueText: text,
  valueNumeric: value,
  unit: unit,
  referenceRange: reference,
);

void main() {
  group('building trends', () {
    test('follows one analyte across readings', () {
      final List<LabTrend> trends = buildLabTrends(<LabResult>[
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 1),
          value: 11.4,
          unit: 'g/dL',
        ),
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 8),
          value: 12.1,
          unit: 'g/dL',
        ),
      ]);

      expect(trends, hasLength(1));
      expect(trends.single.analyteCode, 'HGB');
      expect(trends.single.points, hasLength(2));
      expect(trends.single.latest.value, 12.1);
      expect(trends.single.isRising, isTrue);
    });

    test('orders the readings by time, not by arrival', () {
      final List<LabTrend> trends = buildLabTrends(<LabResult>[
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 8),
          value: 12.1,
        ),
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 1),
          value: 11.4,
        ),
      ]);
      expect(trends.single.points.first.value, 11.4);
      expect(trends.single.points.last.value, 12.1);
    });

    test('leaves out a textual result', () {
      final List<LabTrend> trends = buildLabTrends(<LabResult>[
        _result(
          analyteCode: 'CULT',
          analyteName: 'Culture',
          at: DateTime.utc(2026, 9, 1),
          text: 'No growth',
        ),
        _result(
          analyteCode: 'CULT',
          analyteName: 'Culture',
          at: DateTime.utc(2026, 9, 8),
          text: 'No growth',
        ),
      ]);
      expect(trends, isEmpty);
    });

    test('leaves out an analyte measured once', () {
      final List<LabTrend> trends = buildLabTrends(<LabResult>[
        _result(
          analyteCode: 'NA',
          analyteName: 'Sodium',
          at: DateTime.utc(2026, 9, 1),
          value: 139,
        ),
      ]);
      expect(trends, isEmpty);
    });

    test('keeps separate analytes apart', () {
      final List<LabTrend> trends = buildLabTrends(<LabResult>[
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 1),
          value: 11,
        ),
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 8),
          value: 12,
        ),
        _result(
          analyteCode: 'CREA',
          analyteName: 'Creatinine',
          at: DateTime.utc(2026, 9, 1),
          value: 1.1,
        ),
        _result(
          analyteCode: 'CREA',
          analyteName: 'Creatinine',
          at: DateTime.utc(2026, 9, 8),
          value: 1.4,
        ),
      ]);
      expect(trends, hasLength(2));
      expect(
        trends.map((LabTrend trend) => trend.analyteCode).toList(),
        <String>['CREA', 'HGB'],
      );
    });

    test('keeps the most recent readings when there are many', () {
      final List<LabTrend> trends = buildLabTrends(<LabResult>[
        for (int i = 0; i < 30; i++)
          _result(
            analyteCode: 'HGB',
            analyteName: 'Haemoglobin',
            at: DateTime.utc(2026, 1, 1).add(Duration(days: i)),
            value: 10 + i * 0.1,
          ),
      ], maxPoints: 5);
      expect(trends.single.points, hasLength(5));
      expect(trends.single.latest.value, closeTo(12.9, 0.001));
    });

    test('marks a reading that sits outside the reference interval', () {
      final List<LabTrend> trends = buildLabTrends(<LabResult>[
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 1),
          value: 11,
          reference: '12-15 g/dL',
        ),
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 8),
          value: 9.4,
          reference: '12-15 g/dL',
        ),
      ]);
      expect(trends.single.referenceLow, 12);
      expect(trends.single.referenceHigh, 15);
      expect(trends.single.latestIsAbnormal, isTrue);
    });

    test('a reading inside the interval is not abnormal', () {
      final List<LabTrend> trends = buildLabTrends(<LabResult>[
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 1),
          value: 11,
          reference: '12-15 g/dL',
        ),
        _result(
          analyteCode: 'HGB',
          analyteName: 'Haemoglobin',
          at: DateTime.utc(2026, 9, 8),
          value: 13,
          reference: '12-15 g/dL',
        ),
      ]);
      expect(trends.single.latestIsAbnormal, isFalse);
    });
  });

  group('reading a reference interval', () {
    test('reads a plain interval', () {
      expect(parseReferenceRange('12-15'), (12.0, 15.0));
    });

    test('reads an interval with a unit', () {
      expect(parseReferenceRange('12.0 - 15.0 g/dL'), (12.0, 15.0));
    });

    test('reads an interval written with words', () {
      expect(parseReferenceRange('3.5 to 5.5'), (3.5, 5.5));
    });

    test('leaves a word alone rather than guessing', () {
      expect(parseReferenceRange('Negative'), (null, null));
    });

    test('leaves a missing interval alone', () {
      expect(parseReferenceRange(null), (null, null));
    });

    test('refuses an interval that runs backwards', () {
      expect(parseReferenceRange('15-12'), (null, null));
    });
  });
}
