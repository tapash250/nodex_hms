/// Enterprise KPI readings (Module 01).
///
/// A snapshot is a measurement of a facility at a moment. The dashboard does
/// not ask a model to decide whether the hospital is in trouble: it compares
/// the latest reading with the facility's own trailing baseline and states the
/// four figures that moved. A narrative may be attached to the snapshot when
/// one has been approved, but the figures remain the evidence.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:meta/meta.dart';

/// How serious a derived risk point is.
enum ExecutiveRiskLevel {
  /// The figure is inside its ordinary range.
  normal,

  /// The figure has drifted enough to watch.
  watch,

  /// The figure needs an executive decision now.
  critical;

  /// The words shown beside the figure.
  String get label => switch (this) {
    ExecutiveRiskLevel.normal => 'Within baseline',
    ExecutiveRiskLevel.watch => 'Watch',
    ExecutiveRiskLevel.critical => 'Act now',
  };
}

/// One of the four points the executive dashboard derives from the figures.
@immutable
final class ExecutiveRisk {
  /// Creates a risk point.
  const ExecutiveRisk({
    required this.code,
    required this.title,
    required this.level,
    required this.detail,
  });

  /// Stable identifier, used by tests and by a future approved narrative.
  final String code;

  /// The subject, for example `Occupancy`.
  final String title;

  /// How serious the reading is.
  final ExecutiveRiskLevel level;

  /// The figure and the baseline it was compared with.
  final String detail;

  /// Whether the point needs attention.
  bool get needsAttention => level != ExecutiveRiskLevel.normal;
}

/// A facility's executive reading at a moment.
@immutable
final class ExecutiveKpiSnapshot {
  /// Creates a snapshot.
  const ExecutiveKpiSnapshot({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.at,
    required this.occupancyRate,
    required this.activeInpatients,
    required this.erWaitingCount,
    required this.dailyGrossRevenue,
    required this.dailyNetRevenue,
    required this.bedTurnoverRate,
    required this.averageLengthOfStayDays,
    this.aiExecutiveSummary,
  });

  /// Reads a snapshot from a local row.
  factory ExecutiveKpiSnapshot.fromRow(Map<String, Object?> row) =>
      ExecutiveKpiSnapshot(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        at: DateTime.parse(row['snapshot_timestamp']! as String),
        occupancyRate: _asDouble(row['occupancy_rate']) ?? 0,
        activeInpatients: (row['active_inpatients'] as int?) ?? 0,
        erWaitingCount: (row['er_waiting_count'] as int?) ?? 0,
        dailyGrossRevenue: _asDouble(row['daily_gross_revenue']) ?? 0,
        dailyNetRevenue: _asDouble(row['daily_net_revenue']) ?? 0,
        bedTurnoverRate: _asDouble(row['bed_turnover_rate']) ?? 0,
        averageLengthOfStayDays:
            _asDouble(row['average_length_of_stay_days']) ?? 0,
        aiExecutiveSummary: _asJsonMap(row['ai_executive_summary']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility this reading describes.
  final String facilityId;

  /// When the reading was captured.
  final DateTime at;

  /// Occupied beds as a percentage of beds that are not under maintenance.
  final double occupancyRate;

  /// Patients currently holding a bed.
  final int activeInpatients;

  /// Emergency visits still in progress for this facility.
  final int erWaitingCount;

  /// Invoices issued during the facility day, before refunds.
  final double dailyGrossRevenue;

  /// Gross revenue minus refunds recorded during the same day.
  final double dailyNetRevenue;

  /// Released bed assignments in the trailing 24 hours as a percentage of
  /// beds that are not under maintenance.
  final double bedTurnoverRate;

  /// Mean completed length of stay in the trailing 30 days, in days.
  final double averageLengthOfStayDays;

  /// An approved narrative attached to this snapshot, when one exists.
  final Map<String, Object?>? aiExecutiveSummary;
}

/// The latest executive reading and the facility baseline behind it.
@immutable
final class ExecutiveKpiState {
  /// Creates a dashboard state.
  const ExecutiveKpiState({required this.facilityId, required this.snapshots});

  /// A state for a session with no facility in scope.
  const ExecutiveKpiState.empty() : facilityId = '', snapshots = const [];

  /// The facility the readings belong to.
  final String facilityId;

  /// Readings newest first, bounded to the trailing replication window.
  final List<ExecutiveKpiSnapshot> snapshots;

  /// The newest reading, or null before the first snapshot arrives.
  ExecutiveKpiSnapshot? get latest =>
      snapshots.isEmpty ? null : snapshots.first;

  /// The earlier readings that form the baseline.
  List<ExecutiveKpiSnapshot> get baseline =>
      snapshots.skip(1).take(30).toList(growable: false);

  /// The four risk points derived from the latest reading.
  ///
  /// The points are always four, even when all four are within baseline: a
  /// dashboard that hides the normal readings makes a quiet hospital look
  /// like a missing feed.
  List<ExecutiveRisk> get risks {
    final ExecutiveKpiSnapshot? reading = latest;
    if (reading == null) return const <ExecutiveRisk>[];
    final List<ExecutiveKpiSnapshot> prior = baseline;
    return <ExecutiveRisk>[
      _occupancyRisk(reading, prior),
      _emergencyRisk(reading, prior),
      _revenueRisk(reading, prior),
      _lengthOfStayRisk(reading, prior),
    ];
  }

  /// The approved narrative attached to the latest snapshot, if any.
  String? get aiSummary {
    final Object? value = latest?.aiExecutiveSummary?['summary'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static ExecutiveRisk _occupancyRisk(
    ExecutiveKpiSnapshot reading,
    List<ExecutiveKpiSnapshot> prior,
  ) {
    final _Baseline baseline = _Baseline.of(
      prior.map((ExecutiveKpiSnapshot s) => s.occupancyRate),
    );
    final double z = baseline.zScore(reading.occupancyRate);
    final ExecutiveRiskLevel level = reading.occupancyRate >= 90 || z >= 2
        ? ExecutiveRiskLevel.critical
        : reading.occupancyRate >= 85 || z >= 1.5
        ? ExecutiveRiskLevel.watch
        : ExecutiveRiskLevel.normal;
    return ExecutiveRisk(
      code: 'occupancy',
      title: 'Occupancy',
      level: level,
      detail: baseline.hasMean
          ? '${_percent(reading.occupancyRate)} occupied against a '
                '${_percent(baseline.mean!)} mean over '
                '${baseline.count} earlier snapshot(s).'
          : '${_percent(reading.occupancyRate)} occupied; no earlier '
                'snapshot is available for a baseline.',
    );
  }

  static ExecutiveRisk _emergencyRisk(
    ExecutiveKpiSnapshot reading,
    List<ExecutiveKpiSnapshot> prior,
  ) {
    final _Baseline baseline = _Baseline.of(
      prior.map((ExecutiveKpiSnapshot s) => s.erWaitingCount.toDouble()),
    );
    final double z = baseline.zScore(reading.erWaitingCount.toDouble());
    final ExecutiveRiskLevel level = reading.erWaitingCount >= 20 || z >= 2
        ? ExecutiveRiskLevel.critical
        : reading.erWaitingCount >= 10 || z >= 1.5
        ? ExecutiveRiskLevel.watch
        : ExecutiveRiskLevel.normal;
    return ExecutiveRisk(
      code: 'emergency',
      title: 'Emergency queue',
      level: level,
      detail: baseline.hasMean
          ? '${reading.erWaitingCount} waiting against a '
                '${baseline.mean!.toStringAsFixed(1)} mean over '
                '${baseline.count} earlier snapshot(s).'
          : '${reading.erWaitingCount} waiting; no earlier snapshot is '
                'available for a baseline.',
    );
  }

  static ExecutiveRisk _revenueRisk(
    ExecutiveKpiSnapshot reading,
    List<ExecutiveKpiSnapshot> prior,
  ) {
    final _Baseline baseline = _Baseline.of(
      prior.map((ExecutiveKpiSnapshot s) => s.dailyNetRevenue),
    );
    final double net = reading.dailyNetRevenue;
    final double? mean = baseline.mean;
    final ExecutiveRiskLevel level;
    if (mean == null || mean <= 0) {
      level = ExecutiveRiskLevel.normal;
    } else if (net < mean * 0.8 ||
        (baseline.stddev! > 0 && baseline.zScore(net) <= -2)) {
      level = ExecutiveRiskLevel.critical;
    } else if (net < mean * 0.9 ||
        (baseline.stddev! > 0 && baseline.zScore(net) <= -1.5)) {
      level = ExecutiveRiskLevel.watch;
    } else {
      level = ExecutiveRiskLevel.normal;
    }
    return ExecutiveRisk(
      code: 'revenue',
      title: 'Net revenue',
      level: level,
      detail: mean == null || mean <= 0
          ? '${net.toStringAsFixed(2)} collected; no earlier revenue '
                'baseline is available.'
          : '${net.toStringAsFixed(2)} collected against a '
                '${mean.toStringAsFixed(2)} mean over '
                '${baseline.count} earlier snapshot(s).',
    );
  }

  static ExecutiveRisk _lengthOfStayRisk(
    ExecutiveKpiSnapshot reading,
    List<ExecutiveKpiSnapshot> prior,
  ) {
    final _Baseline baseline = _Baseline.of(
      prior.map((ExecutiveKpiSnapshot s) => s.averageLengthOfStayDays),
    );
    final double days = reading.averageLengthOfStayDays;
    final double z = baseline.zScore(days);
    final ExecutiveRiskLevel level = days >= 7 || z >= 2
        ? ExecutiveRiskLevel.critical
        : days >= 5 || z >= 1.5
        ? ExecutiveRiskLevel.watch
        : ExecutiveRiskLevel.normal;
    return ExecutiveRisk(
      code: 'length_of_stay',
      title: 'Length of stay',
      level: level,
      detail: baseline.hasMean
          ? '${days.toStringAsFixed(2)} days against a '
                '${baseline.mean!.toStringAsFixed(2)} day mean over '
                '${baseline.count} earlier snapshot(s).'
          : '${days.toStringAsFixed(2)} days; no earlier snapshot is '
                'available for a baseline.',
    );
  }

  static String _percent(double value) => '${value.toStringAsFixed(2)}%';
}

/// Mean and population standard deviation of a trailing window.
final class _Baseline {
  const _Baseline({
    required this.count,
    required this.mean,
    required this.stddev,
  });

  factory _Baseline.of(Iterable<double> values) {
    final List<double> list = values.toList(growable: false);
    if (list.isEmpty) {
      return const _Baseline(count: 0, mean: null, stddev: null);
    }
    final double mean =
        list.reduce((double a, double b) => a + b) / list.length;
    final double variance = list.length < 2
        ? 0
        : (list
                      .map((double value) => math.pow(value - mean, 2))
                      .reduce((num a, num b) => a + b) /
                  list.length)
              .toDouble();
    return _Baseline(
      count: list.length,
      mean: mean,
      stddev: math.sqrt(variance),
    );
  }

  final int count;
  final double? mean;
  final double? stddev;

  bool get hasMean => mean != null;

  /// Standard score, or zero when the baseline has no spread.
  double zScore(double value) {
    final double? centre = mean;
    final double? spread = stddev;
    if (centre == null || spread == null || spread == 0) return 0;
    return (value - centre) / spread;
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

Map<String, Object?>? _asJsonMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map(
      (Object? key, Object? item) => MapEntry(key.toString(), item),
    );
  }
  if (value is String && value.trim().isNotEmpty) {
    final Object? decoded = jsonDecode(value);
    if (decoded is Map) {
      return decoded.map(
        (Object? key, Object? item) => MapEntry(key.toString(), item),
      );
    }
  }
  return null;
}
