/// Laboratory trends for a patient (Module 49).
///
/// A trend is a property of the patient, not of an order: the same analyte is
/// followed across three orders taken in three months. This groups the
/// patient's numeric results by analyte and keeps the ones that can actually
/// be read as a curve.
library;

import 'package:nodex_hms/domain/laboratory/lab.dart';

/// One reading of a trend.
final class LabTrendPoint {
  /// Declares a reading.
  const LabTrendPoint({required this.value, required this.at});

  /// The measured value.
  final double value;

  /// When it was measured.
  final DateTime at;
}

/// One analyte's trend.
final class LabTrend {
  /// Declares a trend.
  const LabTrend({
    required this.analyteCode,
    required this.analyteName,
    required this.points,
    this.unit,
    this.referenceLow,
    this.referenceHigh,
  });

  /// Standardized analyte code.
  final String analyteCode;

  /// Display name.
  final String analyteName;

  /// The readings, oldest first.
  final List<LabTrendPoint> points;

  /// Unit of measure.
  final String? unit;

  /// Lower edge of the reference interval, when the lab stated one.
  final double? referenceLow;

  /// Upper edge of the reference interval, when the lab stated one.
  final double? referenceHigh;

  /// The most recent reading.
  LabTrendPoint get latest => points.last;

  /// Whether the latest reading sits outside the reference interval.
  bool get latestIsAbnormal {
    final double low = referenceLow ?? double.negativeInfinity;
    final double high = referenceHigh ?? double.infinity;
    return latest.value < low || latest.value > high;
  }

  /// Whether the trend moves in the direction a worsening result would.
  ///
  /// A rising creatinine and a rising haemoglobin mean opposite things, and
  /// the analyte code is the only thing that can say which one this is.
  bool get isRising => points.length > 1 && latest.value > points.first.value;
}

/// Builds the trends held for a patient.
///
/// Only numeric results can be plotted, and a single reading is not a trend:
/// one value is a measurement, two values are a direction, and more are a
/// curve. Textual results and single readings are left out.
List<LabTrend> buildLabTrends(List<LabResult> results, {int maxPoints = 24}) {
  final Map<String, List<LabResult>> byAnalyte = <String, List<LabResult>>{};
  for (final LabResult result in results) {
    if (result.valueNumeric == null) continue;
    byAnalyte.putIfAbsent(result.analyteCode, () => <LabResult>[]).add(result);
  }

  final List<LabTrend> trends = <LabTrend>[];
  for (final MapEntry<String, List<LabResult>> entry in byAnalyte.entries) {
    final List<LabResult> readings = entry.value
      ..sort((LabResult a, LabResult b) => a.enteredAt.compareTo(b.enteredAt));
    if (readings.length < 2) continue;
    final List<LabResult> kept = readings.length > maxPoints
        ? readings.sublist(readings.length - maxPoints)
        : readings;
    final LabResult last = kept.last;
    final (double?, double?) range = parseReferenceRange(last.referenceRange);
    trends.add(
      LabTrend(
        analyteCode: entry.key,
        analyteName: last.analyteName,
        unit: last.unit,
        referenceLow: range.$1,
        referenceHigh: range.$2,
        points: <LabTrendPoint>[
          for (final LabResult reading in kept)
            LabTrendPoint(value: reading.valueNumeric!, at: reading.enteredAt),
        ],
      ),
    );
  }

  trends.sort(
    (LabTrend a, LabTrend b) =>
        a.analyteName.toLowerCase().compareTo(b.analyteName.toLowerCase()),
  );
  return trends;
}

/// Reads a reference interval out of the text the laboratory recorded.
///
/// The text is free form — "12.0-15.0 g/dL", "Negative", "3.5 to 5.5" — so
/// only an interval written as two numbers with a dash between them is
/// understood. Anything else is left alone rather than guessed at.
(double?, double?) parseReferenceRange(String? text) {
  if (text == null) return (null, null);
  final RegExpMatch? match = RegExp(
    r'(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return (null, null);
  final double low = double.parse(match.group(1)!);
  final double high = double.parse(match.group(2)!);
  if (high <= low) return (null, null);
  return (low, high);
}
