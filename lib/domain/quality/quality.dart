/// Quality & NABH Compliance Hub entities (Module 35).
///
/// Specification scope: "Accreditation compliance checklists (NABH / JCI),
/// Hospital Acquired Infection (HAI) tracking, and needle-stick incident
/// audits." Entities: "compliance_audits, incident_reports, and
/// clinical_indicators."
///
/// This is the quality estate: the evidence a hospital presents to an
/// accreditation body and the incident and indicator record that evidence is
/// built from. It is distinct from the clinical record (an encounter records the
/// care; an audit records whether the care met a standard) and from the statutory
/// register (the law requires a birth certificate; an accreditation body requires
/// a hand-hygiene rate).
///
/// Three records, mirroring the scope: the [ComplianceAudit] of one framework
/// chapter, the [IncidentReport] with the needle-stick and HAI events the scope
/// names, and the [ClinicalIndicator] measured over a period.
///
/// The facts that a stored copy would let drift are *derived* instead: the
/// compliance score and its verdict from the two criterion counts
/// ([complianceScore], [auditVerdict]), the indicator's value from its numerator,
/// denominator and unit ([indicatorValue]) and whether it meets its target from
/// its direction ([indicatorMeetsTarget]), and the overdue markers from the
/// severity response window ([incidentResponseWindow],
/// [isIncidentResponseOverdue], [isAuditOverdue], [isIncidentFollowUpOverdue]).
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// The scheme an accreditation audit is conducted under.
enum AccreditationFramework {
  /// National Accreditation Board for Hospitals and Healthcare Providers.
  nabh('nabh'),

  /// Joint Commission International.
  jci('jci'),

  /// ISO 9001-style quality management.
  iso('iso'),

  /// An internally devised standard.
  internal('internal');

  const AccreditationFramework(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AccreditationFramework.nabh => 'NABH',
    AccreditationFramework.jci => 'JCI',
    AccreditationFramework.iso => 'ISO',
    AccreditationFramework.internal => 'Internal',
  };

  /// Parses a stored value.
  static AccreditationFramework fromWire(String value) =>
      AccreditationFramework.values.firstWhere(
        (AccreditationFramework value_) => value_.wireValue == value,
        orElse: () => AccreditationFramework.internal,
      );
}

/// Lifecycle status of a compliance audit.
enum AuditStatus {
  /// Scheduled; editable.
  planned('planned'),

  /// Under way; the score is being entered.
  inProgress('in_progress'),

  /// Scored and attested; terminal.
  completed('completed'),

  /// Called off with a reason; terminal.
  cancelled('cancelled');

  const AuditStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AuditStatus.planned => 'Planned',
    AuditStatus.inProgress => 'In progress',
    AuditStatus.completed => 'Completed',
    AuditStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static AuditStatus fromWire(String value) => AuditStatus.values.firstWhere(
    (AuditStatus value_) => value_.wireValue == value,
    orElse: () => AuditStatus.planned,
  );

  /// Whether the audit has started.
  bool get isStarted => this == AuditStatus.inProgress || isTerminal;

  /// Whether the audit is settled.
  bool get isTerminal =>
      this == AuditStatus.completed || this == AuditStatus.cancelled;
}

/// Whether a compliance audit may move from [from] to [to].
bool auditCanTransition(AuditStatus from, AuditStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    AuditStatus.planned =>
      to == AuditStatus.inProgress || to == AuditStatus.cancelled,
    AuditStatus.inProgress =>
      to == AuditStatus.completed || to == AuditStatus.cancelled,
    AuditStatus.completed || AuditStatus.cancelled => false,
  };
}

/// What kind of patient safety incident was reported.
enum IncidentCategory {
  /// A sharps injury, the audit the scope names.
  needleStick('needle_stick'),

  /// A medication error.
  medicationError('medication_error'),

  /// A patient fall.
  patientFall('patient_fall'),

  /// A hospital acquired infection.
  hai('hai'),

  /// A transfusion reaction.
  transfusionReaction('transfusion_reaction'),

  /// A surgical incident.
  surgical('surgical'),

  /// An equipment failure.
  equipment('equipment'),

  /// Violence against staff or patients.
  violence('violence'),

  /// Anything else, described on the row.
  other('other');

  const IncidentCategory(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    IncidentCategory.needleStick => 'Needle-stick injury',
    IncidentCategory.medicationError => 'Medication error',
    IncidentCategory.patientFall => 'Patient fall',
    IncidentCategory.hai => 'Hospital acquired infection',
    IncidentCategory.transfusionReaction => 'Transfusion reaction',
    IncidentCategory.surgical => 'Surgical incident',
    IncidentCategory.equipment => 'Equipment failure',
    IncidentCategory.violence => 'Violence',
    IncidentCategory.other => 'Other',
  };

  /// Parses a stored value.
  static IncidentCategory fromWire(String value) =>
      IncidentCategory.values.firstWhere(
        (IncidentCategory value_) => value_.wireValue == value,
        orElse: () => IncidentCategory.other,
      );
}

/// How serious an incident is.
enum IncidentSeverity {
  /// Caught before harm.
  nearMiss('near_miss'),

  /// Minor harm.
  minor('minor'),

  /// Moderate harm.
  moderate('moderate'),

  /// Major harm.
  major('major'),

  /// Death or permanent harm.
  sentinel('sentinel');

  const IncidentSeverity(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    IncidentSeverity.nearMiss => 'Near miss',
    IncidentSeverity.minor => 'Minor',
    IncidentSeverity.moderate => 'Moderate',
    IncidentSeverity.major => 'Major',
    IncidentSeverity.sentinel => 'Sentinel',
  };

  /// Parses a stored value.
  static IncidentSeverity fromWire(String value) =>
      IncidentSeverity.values.firstWhere(
        (IncidentSeverity value_) => value_.wireValue == value,
        orElse: () => IncidentSeverity.minor,
      );
}

/// Lifecycle status of an incident report.
enum IncidentStatus {
  /// Logged; editable.
  reported('reported'),

  /// Being investigated; what happened is frozen.
  investigating('investigating'),

  /// Corrective action agreed with a date.
  actionPlan('action_plan'),

  /// Closed with a note; terminal.
  closed('closed'),

  /// Withdrawn while live.
  voided('voided');

  const IncidentStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    IncidentStatus.reported => 'Reported',
    IncidentStatus.investigating => 'Investigating',
    IncidentStatus.actionPlan => 'Action plan',
    IncidentStatus.closed => 'Closed',
    IncidentStatus.voided => 'Voided',
  };

  /// Parses a stored value.
  static IncidentStatus fromWire(String value) =>
      IncidentStatus.values.firstWhere(
        (IncidentStatus value_) => value_.wireValue == value,
        orElse: () => IncidentStatus.reported,
      );

  /// Whether the incident has still to be worked.
  bool get isLive => !isTerminal;

  /// Whether the incident is settled.
  bool get isTerminal =>
      this == IncidentStatus.closed || this == IncidentStatus.voided;

  /// Whether the incident is still open for investigation.
  bool get awaitsInvestigation => this == IncidentStatus.reported;
}

/// Whether an incident report may move from [from] to [to].
bool incidentCanTransition(IncidentStatus from, IncidentStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    IncidentStatus.reported =>
      to == IncidentStatus.investigating || to == IncidentStatus.voided,
    IncidentStatus.investigating =>
      to == IncidentStatus.actionPlan || to == IncidentStatus.voided,
    IncidentStatus.actionPlan => to == IncidentStatus.closed,
    IncidentStatus.closed || IncidentStatus.voided => false,
  };
}

/// What a clinical indicator measures.
enum IndicatorCategory {
  /// Infection prevention and control.
  infectionControl('infection_control'),

  /// Patient safety.
  patientSafety('patient_safety'),

  /// A clinical outcome.
  clinicalOutcome('clinical_outcome'),

  /// An operational measure.
  operational('operational'),

  /// Evidence for an accreditation standard.
  accreditation('accreditation');

  const IndicatorCategory(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    IndicatorCategory.infectionControl => 'Infection control',
    IndicatorCategory.patientSafety => 'Patient safety',
    IndicatorCategory.clinicalOutcome => 'Clinical outcome',
    IndicatorCategory.operational => 'Operational',
    IndicatorCategory.accreditation => 'Accreditation',
  };

  /// Parses a stored value.
  static IndicatorCategory fromWire(String value) =>
      IndicatorCategory.values.firstWhere(
        (IndicatorCategory value_) => value_.wireValue == value,
        orElse: () => IndicatorCategory.operational,
      );
}

/// How an indicator's ratio reads.
enum IndicatorUnit {
  /// A percentage.
  percent('percent'),

  /// Events per thousand patient days.
  perThousandPatientDays('per_1000_patient_days'),

  /// Events per thousand device days.
  perThousandDeviceDays('per_1000_device_days'),

  /// A plain count.
  count('count'),

  /// A bare ratio.
  ratio('ratio'),

  /// A duration in hours.
  hours('hours');

  const IndicatorUnit(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    IndicatorUnit.percent => 'Percent',
    IndicatorUnit.perThousandPatientDays => 'Per 1000 patient days',
    IndicatorUnit.perThousandDeviceDays => 'Per 1000 device days',
    IndicatorUnit.count => 'Count',
    IndicatorUnit.ratio => 'Ratio',
    IndicatorUnit.hours => 'Hours',
  };

  /// The multiplier the unit applies to the raw ratio.
  ///
  /// A count and an hours reading are the numerator itself, so the multiplier is
  /// not applied to them by [indicatorValue].
  double get ratioMultiplier => switch (this) {
    IndicatorUnit.percent => 100,
    IndicatorUnit.perThousandPatientDays => 1000,
    IndicatorUnit.perThousandDeviceDays => 1000,
    IndicatorUnit.count => 1,
    IndicatorUnit.ratio => 1,
    IndicatorUnit.hours => 1,
  };

  /// Whether the value is the numerator rather than a ratio.
  bool get isAbsolute =>
      this == IndicatorUnit.count || this == IndicatorUnit.hours;

  /// Parses a stored value.
  static IndicatorUnit fromWire(String value) =>
      IndicatorUnit.values.firstWhere(
        (IndicatorUnit value_) => value_.wireValue == value,
        orElse: () => IndicatorUnit.percent,
      );
}

/// Which way an indicator is good.
enum IndicatorDirection {
  /// A larger value is better.
  higherIsBetter('higher_is_better'),

  /// A smaller value is better.
  lowerIsBetter('lower_is_better');

  const IndicatorDirection(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    IndicatorDirection.higherIsBetter => 'Higher is better',
    IndicatorDirection.lowerIsBetter => 'Lower is better',
  };

  /// Parses a stored value.
  static IndicatorDirection fromWire(String value) =>
      IndicatorDirection.values.firstWhere(
        (IndicatorDirection value_) => value_.wireValue == value,
        orElse: () => IndicatorDirection.lowerIsBetter,
      );
}

/// Lifecycle status of a clinical indicator reading.
enum IndicatorStatus {
  /// Being entered; editable.
  draft('draft'),

  /// Published; frozen but for retraction.
  published('published'),

  /// Withdrawn with a reason; terminal.
  retracted('retracted');

  const IndicatorStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    IndicatorStatus.draft => 'Draft',
    IndicatorStatus.published => 'Published',
    IndicatorStatus.retracted => 'Retracted',
  };

  /// Parses a stored value.
  static IndicatorStatus fromWire(String value) =>
      IndicatorStatus.values.firstWhere(
        (IndicatorStatus value_) => value_.wireValue == value,
        orElse: () => IndicatorStatus.draft,
      );

  /// Whether the reading is still being entered.
  bool get isDraft => this == IndicatorStatus.draft;

  /// Whether the reading is settled.
  bool get isTerminal => this == IndicatorStatus.retracted;
}

/// Whether a clinical indicator may move from [from] to [to].
bool indicatorCanTransition(IndicatorStatus from, IndicatorStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    IndicatorStatus.draft => to == IndicatorStatus.published,
    IndicatorStatus.published => to == IndicatorStatus.retracted,
    IndicatorStatus.retracted => false,
  };
}

/// How a scored audit reads against the conformance thresholds.
enum AuditVerdict {
  /// Not scored yet.
  notScored('not_scored'),

  /// At or above the conformance threshold.
  conformant('conformant'),

  /// At or above the partial threshold but below conformance.
  partiallyConformant('partially_conformant'),

  /// Below the partial threshold.
  nonConformant('non_conformant');

  const AuditVerdict(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    AuditVerdict.notScored => 'Not scored',
    AuditVerdict.conformant => 'Conformant',
    AuditVerdict.partiallyConformant => 'Partially conformant',
    AuditVerdict.nonConformant => 'Non-conformant',
  };
}

/// The score at or above which a chapter is conformant.
const int auditConformantThreshold = 90;

/// The score at or above which a chapter is partially conformant.
const int auditPartialThreshold = 70;

/// The compliance score of a scored audit, as a whole percentage.
///
/// Deriving the score from the two counts means the percentage cannot disagree
/// with the criteria it summarises. An unscored or uncountable audit has none.
int? complianceScore(ComplianceAudit audit) {
  final int? total = audit.totalCriteria;
  final int? compliant = audit.compliantCriteria;
  if (total == null || compliant == null || total <= 0) {
    return null;
  }
  return ((compliant * 100) / total).round();
}

/// How a scored audit reads against the conformance thresholds.
AuditVerdict auditVerdict(ComplianceAudit audit) {
  final int? score = complianceScore(audit);
  if (score == null) {
    return AuditVerdict.notScored;
  }
  if (score >= auditConformantThreshold) {
    return AuditVerdict.conformant;
  }
  if (score >= auditPartialThreshold) {
    return AuditVerdict.partiallyConformant;
  }
  return AuditVerdict.nonConformant;
}

/// Whether a planned or started audit is overdue.
///
/// An audit is overdue when its scheduled moment has passed and it has not been
/// conducted. A conducted audit is never overdue, however late it was: the
/// conducted moment settles it.
bool isAuditOverdue({required ComplianceAudit audit, required DateTime now}) {
  if (audit.conductedAt != null || audit.status.isTerminal) {
    return false;
  }
  return now.toUtc().isAfter(audit.scheduledFor.toUtc());
}

/// How long an incident severity allows before it must be under investigation.
///
/// A sentinel event or a major harm has a day; a moderate one three days; a
/// minor one or a near miss a week. Derived rather than stored, so a threshold
/// change re-derives every marker on every device.
Duration incidentResponseWindow(IncidentSeverity severity) =>
    switch (severity) {
      IncidentSeverity.sentinel ||
      IncidentSeverity.major => const Duration(days: 1),
      IncidentSeverity.moderate => const Duration(days: 3),
      IncidentSeverity.minor ||
      IncidentSeverity.nearMiss => const Duration(days: 7),
    };

/// Whether an incident is overdue for investigation.
///
/// An incident already under investigation is not overdue, whatever the delay
/// was; the rule marks what still has to happen, not what was slow.
bool isIncidentResponseOverdue({
  required IncidentReport incident,
  required DateTime now,
}) {
  if (!incident.status.awaitsInvestigation) {
    return false;
  }
  return now.toUtc().difference(incident.occurredAt.toUtc()) >
      incidentResponseWindow(incident.severity);
}

/// Whether a serology follow-up date has passed without the follow-up closing.
///
/// A needle-stick injury carries a follow-up date in the incident itself; the
/// overdue marker is derived from it and the clock.
bool isIncidentFollowUpOverdue({
  required IncidentReport incident,
  required DateTime now,
}) {
  final DateTime? due = incident.followUpDueAt;
  if (due == null || incident.status.isTerminal) {
    return false;
  }
  return now.toUtc().isAfter(due.toUtc());
}

/// The measured value of an indicator, in its own unit.
///
/// A count or an hours reading is its numerator; everything else is the ratio
/// times the unit's multiplier. A reading with no denominator has no value.
double? indicatorValue(ClinicalIndicator indicator) {
  if (indicator.unit.isAbsolute) {
    return indicator.numerator.toDouble();
  }
  if (indicator.denominator <= 0) {
    return null;
  }
  return indicator.numerator /
      indicator.denominator *
      indicator.unit.ratioMultiplier;
}

/// Whether an indicator meets its target, or null when it cannot be answered.
///
/// The comparison reads the direction, so one rule serves a hand-hygiene rate
/// that must rise and an infection rate that must fall.
bool? indicatorMeetsTarget(ClinicalIndicator indicator) {
  final int? target = indicator.targetValue;
  final double? value = indicatorValue(indicator);
  if (target == null || value == null) {
    return null;
  }
  return switch (indicator.direction) {
    IndicatorDirection.higherIsBetter => value >= target,
    IndicatorDirection.lowerIsBetter => value <= target,
  };
}

/// One audit of one framework chapter.
@immutable
final class ComplianceAudit {
  /// Creates a compliance audit.
  const ComplianceAudit({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.framework,
    required this.chapter,
    required this.title,
    required this.scheduledFor,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.standardReference,
    this.auditorId,
    this.conductedAt,
    this.totalCriteria,
    this.compliantCriteria,
    this.findings,
    this.correctiveActionDueAt,
    this.completedBy,
    this.cancelledAt,
    this.cancelReason,
    this.createdAt,
  });

  /// Validates and builds a new planned audit row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String chapter,
    required String title,
    required DateTime scheduledFor,
    required String createdBy,
    AccreditationFramework framework = AccreditationFramework.nabh,
    String? standardReference,
    String? auditorId,
    String? findings,
    String auditId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (chapter.trim().isEmpty) {
      fieldErrors['chapter'] = 'The chapter assessed is required.';
    }
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'A title is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Compliance audit failed validation.',
        fieldErrors: fieldErrors,
        code: 'compliance_audit_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (auditId.isNotEmpty) 'id': auditId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'framework': framework.wireValue,
      'chapter': chapter.trim(),
      'title': title.trim(),
      'standard_reference': _trimmed(standardReference),
      'auditor_id': _trimmed(auditorId),
      'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      'status': AuditStatus.planned.wireValue,
      'conducted_at': null,
      'total_criteria': null,
      'compliant_criteria': null,
      'findings': _trimmed(findings),
      'corrective_action_due_at': null,
      'completed_by': null,
      'cancelled_at': null,
      'cancel_reason': null,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes an audit from a local row.
  factory ComplianceAudit.fromRow(Map<String, Object?> row) => ComplianceAudit(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    framework: AccreditationFramework.fromWire(
      (row['framework'] as String?) ?? AccreditationFramework.nabh.wireValue,
    ),
    chapter: row['chapter']! as String,
    title: row['title']! as String,
    scheduledFor: _parse(row['scheduled_for']),
    status: AuditStatus.fromWire(
      (row['status'] as String?) ?? AuditStatus.planned.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    standardReference: row['standard_reference'] as String?,
    auditorId: row['auditor_id'] as String?,
    conductedAt: _parseNullable(row['conducted_at']),
    totalCriteria: row['total_criteria'] == null
        ? null
        : _asInt(row['total_criteria']),
    compliantCriteria: row['compliant_criteria'] == null
        ? null
        : _asInt(row['compliant_criteria']),
    findings: row['findings'] as String?,
    correctiveActionDueAt: _parseNullable(row['corrective_action_due_at']),
    completedBy: row['completed_by'] as String?,
    cancelledAt: _parseNullable(row['cancelled_at']),
    cancelReason: row['cancel_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility audited.
  final String facilityId;

  /// The scheme audited under.
  final AccreditationFramework framework;

  /// The chapter assessed.
  final String chapter;

  /// What the audit covers.
  final String title;

  /// When the audit is scheduled, UTC.
  final DateTime scheduledFor;

  /// Lifecycle status.
  final AuditStatus status;

  /// Who raised the audit.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The clause within the chapter.
  final String? standardReference;

  /// The auditor.
  final String? auditorId;

  /// When the audit was conducted, UTC.
  final DateTime? conductedAt;

  /// How many criteria were assessed.
  final int? totalCriteria;

  /// How many criteria were met.
  final int? compliantCriteria;

  /// What the audit found.
  final String? findings;

  /// When the corrective action falls due, UTC.
  final DateTime? correctiveActionDueAt;

  /// Who completed the audit.
  final String? completedBy;

  /// When the audit was cancelled, UTC.
  final DateTime? cancelledAt;

  /// Why the audit was cancelled.
  final String? cancelReason;

  /// When the audit was raised, UTC.
  final DateTime? createdAt;

  /// The derived compliance score.
  int? get score => complianceScore(this);

  /// The derived verdict.
  AuditVerdict get verdict => auditVerdict(this);

  /// Whether the audit is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the audit has been scored.
  bool get isScored => score != null;
}

/// The change set that starts an audit.
Map<String, Object?> auditStartChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': AuditStatus.inProgress.wireValue,
    'conducted_at': now,
    'updated_at': now,
  };
}

/// The change set that completes and scores an audit.
Map<String, Object?> auditCompleteChanges({
  required int totalCriteria,
  required int compliantCriteria,
  required String completedBy,
  String? findings,
  DateTime? correctiveActionDueAt,
  DateTime? at,
}) {
  final Map<String, String> fieldErrors = <String, String>{};
  if (totalCriteria <= 0) {
    fieldErrors['total_criteria'] = 'Expected at least one criterion.';
  }
  if (compliantCriteria < 0) {
    fieldErrors['compliant_criteria'] = 'A count cannot be negative.';
  }
  if (totalCriteria > 0 && compliantCriteria > totalCriteria) {
    fieldErrors['compliant_criteria'] = 'More criteria were met than assessed.';
  }
  if (completedBy.isEmpty) {
    fieldErrors['completed_by'] = 'Who completed it is required.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Compliance audit failed validation.',
      fieldErrors: fieldErrors,
      code: 'compliance_audit_score_invalid',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': AuditStatus.completed.wireValue,
    'total_criteria': totalCriteria,
    'compliant_criteria': compliantCriteria,
    'findings': ?_trimmed(findings),
    'corrective_action_due_at': ?correctiveActionDueAt
        ?.toUtc()
        .toIso8601String(),
    'completed_by': completedBy,
    'updated_at': now,
  };
}

/// The change set that calls an audit off.
Map<String, Object?> auditCancelChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Compliance audit failed validation.',
      fieldErrors: <String, String>{'cancel_reason': 'A reason is required.'},
      code: 'compliance_audit_cancel_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': AuditStatus.cancelled.wireValue,
    'cancelled_at': now,
    'cancel_reason': reason.trim(),
    'updated_at': now,
  };
}

/// A patient safety incident, including the needle-stick and HAI events.
@immutable
final class IncidentReport {
  /// Creates an incident report.
  const IncidentReport({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.reportNumber,
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    required this.occurredAt,
    required this.reportedAt,
    required this.reportedBy,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.location,
    this.patientId,
    this.assignedTo,
    this.immediateAction,
    this.investigationStartedAt,
    this.actionPlan,
    this.actionPlanDueAt,
    this.followUpDueAt,
    this.closedAt,
    this.closureNote,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new reported incident row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String reportNumber,
    required String title,
    required String description,
    required DateTime occurredAt,
    required String reportedBy,
    required String createdBy,
    IncidentCategory category = IncidentCategory.other,
    IncidentSeverity severity = IncidentSeverity.minor,
    String? location,
    String? patientId,
    String? assignedTo,
    String? immediateAction,
    DateTime? reportedAt,
    DateTime? followUpDueAt,
    String incidentId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (reportNumber.trim().isEmpty) {
      fieldErrors['report_number'] = 'A report number is required.';
    }
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'A title is required.';
    }
    if (description.trim().isEmpty) {
      fieldErrors['description'] = 'What happened is required.';
    }
    if (reportedBy.isEmpty) {
      fieldErrors['reported_by'] = 'Who reported it is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Incident report failed validation.',
        fieldErrors: fieldErrors,
        code: 'incident_report_invalid',
      );
    }
    final DateTime at = (reportedAt ?? DateTime.now()).toUtc();
    final String stamp = at.toIso8601String();
    return <String, Object?>{
      if (incidentId.isNotEmpty) 'id': incidentId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'report_number': reportNumber.trim(),
      'category': category.wireValue,
      'severity': severity.wireValue,
      'title': title.trim(),
      'description': description.trim(),
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'reported_at': stamp,
      'location': _trimmed(location),
      'patient_id': _trimmed(patientId),
      'reported_by': reportedBy,
      'assigned_to': _trimmed(assignedTo),
      'immediate_action': _trimmed(immediateAction),
      'status': IncidentStatus.reported.wireValue,
      'investigation_started_at': null,
      'action_plan': null,
      'action_plan_due_at': null,
      'follow_up_due_at': ?followUpDueAt?.toUtc().toIso8601String(),
      'closed_at': null,
      'closure_note': null,
      'voided_at': null,
      'void_reason': null,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes an incident from a local row.
  factory IncidentReport.fromRow(Map<String, Object?> row) => IncidentReport(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    reportNumber: row['report_number']! as String,
    category: IncidentCategory.fromWire(
      (row['category'] as String?) ?? IncidentCategory.other.wireValue,
    ),
    severity: IncidentSeverity.fromWire(
      (row['severity'] as String?) ?? IncidentSeverity.minor.wireValue,
    ),
    title: row['title']! as String,
    description: row['description']! as String,
    occurredAt: _parse(row['occurred_at']),
    reportedAt: _parse(row['reported_at']),
    reportedBy: row['reported_by']! as String,
    status: IncidentStatus.fromWire(
      (row['status'] as String?) ?? IncidentStatus.reported.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    location: row['location'] as String?,
    patientId: row['patient_id'] as String?,
    assignedTo: row['assigned_to'] as String?,
    immediateAction: row['immediate_action'] as String?,
    investigationStartedAt: _parseNullable(row['investigation_started_at']),
    actionPlan: row['action_plan'] as String?,
    actionPlanDueAt: _parseNullable(row['action_plan_due_at']),
    followUpDueAt: _parseNullable(row['follow_up_due_at']),
    closedAt: _parseNullable(row['closed_at']),
    closureNote: row['closure_note'] as String?,
    voidedAt: _parseNullable(row['voided_at']),
    voidReason: row['void_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility where the incident happened.
  final String facilityId;

  /// The hospital's report number.
  final String reportNumber;

  /// What kind of incident it is.
  final IncidentCategory category;

  /// How serious it is.
  final IncidentSeverity severity;

  /// What happened, in one line.
  final String title;

  /// What happened, in full.
  final String description;

  /// When the incident happened, UTC.
  final DateTime occurredAt;

  /// When the incident was reported, UTC.
  final DateTime reportedAt;

  /// Who reported it.
  final String reportedBy;

  /// Lifecycle status.
  final IncidentStatus status;

  /// Who raised the report.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// Where it happened.
  final String? location;

  /// The patient involved, when there is one.
  final String? patientId;

  /// Who is investigating.
  final String? assignedTo;

  /// What was done at once, as a needle-stick may need prophylaxis at once.
  final String? immediateAction;

  /// When the investigation started, UTC.
  final DateTime? investigationStartedAt;

  /// The agreed corrective action.
  final String? actionPlan;

  /// When the corrective action falls due, UTC.
  final DateTime? actionPlanDueAt;

  /// When a serology follow-up falls due, UTC.
  final DateTime? followUpDueAt;

  /// When the incident was closed, UTC.
  final DateTime? closedAt;

  /// Why the incident was closed.
  final String? closureNote;

  /// When the report was withdrawn, UTC.
  final DateTime? voidedAt;

  /// Why the report was withdrawn.
  final String? voidReason;

  /// When the report was raised, UTC.
  final DateTime? createdAt;

  /// Whether the incident has still to be worked.
  bool get isLive => status.isLive;

  /// Whether the incident is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the incident is a sharps injury.
  bool get isNeedleStick => category == IncidentCategory.needleStick;

  /// Whether the incident is a hospital acquired infection.
  bool get isHospitalAcquiredInfection => category == IncidentCategory.hai;

  /// The derived response window for this severity.
  Duration get responseWindow => incidentResponseWindow(severity);
}

/// The change set that opens an investigation.
Map<String, Object?> incidentInvestigateChanges({
  String? assignedTo,
  DateTime? at,
}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': IncidentStatus.investigating.wireValue,
    'investigation_started_at': now,
    'assigned_to': ?_trimmed(assignedTo),
    'updated_at': now,
  };
}

/// The change set that records the agreed corrective action.
Map<String, Object?> incidentActionPlanChanges({
  required String actionPlan,
  required DateTime dueAt,
}) {
  if (actionPlan.trim().isEmpty) {
    throw const ValidationError(
      message: 'Incident report failed validation.',
      fieldErrors: <String, String>{
        'action_plan': 'An action plan is required.',
      },
      code: 'incident_action_plan_missing',
    );
  }
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': IncidentStatus.actionPlan.wireValue,
    'action_plan': actionPlan.trim(),
    'action_plan_due_at': dueAt.toUtc().toIso8601String(),
    'updated_at': now,
  };
}

/// The change set that closes an incident.
Map<String, Object?> incidentCloseChanges({
  required String note,
  DateTime? at,
}) {
  if (note.trim().isEmpty) {
    throw const ValidationError(
      message: 'Incident report failed validation.',
      fieldErrors: <String, String>{
        'closure_note': 'A closure note is required.',
      },
      code: 'incident_closure_note_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': IncidentStatus.closed.wireValue,
    'closed_at': now,
    'closure_note': note.trim(),
    'updated_at': now,
  };
}

/// The change set that withdraws an incident report.
Map<String, Object?> incidentVoidChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Incident report failed validation.',
      fieldErrors: <String, String>{'void_reason': 'A reason is required.'},
      code: 'incident_void_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': IncidentStatus.voided.wireValue,
    'voided_at': now,
    'void_reason': reason.trim(),
    'updated_at': now,
  };
}

/// One measured clinical indicator over one period.
@immutable
final class ClinicalIndicator {
  /// Creates a clinical indicator reading.
  const ClinicalIndicator({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.code,
    required this.name,
    required this.category,
    required this.unit,
    required this.direction,
    required this.periodStart,
    required this.periodEnd,
    required this.numerator,
    required this.denominator,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.targetValue,
    this.sourceNote,
    this.publishedBy,
    this.publishedAt,
    this.retractedAt,
    this.retractReason,
    this.createdAt,
  });

  /// Validates and builds a new draft indicator row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String code,
    required String name,
    required DateTime periodStart,
    required DateTime periodEnd,
    required String createdBy,
    IndicatorCategory category = IndicatorCategory.operational,
    IndicatorUnit unit = IndicatorUnit.percent,
    IndicatorDirection direction = IndicatorDirection.lowerIsBetter,
    int numerator = 0,
    int denominator = 0,
    int? targetValue,
    String? sourceNote,
    String indicatorId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (code.trim().isEmpty) {
      fieldErrors['code'] = 'An indicator code is required.';
    }
    if (name.trim().isEmpty) {
      fieldErrors['name'] = 'An indicator name is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (numerator < 0) {
      fieldErrors['numerator'] = 'A count cannot be negative.';
    }
    if (denominator < 0) {
      fieldErrors['denominator'] = 'A count cannot be negative.';
    }
    if (targetValue != null && targetValue < 0) {
      fieldErrors['target_value'] = 'A target cannot be negative.';
    }
    if (periodEnd.isBefore(periodStart)) {
      fieldErrors['period_end'] = 'The period ends before it starts.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Clinical indicator failed validation.',
        fieldErrors: fieldErrors,
        code: 'clinical_indicator_invalid',
      );
    }
    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (indicatorId.isNotEmpty) 'id': indicatorId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'code': code.trim(),
      'name': name.trim(),
      'category': category.wireValue,
      'unit': unit.wireValue,
      'direction': direction.wireValue,
      'period_start': _date(periodStart),
      'period_end': _date(periodEnd),
      'numerator': numerator,
      'denominator': denominator,
      'target_value': targetValue,
      'source_note': _trimmed(sourceNote),
      'status': IndicatorStatus.draft.wireValue,
      'published_by': null,
      'published_at': null,
      'retracted_at': null,
      'retract_reason': null,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes an indicator from a local row.
  factory ClinicalIndicator.fromRow(Map<String, Object?> row) =>
      ClinicalIndicator(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        code: row['code']! as String,
        name: row['name']! as String,
        category: IndicatorCategory.fromWire(
          (row['category'] as String?) ??
              IndicatorCategory.operational.wireValue,
        ),
        unit: IndicatorUnit.fromWire(
          (row['unit'] as String?) ?? IndicatorUnit.percent.wireValue,
        ),
        direction: IndicatorDirection.fromWire(
          (row['direction'] as String?) ??
              IndicatorDirection.lowerIsBetter.wireValue,
        ),
        periodStart: _parseDate(row['period_start']),
        periodEnd: _parseDate(row['period_end']),
        numerator: _asInt(row['numerator']),
        denominator: _asInt(row['denominator']),
        status: IndicatorStatus.fromWire(
          (row['status'] as String?) ?? IndicatorStatus.draft.wireValue,
        ),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        targetValue: row['target_value'] == null
            ? null
            : _asInt(row['target_value']),
        sourceNote: row['source_note'] as String?,
        publishedBy: row['published_by'] as String?,
        publishedAt: _parseNullable(row['published_at']),
        retractedAt: _parseNullable(row['retracted_at']),
        retractReason: row['retract_reason'] as String?,
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility measured.
  final String facilityId;

  /// The indicator code.
  final String code;

  /// The indicator name.
  final String name;

  /// What the indicator measures.
  final IndicatorCategory category;

  /// How the ratio reads.
  final IndicatorUnit unit;

  /// Which way is good.
  final IndicatorDirection direction;

  /// The first day of the period.
  final DateTime periodStart;

  /// The last day of the period.
  final DateTime periodEnd;

  /// The count of events.
  final int numerator;

  /// The count of the population at risk.
  final int denominator;

  /// Lifecycle status.
  final IndicatorStatus status;

  /// Who raised the reading.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The figure the indicator is held to.
  final int? targetValue;

  /// Where the counts came from.
  final String? sourceNote;

  /// Who published the reading.
  final String? publishedBy;

  /// When the reading was published, UTC.
  final DateTime? publishedAt;

  /// When the reading was retracted, UTC.
  final DateTime? retractedAt;

  /// Why the reading was retracted.
  final String? retractReason;

  /// When the reading was raised, UTC.
  final DateTime? createdAt;

  /// The derived measured value.
  double? get value => indicatorValue(this);

  /// The derived target comparison.
  bool? get meetsTarget => indicatorMeetsTarget(this);

  /// Whether the reading is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the reading is published.
  bool get isPublished => status == IndicatorStatus.published;

  /// Whether the reading has a denominator to divide by.
  bool get hasDenominator => denominator > 0;
}

/// The change set that publishes a reading.
Map<String, Object?> indicatorPublishChanges({
  required String publishedBy,
  DateTime? at,
}) {
  if (publishedBy.isEmpty) {
    throw const ValidationError(
      message: 'Clinical indicator failed validation.',
      fieldErrors: <String, String>{
        'published_by': 'Who published it is required.',
      },
      code: 'clinical_indicator_publisher_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': IndicatorStatus.published.wireValue,
    'published_by': publishedBy,
    'published_at': now,
    'updated_at': now,
  };
}

/// The change set that retracts a published reading.
Map<String, Object?> indicatorRetractChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Clinical indicator failed validation.',
      fieldErrors: <String, String>{'retract_reason': 'A reason is required.'},
      code: 'clinical_indicator_retract_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': IndicatorStatus.retracted.wireValue,
    'retracted_at': now,
    'retract_reason': reason.trim(),
    'updated_at': now,
  };
}

String? _trimmed(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _date(DateTime value) {
  final DateTime utc = value.toUtc();
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${utc.month.toString().padLeft(2, '0')}-'
      '${utc.day.toString().padLeft(2, '0')}';
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

DateTime _parseDate(Object? value) {
  if (value is! String) {
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
  final List<String> parts = value.split('-');
  if (parts.length == 3) {
    final int? year = int.tryParse(parts[0]);
    final int? month = int.tryParse(parts[1]);
    final int? day = int.tryParse(
      parts[2].length > 2 ? parts[2].substring(0, 2) : parts[2],
    );
    if (year != null && month != null && day != null) {
      return DateTime.utc(year, month, day);
    }
  }
  return DateTime.parse(value).toUtc();
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.parse(value);
  }
  return 0;
}
