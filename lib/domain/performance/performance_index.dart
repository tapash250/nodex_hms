/// Clinical performance indicators (Module 03).
///
/// An indicator is a value for a period, read against a baseline. The
/// judgement is derived here rather than stored: a number that is two
/// standard deviations above its baseline is worse than one that is two
/// standard deviations below it, and only the direction of the indicator says
/// which is which.
library;

import 'package:meta/meta.dart';

/// How far an indicator sits from its baseline.
enum IndicatorStanding {
  /// Inside the usual spread of this indicator.
  withinBaseline('Within baseline'),

  /// Beyond the usual spread, in the direction that matters.
  beyondBaseline('Beyond baseline'),

  /// No baseline has been recorded, so nothing can be said.
  noBaseline('No baseline');

  const IndicatorStanding(this.label);

  /// Human-readable label.
  final String label;
}

/// One indicator for one period.
@immutable
final class PerformanceIndex {
  /// Creates an indicator reading.
  const PerformanceIndex({
    required this.id,
    required this.tenantId,
    required this.indicatorCode,
    required this.indicatorName,
    required this.category,
    required this.periodStart,
    required this.periodEnd,
    required this.value,
    this.baselineMean,
    this.baselineStddev,
    this.sampleSize = 0,
    this.lowerIsBetter = true,
  });

  /// Reads an indicator from a local row.
  factory PerformanceIndex.fromRow(Map<String, Object?> row) =>
      PerformanceIndex(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        indicatorCode: row['indicator_code']! as String,
        indicatorName: row['indicator_name']! as String,
        category: row['category']! as String,
        periodStart: DateTime.parse(row['period_start']! as String),
        periodEnd: DateTime.parse(row['period_end']! as String),
        value: _asDouble(row['value'])!,
        baselineMean: _asDouble(row['baseline_mean']),
        baselineStddev: _asDouble(row['baseline_stddev']),
        sampleSize: (row['sample_size'] as int?) ?? 0,
        lowerIsBetter: (row['lower_is_better'] as int?) != 0,
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The code of the indicator.
  final String indicatorCode;

  /// The name of the indicator.
  final String indicatorName;

  /// Which family of indicator it is.
  final String category;

  /// The start of the period.
  final DateTime periodStart;

  /// The end of the period.
  final DateTime periodEnd;

  /// The value for the period.
  final double value;

  /// The mean this indicator normally sits at.
  final double? baselineMean;

  /// The spread this indicator normally sits within.
  final double? baselineStddev;

  /// How many cases the reading covers.
  final int sampleSize;

  /// Whether a lower value is the better one.
  final bool lowerIsBetter;

  /// How far the value sits from the baseline, in standard deviations.
  ///
  /// Null when there is no baseline, or when the baseline has no spread to
  /// divide by: a flat baseline says nothing about what is usual.
  double? get deviation {
    final double? mean = baselineMean;
    final double? spread = baselineStddev;
    if (mean == null || spread == null || spread == 0) return null;
    return (value - mean) / spread;
  }

  /// Whether the value is worse than the baseline.
  ///
  /// A turnaround time that is going up is worse; a survival rate that is
  /// going down is worse. The indicator says which way is which.
  bool get isWorseThanBaseline {
    final double? delta = deviation;
    if (delta == null) return false;
    return lowerIsBetter ? delta > 0 : delta < 0;
  }

  /// Where the indicator stands.
  IndicatorStanding get standing {
    final double? delta = deviation;
    if (delta == null) {
      return baselineMean == null
          ? IndicatorStanding.noBaseline
          : IndicatorStanding.withinBaseline;
    }
    return delta.abs() >= 2
        ? IndicatorStanding.beyondBaseline
        : IndicatorStanding.withinBaseline;
  }

  /// The sentence the dashboard shows for this reading.
  String get summary {
    final double? delta = deviation;
    if (delta == null) {
      return '$value · no baseline to compare against';
    }
    final String sign = delta > 0 ? '+' : '';
    return '$value · $sign${delta.toStringAsFixed(1)}σ from baseline';
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
