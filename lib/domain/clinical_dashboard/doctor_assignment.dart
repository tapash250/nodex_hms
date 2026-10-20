/// The attending's cockpit (Module 04).
///
/// Three lists that a clinician opens at the start of a shift: the patients
/// they are responsible for, today's clinic, and the results that are waiting
/// for a signature. The first comes from the assignments, because a patient
/// is "mine" because there is an assignment row and not because a dashboard
/// says so.
library;

import 'package:meta/meta.dart';

/// What the clinician is responsible for.
enum AssignmentType {
  /// The clinician is the patient's attending.
  primaryAttending('primary_attending', 'Attending'),

  /// The clinician was asked for a second opinion.
  consulting('consulting', 'Consulting'),

  /// The clinician is on the rounding list.
  rounding('rounding', 'Rounding');

  const AssignmentType(this.wireValue, this.label);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  final String label;

  /// Parses a stored value.
  static AssignmentType fromWire(String value) =>
      AssignmentType.values.firstWhere(
        (AssignmentType type) => type.wireValue == value,
        orElse: () => AssignmentType.primaryAttending,
      );
}

/// One patient's responsibility.
@immutable
final class DoctorAssignment {
  /// Creates an assignment.
  const DoctorAssignment({
    required this.id,
    required this.tenantId,
    required this.doctorId,
    required this.patientId,
    required this.assignmentType,
    required this.status,
    this.assignedAt,
    this.concludedAt,
  });

  /// Reads an assignment from a local row.
  factory DoctorAssignment.fromRow(Map<String, Object?> row) =>
      DoctorAssignment(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        doctorId: row['doctor_id']! as String,
        patientId: row['patient_id']! as String,
        assignmentType: AssignmentType.fromWire(
          row['assignment_type']! as String,
        ),
        status: row['status']! as String,
        assignedAt: _parse(row['assigned_at']),
        concludedAt: _parse(row['concluded_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The clinician.
  final String doctorId;

  /// The patient.
  final String patientId;

  /// What the responsibility is.
  final AssignmentType assignmentType;

  /// Whether the responsibility still stands.
  final String status;

  /// When it was taken on.
  final DateTime? assignedAt;

  /// When it was concluded.
  final DateTime? concludedAt;

  /// Whether the responsibility is current.
  bool get isActive => status == 'active';
}

DateTime? _parse(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
