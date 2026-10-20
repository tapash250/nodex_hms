/// Departmental flow (Module 02).
///
/// A reading of a moment: how many patients registered, how many are waiting,
/// how long the wait has been. The dashboard shows the figures and derives
/// the judgement from them — a queue is long because the count says so, not
/// because a column said "long".
library;

import 'package:meta/meta.dart';

/// A department's flow at a moment.
@immutable
final class DepartmentMetric {
  /// Creates a reading.
  const DepartmentMetric({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.departmentId,
    required this.at,
    this.registrations = 0,
    this.waitingCount = 0,
    this.completedCount = 0,
    this.averageWaitMinutes,
    this.bottleneck,
  });

  /// Reads a reading from a local row.
  factory DepartmentMetric.fromRow(Map<String, Object?> row) =>
      DepartmentMetric(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        departmentId: row['department_id']! as String,
        at: DateTime.parse(row['metric_timestamp']! as String),
        registrations: (row['registrations'] as int?) ?? 0,
        waitingCount: (row['waiting_count'] as int?) ?? 0,
        completedCount: (row['completed_count'] as int?) ?? 0,
        averageWaitMinutes: _asDouble(row['average_wait_minutes']),
        bottleneck: row['bottleneck'] as String?,
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility the department is in.
  final String facilityId;

  /// The department.
  final String departmentId;

  /// When the reading was taken.
  final DateTime at;

  /// How many patients registered in the window.
  final int registrations;

  /// How many are waiting now.
  final int waitingCount;

  /// How many were seen.
  final int completedCount;

  /// The average wait, in minutes.
  final double? averageWaitMinutes;

  /// What the operations team says is holding the queue.
  final String? bottleneck;

  /// The share of the department's patients who are still waiting.
  double get waitingShare {
    final int total = waitingCount + completedCount;
    return total == 0 ? 0 : waitingCount / total;
  }

  /// Whether the queue is long enough to act on.
  ///
  /// The threshold is a clinical judgement the dashboard cannot make, so it
  /// is stated rather than implied: a queue is flagged when the wait is over
  /// [longWaitMinutes] or the waiting share is over [highWaitingShare].
  bool isBacklogged({int longWaitMinutes = 60, double highWaitingShare = 0.5}) {
    final double? wait = averageWaitMinutes;
    if (wait != null && wait >= longWaitMinutes) return true;
    return waitingShare >= highWaitingShare && waitingCount > 0;
  }

  /// The sentence the dashboard shows for this reading.
  String get summary {
    final String wait = averageWaitMinutes == null
        ? 'no wait recorded'
        : '${averageWaitMinutes!.toStringAsFixed(0)} min average wait';
    return '$waitingCount waiting · $registrations registered · $wait';
  }
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
