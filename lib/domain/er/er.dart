/// Emergency Department and triage entities (Module 05).
///
/// Triage acuity uses the ESI 1-5 scale. Escalation is one-way and requires
/// `triage.escalate`. ER visits transition through a finite status machine
/// enforced by a Postgres trigger.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// ESI acuity levels.
enum TriageAcuity {
  esi1('esi1'),
  esi2('esi2'),
  esi3('esi3'),
  esi4('esi4'),
  esi5('esi5');

  const TriageAcuity(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    TriageAcuity.esi1 => 'ESI 1 — Resuscitation',
    TriageAcuity.esi2 => 'ESI 2 — Emergent',
    TriageAcuity.esi3 => 'ESI 3 — Urgent',
    TriageAcuity.esi4 => 'ESI 4 — Less urgent',
    TriageAcuity.esi5 => 'ESI 5 — Non-urgent',
  };

  static TriageAcuity fromWire(String value) => TriageAcuity.values.firstWhere(
    (TriageAcuity acuity) => acuity.wireValue == value,
    orElse: () => TriageAcuity.esi3,
  );
}

/// Triage disposition.
enum TriageDisposition {
  discharge('discharge'),
  admit('admit'),
  transfer('transfer'),
  leftAgainstMedicalAdvice('left_against_medical_advice'),
  deceased('deceased');

  const TriageDisposition(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    TriageDisposition.discharge => 'Discharge',
    TriageDisposition.admit => 'Admit',
    TriageDisposition.transfer => 'Transfer',
    TriageDisposition.leftAgainstMedicalAdvice => 'Left against medical advice',
    TriageDisposition.deceased => 'Deceased',
  };

  static TriageDisposition fromWire(String value) =>
      TriageDisposition.values.firstWhere(
        (TriageDisposition disposition) => disposition.wireValue == value,
        orElse: () => TriageDisposition.discharge,
      );
}

/// How the patient arrived at the ED.
enum ArrivalMode {
  walkIn('walk_in'),
  ambulance('ambulance'),
  helicopter('helicopter'),
  police('police'),
  transfer('transfer');

  const ArrivalMode(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    ArrivalMode.walkIn => 'Walk-in',
    ArrivalMode.ambulance => 'Ambulance',
    ArrivalMode.helicopter => 'Helicopter',
    ArrivalMode.police => 'Police',
    ArrivalMode.transfer => 'Transfer',
  };

  static ArrivalMode? fromWire(String? value) {
    if (value == null) return null;
    for (final ArrivalMode mode in ArrivalMode.values) {
      if (mode.wireValue == value) return mode;
    }
    return null;
  }
}

/// ER visit status. Terminal statuses cannot transition further.
enum ErVisitStatus {
  inProgress('in_progress'),
  discharged('discharged'),
  admitted('admitted'),
  transferred('transferred'),
  leftAma('left_ama'),
  deceased('deceased');

  const ErVisitStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    ErVisitStatus.inProgress => 'In progress',
    ErVisitStatus.discharged => 'Discharged',
    ErVisitStatus.admitted => 'Admitted',
    ErVisitStatus.transferred => 'Transferred',
    ErVisitStatus.leftAma => 'Left AMA',
    ErVisitStatus.deceased => 'Deceased',
  };

  bool get isTerminal =>
      this != ErVisitStatus.inProgress && this != ErVisitStatus.admitted;

  static ErVisitStatus fromWire(String value) =>
      ErVisitStatus.values.firstWhere(
        (ErVisitStatus status) => status.wireValue == value,
        orElse: () => ErVisitStatus.inProgress,
      );
}

/// A triage assessment recorded at ED arrival.
@immutable
final class TriageAssessment {
  const TriageAssessment({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.assessedBy,
    required this.acuity,
    required this.chiefComplaint,
    required this.disposition,
    this.encounterId,
    this.vitals = const <String, Object?>{},
    this.redFlags = const <String>[],
    this.escalated = false,
    this.escalatedBy,
    this.escalatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String patientId;
  final String? encounterId;
  final String assessedBy;
  final TriageAcuity acuity;
  final String chiefComplaint;
  final Map<String, Object?> vitals;
  final List<String> redFlags;
  final TriageDisposition disposition;
  final bool escalated;
  final String? escalatedBy;
  final DateTime? escalatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Maps a local PowerSync row to the domain entity.
  factory TriageAssessment.fromRow(Map<String, Object?> row) {
    final Object? encounter = row['encounter_id'];
    final Object? escalatedBy = row['escalated_by'];
    final Object? escalatedAt = row['escalated_at'];
    final Object? vitals = row['vitals'];
    final Object? redFlags = row['red_flags'];
    return TriageAssessment(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      encounterId: encounter is String ? encounter : null,
      assessedBy: row['assessed_by']! as String,
      acuity: TriageAcuity.fromWire(row['acuity']! as String),
      chiefComplaint: row['chief_complaint']! as String,
      vitals: vitals is Map<String, Object?> ? vitals : <String, Object?>{},
      redFlags: redFlags is List
          ? redFlags.map((Object? flag) => flag.toString()).toList()
          : <String>[],
      disposition: TriageDisposition.fromWire(row['disposition']! as String),
      escalated: row['escalated'] == true,
      escalatedBy: escalatedBy is String ? escalatedBy : null,
      escalatedAt: escalatedAt is DateTime ? escalatedAt : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}

/// An Emergency Department visit linked to a triage assessment.
@immutable
final class ErVisit {
  const ErVisit({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.triageId,
    required this.providerId,
    required this.status,
    required this.startedAt,
    this.encounterId,
    this.arrivalMode,
    this.bedId,
    this.disposition,
    this.dispositionReason,
    this.dischargedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String patientId;
  final String triageId;
  final String? encounterId;
  final String providerId;
  final ErVisitStatus status;
  final ArrivalMode? arrivalMode;
  final String? bedId;
  final DateTime startedAt;
  final String? disposition;
  final String? dispositionReason;
  final DateTime? dischargedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOpen =>
      status == ErVisitStatus.inProgress || status == ErVisitStatus.admitted;

  /// Maps a local PowerSync row to the domain entity.
  factory ErVisit.fromRow(Map<String, Object?> row) {
    final Object? encounter = row['encounter_id'];
    final Object? bed = row['bed_id'];
    final Object? disposition = row['disposition'];
    final Object? dispositionReason = row['disposition_reason'];
    final Object? dischargedAt = row['discharged_at'];
    return ErVisit(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      triageId: row['triage_id']! as String,
      encounterId: encounter is String ? encounter : null,
      providerId: row['provider_id']! as String,
      status: ErVisitStatus.fromWire(row['status']! as String),
      arrivalMode: ArrivalMode.fromWire(row['arrival_mode'] as String?),
      bedId: bed is String ? bed : null,
      startedAt: row['started_at']! as DateTime,
      disposition: disposition is String ? disposition : null,
      dispositionReason: dispositionReason is String ? dispositionReason : null,
      dischargedAt: dischargedAt is DateTime ? dischargedAt : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}
