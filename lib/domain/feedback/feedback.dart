/// Patient Feedback & Grievance Redressal entities (Module 36).
///
/// Specification scope: "Patient Net Promoter Score (NPS) surveys, complaints
/// registry, departmental routing, and resolution SLA tracking."
///
/// This is the patient's voice: what the hospital hears about itself after the
/// care is delivered. It is distinct from the clinical record (an encounter
/// records what was done; a survey records how it was received) and from the
/// quality hub (an incident is a harm the hospital found in itself; a complaint
/// is a harm the patient brought to it).
///
/// Three records, mirroring the scope: the [FeedbackSurvey] response, the
/// [FeedbackComplaint] grievance with its departmental routing, and the
/// append-only [ComplaintRoutingEvent] history of where the case went.
///
/// The facts a stored copy would let drift are derived instead: the band a score
/// falls in and the net promoter score itself from the responses
/// ([npsBand], [netPromoterScore]), and the deadlines from the moment and the
/// severity ([complaintAcknowledgementWindow], [complaintResolutionWindow],
/// [feedbackFollowUpWindow], and the overdue markers built on them). Changing a
/// threshold re-derives every marker rather than stranding a stale flag.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Where a survey response was collected.
enum FeedbackTouchpoint {
  /// Outpatient department.
  opd('opd'),

  /// Inpatient ward.
  ipd('ipd'),

  /// Emergency department.
  emergency('emergency'),

  /// Diagnostics and imaging.
  diagnostics('diagnostics'),

  /// Pharmacy counter.
  pharmacy('pharmacy'),

  /// Billing and cash counter.
  billing('billing'),

  /// A remote consultation.
  telemedicine('telemedicine'),

  /// The discharge desk.
  discharge('discharge'),

  /// Anywhere else, described on the row.
  other('other');

  const FeedbackTouchpoint(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    FeedbackTouchpoint.opd => 'OPD',
    FeedbackTouchpoint.ipd => 'Inpatient ward',
    FeedbackTouchpoint.emergency => 'Emergency',
    FeedbackTouchpoint.diagnostics => 'Diagnostics',
    FeedbackTouchpoint.pharmacy => 'Pharmacy',
    FeedbackTouchpoint.billing => 'Billing',
    FeedbackTouchpoint.telemedicine => 'Telemedicine',
    FeedbackTouchpoint.discharge => 'Discharge',
    FeedbackTouchpoint.other => 'Other',
  };

  /// Parses a stored value.
  static FeedbackTouchpoint fromWire(String value) =>
      FeedbackTouchpoint.values.firstWhere(
        (FeedbackTouchpoint value_) => value_.wireValue == value,
        orElse: () => FeedbackTouchpoint.other,
      );
}

/// Lifecycle status of a survey response.
enum SurveyStatus {
  /// Captured; the only editable stage.
  recorded('recorded'),

  /// Followed up, with a note; terminal.
  actioned('actioned'),

  /// Withdrawn, with a reason; terminal.
  voided('voided');

  const SurveyStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    SurveyStatus.recorded => 'Recorded',
    SurveyStatus.actioned => 'Followed up',
    SurveyStatus.voided => 'Withdrawn',
  };

  /// Parses a stored value.
  static SurveyStatus fromWire(String value) => SurveyStatus.values.firstWhere(
    (SurveyStatus value_) => value_.wireValue == value,
    orElse: () => SurveyStatus.recorded,
  );

  /// Whether the response is settled.
  bool get isTerminal => this != SurveyStatus.recorded;
}

/// Whether a survey response may move from [from] to [to].
bool surveyCanTransition(SurveyStatus from, SurveyStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return to == SurveyStatus.actioned || to == SurveyStatus.voided;
}

/// Which band a Net Promoter Score falls in.
enum NpsBand {
  /// Nine or ten: would recommend.
  promoter('promoter'),

  /// Seven or eight: satisfied but not enthusiastic.
  passive('passive'),

  /// Six or below: would not recommend.
  detractor('detractor');

  const NpsBand(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    NpsBand.promoter => 'Promoter',
    NpsBand.passive => 'Passive',
    NpsBand.detractor => 'Detractor',
  };
}

/// The band a Net Promoter Score falls in.
///
/// The three bands are the definition of the score, not a setting, so a score of
/// nine is a promoter on every device.
NpsBand npsBand(int score) {
  if (score >= 9) {
    return NpsBand.promoter;
  }
  if (score >= 7) {
    return NpsBand.passive;
  }
  return NpsBand.detractor;
}

/// The net promoter score of a set of responses, as a percentage from -100 to
/// 100, or null when there are none.
///
/// Promoters minus detractors over the total, which is why the headline number
/// is computed from the responses rather than stored: a figure kept in a column
/// would drift from the answers behind it.
double? netPromoterScore(Iterable<int> scores) {
  int promoters = 0;
  int detractors = 0;
  int total = 0;
  for (final int score in scores) {
    total++;
    switch (npsBand(score)) {
      case NpsBand.promoter:
        promoters++;
      case NpsBand.detractor:
        detractors++;
      case NpsBand.passive:
        break;
    }
  }
  if (total == 0) {
    return null;
  }
  return (promoters - detractors) / total * 100;
}

/// How long a detractor has to be followed up before it is overdue.
const Duration feedbackFollowUpWindow = Duration(days: 3);

/// Whether a detractor has gone unfollowed for longer than the window.
///
/// Only a detractor has to be followed up: a promoter or a passive answer is
/// recorded and left. A settled response is never overdue.
bool isSurveyFollowUpOverdue({
  required FeedbackSurvey survey,
  required DateTime now,
}) {
  if (survey.status != SurveyStatus.recorded ||
      survey.band != NpsBand.detractor) {
    return false;
  }
  return now.toUtc().difference(survey.recordedAt.toUtc()) >
      feedbackFollowUpWindow;
}

/// What channel a grievance arrived through.
enum ComplaintChannel {
  /// Raised at a counter.
  counter('counter'),

  /// Telephoned in.
  phone('phone'),

  /// Emailed in.
  email('email'),

  /// Raised on the patient portal.
  portal('portal'),

  /// Arrived by letter.
  letter('letter'),

  /// Raised by a member of staff on the patient's behalf.
  staff('staff'),

  /// Anywhere else, described on the row.
  other('other');

  const ComplaintChannel(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ComplaintChannel.counter => 'At the counter',
    ComplaintChannel.phone => 'By telephone',
    ComplaintChannel.email => 'By email',
    ComplaintChannel.portal => 'Patient portal',
    ComplaintChannel.letter => 'By letter',
    ComplaintChannel.staff => 'Raised by staff',
    ComplaintChannel.other => 'Other',
  };

  /// Parses a stored value.
  static ComplaintChannel fromWire(String value) =>
      ComplaintChannel.values.firstWhere(
        (ComplaintChannel value_) => value_.wireValue == value,
        orElse: () => ComplaintChannel.other,
      );
}

/// What a grievance is about.
enum ComplaintCategory {
  /// Waiting to be seen.
  waitingTime('waiting_time'),

  /// How a member of staff behaved.
  staffBehaviour('staff_behaviour'),

  /// An invoice or a charge.
  billing('billing'),

  /// The care itself.
  clinicalCare('clinical_care'),

  /// Cleanliness.
  cleanliness('cleanliness'),

  /// Catering.
  food('food'),

  /// The building or equipment.
  facility('facility'),

  /// Confidentiality or dignity.
  privacy('privacy'),

  /// Anything else, described on the row.
  other('other');

  const ComplaintCategory(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ComplaintCategory.waitingTime => 'Waiting time',
    ComplaintCategory.staffBehaviour => 'Staff behaviour',
    ComplaintCategory.billing => 'Billing',
    ComplaintCategory.clinicalCare => 'Clinical care',
    ComplaintCategory.cleanliness => 'Cleanliness',
    ComplaintCategory.food => 'Food',
    ComplaintCategory.facility => 'Facility',
    ComplaintCategory.privacy => 'Privacy',
    ComplaintCategory.other => 'Other',
  };

  /// Parses a stored value.
  static ComplaintCategory fromWire(String value) =>
      ComplaintCategory.values.firstWhere(
        (ComplaintCategory value_) => value_.wireValue == value,
        orElse: () => ComplaintCategory.other,
      );
}

/// How pressing a grievance is.
enum ComplaintSeverity {
  /// Can wait a fortnight.
  low('low'),

  /// A week.
  medium('medium'),

  /// Three days.
  high('high');

  const ComplaintSeverity(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ComplaintSeverity.low => 'Low',
    ComplaintSeverity.medium => 'Medium',
    ComplaintSeverity.high => 'High',
  };

  /// Parses a stored value.
  static ComplaintSeverity fromWire(String value) =>
      ComplaintSeverity.values.firstWhere(
        (ComplaintSeverity value_) => value_.wireValue == value,
        orElse: () => ComplaintSeverity.low,
      );
}

/// Lifecycle status of a grievance.
enum ComplaintStatus {
  /// Taken at the counter; the only editable-by-facts stage.
  logged('logged'),

  /// Someone has told the complainant it is being looked at.
  acknowledged('acknowledged'),

  /// Under investigation.
  investigating('investigating'),

  /// The hospital has answered it.
  resolved('resolved'),

  /// The complainant has been told the answer; terminal.
  closed('closed'),

  /// Found to have no substance, with a reason; terminal.
  dismissed('dismissed'),

  /// Filed in error, with a reason; terminal.
  voided('voided');

  const ComplaintStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ComplaintStatus.logged => 'Logged',
    ComplaintStatus.acknowledged => 'Acknowledged',
    ComplaintStatus.investigating => 'Investigating',
    ComplaintStatus.resolved => 'Resolved',
    ComplaintStatus.closed => 'Closed',
    ComplaintStatus.dismissed => 'Dismissed',
    ComplaintStatus.voided => 'Withdrawn',
  };

  /// Parses a stored value.
  static ComplaintStatus fromWire(String value) =>
      ComplaintStatus.values.firstWhere(
        (ComplaintStatus value_) => value_.wireValue == value,
        orElse: () => ComplaintStatus.logged,
      );

  /// Whether the grievance still has to be worked.
  bool get isLive => !isTerminal;

  /// Whether the grievance is settled.
  bool get isTerminal =>
      this == ComplaintStatus.closed ||
      this == ComplaintStatus.dismissed ||
      this == ComplaintStatus.voided;

  /// Whether the complainant is still waiting to be acknowledged.
  bool get awaitsAcknowledgement => this == ComplaintStatus.logged;

  /// Whether the grievance is still waiting on an answer.
  bool get awaitsResolution =>
      this == ComplaintStatus.logged ||
      this == ComplaintStatus.acknowledged ||
      this == ComplaintStatus.investigating;
}

/// Whether a grievance may move from [from] to [to].
bool complaintCanTransition(ComplaintStatus from, ComplaintStatus to) {
  if (from.isTerminal) {
    return false;
  }
  return switch (from) {
    ComplaintStatus.logged =>
      to == ComplaintStatus.acknowledged ||
          to == ComplaintStatus.dismissed ||
          to == ComplaintStatus.voided,
    ComplaintStatus.acknowledged =>
      to == ComplaintStatus.investigating || to == ComplaintStatus.dismissed,
    ComplaintStatus.investigating =>
      to == ComplaintStatus.resolved || to == ComplaintStatus.dismissed,
    ComplaintStatus.resolved => to == ComplaintStatus.closed,
    ComplaintStatus.closed ||
    ComplaintStatus.dismissed ||
    ComplaintStatus.voided => false,
  };
}

/// How long a grievance may sit unacknowledged.
const Duration complaintAcknowledgementWindow = Duration(hours: 24);

/// How long a grievance of a given severity may take to resolve.
Duration complaintResolutionWindow(ComplaintSeverity severity) =>
    switch (severity) {
      ComplaintSeverity.high => const Duration(days: 3),
      ComplaintSeverity.medium => const Duration(days: 7),
      ComplaintSeverity.low => const Duration(days: 14),
    };

/// Whether a grievance has sat unacknowledged past its window.
bool isComplaintAcknowledgementOverdue({
  required FeedbackComplaint complaint,
  required DateTime now,
}) {
  if (!complaint.status.awaitsAcknowledgement) {
    return false;
  }
  return now.toUtc().difference(complaint.receivedAt.toUtc()) >
      complaintAcknowledgementWindow;
}

/// Whether a grievance has gone unresolved past its severity window.
///
/// A resolved or closed grievance is not overdue however long it took: the rule
/// marks what still has to happen, not what was slow.
bool isComplaintResolutionOverdue({
  required FeedbackComplaint complaint,
  required DateTime now,
}) {
  if (!complaint.status.awaitsResolution) {
    return false;
  }
  return now.toUtc().difference(complaint.receivedAt.toUtc()) >
      complaintResolutionWindow(complaint.severity);
}

/// Whether either deadline on a grievance has been missed.
bool isComplaintSlaBreached({
  required FeedbackComplaint complaint,
  required DateTime now,
}) =>
    isComplaintAcknowledgementOverdue(complaint: complaint, now: now) ||
    isComplaintResolutionOverdue(complaint: complaint, now: now);

/// What a routing event records.
enum RoutingEventType {
  /// The grievance was first taken.
  logged('logged'),

  /// It was sent to a department.
  routed('routed'),

  /// It was moved to another department.
  rerouted('rerouted'),

  /// It was escalated.
  escalated('escalated'),

  /// The complainant was contacted.
  contacted('contacted');

  const RoutingEventType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    RoutingEventType.logged => 'Logged',
    RoutingEventType.routed => 'Routed',
    RoutingEventType.rerouted => 'Re-routed',
    RoutingEventType.escalated => 'Escalated',
    RoutingEventType.contacted => 'Complainant contacted',
  };

  /// Parses a stored value.
  static RoutingEventType fromWire(String value) =>
      RoutingEventType.values.firstWhere(
        (RoutingEventType value_) => value_.wireValue == value,
        orElse: () => RoutingEventType.logged,
      );
}

/// One Net Promoter Score response.
@immutable
final class FeedbackSurvey {
  /// Creates a survey response.
  const FeedbackSurvey({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.surveyNumber,
    required this.touchpoint,
    required this.npsScore,
    required this.recordedAt,
    required this.recordedBy,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.patientId,
    this.encounterId,
    this.comment,
    this.actionNote,
    this.actionedBy,
    this.actionedAt,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new recorded response row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String surveyNumber,
    required int npsScore,
    required String recordedBy,
    required String createdBy,
    FeedbackTouchpoint touchpoint = FeedbackTouchpoint.opd,
    String? patientId,
    String? encounterId,
    String? comment,
    DateTime? recordedAt,
    String surveyId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (surveyNumber.trim().isEmpty) {
      fieldErrors['survey_number'] = 'A survey number is required.';
    }
    if (npsScore < 0 || npsScore > 10) {
      fieldErrors['nps_score'] = 'A score is between 0 and 10.';
    }
    if (recordedBy.isEmpty) {
      fieldErrors['recorded_by'] = 'Who recorded it is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Survey response failed validation.',
        fieldErrors: fieldErrors,
        code: 'feedback_survey_invalid',
      );
    }
    final DateTime at = (recordedAt ?? DateTime.now()).toUtc();
    final String stamp = at.toIso8601String();
    return <String, Object?>{
      if (surveyId.isNotEmpty) 'id': surveyId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'survey_number': surveyNumber.trim(),
      'patient_id': _trimmed(patientId),
      'encounter_id': _trimmed(encounterId),
      'touchpoint': touchpoint.wireValue,
      'nps_score': npsScore,
      'comment': _trimmed(comment),
      'recorded_at': stamp,
      'status': SurveyStatus.recorded.wireValue,
      'action_note': null,
      'actioned_by': null,
      'actioned_at': null,
      'voided_at': null,
      'void_reason': null,
      'recorded_by': recordedBy,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a response from a local row.
  factory FeedbackSurvey.fromRow(Map<String, Object?> row) => FeedbackSurvey(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    facilityId: row['facility_id']! as String,
    surveyNumber: row['survey_number']! as String,
    touchpoint: FeedbackTouchpoint.fromWire(
      (row['touchpoint'] as String?) ?? FeedbackTouchpoint.other.wireValue,
    ),
    npsScore: _asInt(row['nps_score']),
    recordedAt: _parse(row['recorded_at']),
    recordedBy: row['recorded_by']! as String,
    status: SurveyStatus.fromWire(
      (row['status'] as String?) ?? SurveyStatus.recorded.wireValue,
    ),
    createdBy: row['created_by']! as String,
    updatedAt: _parse(row['updated_at']),
    patientId: row['patient_id'] as String?,
    encounterId: row['encounter_id'] as String?,
    comment: row['comment'] as String?,
    actionNote: row['action_note'] as String?,
    actionedBy: row['actioned_by'] as String?,
    actionedAt: _parseNullable(row['actioned_at']),
    voidedAt: _parseNullable(row['voided_at']),
    voidReason: row['void_reason'] as String?,
    createdAt: _parseNullable(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility where the response was collected.
  final String facilityId;

  /// The hospital's survey number.
  final String surveyNumber;

  /// Where the response was collected.
  final FeedbackTouchpoint touchpoint;

  /// The score, from zero to ten.
  final int npsScore;

  /// When the response was captured, UTC.
  final DateTime recordedAt;

  /// Who captured it.
  final String recordedBy;

  /// Lifecycle status.
  final SurveyStatus status;

  /// Who raised the response.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The patient, when the response is not anonymous.
  final String? patientId;

  /// The encounter the response follows, when there is one.
  final String? encounterId;

  /// What the patient chose to add.
  final String? comment;

  /// What was done about a detractor.
  final String? actionNote;

  /// Who followed it up.
  final String? actionedBy;

  /// When it was followed up, UTC.
  final DateTime? actionedAt;

  /// When the response was withdrawn, UTC.
  final DateTime? voidedAt;

  /// Why the response was withdrawn.
  final String? voidReason;

  /// When the response was raised, UTC.
  final DateTime? createdAt;

  /// The derived band.
  NpsBand get band => npsBand(npsScore);

  /// Whether the response is a detractor.
  bool get isDetractor => band == NpsBand.detractor;

  /// Whether the response is a promoter.
  bool get isPromoter => band == NpsBand.promoter;

  /// Whether the response is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the response is anonymous.
  bool get isAnonymous => patientId == null;
}

/// The change set that follows up a detractor.
Map<String, Object?> surveyActionChanges({
  required String note,
  required String actionedBy,
  DateTime? at,
}) {
  if (note.trim().isEmpty) {
    throw const ValidationError(
      message: 'Survey response failed validation.',
      fieldErrors: <String, String>{'action_note': 'A note is required.'},
      code: 'feedback_action_note_missing',
    );
  }
  if (actionedBy.isEmpty) {
    throw const ValidationError(
      message: 'Survey response failed validation.',
      fieldErrors: <String, String>{'actioned_by': 'Who acted is required.'},
      code: 'feedback_action_actor_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': SurveyStatus.actioned.wireValue,
    'action_note': note.trim(),
    'actioned_by': actionedBy,
    'actioned_at': now,
    'updated_at': now,
  };
}

/// The change set that withdraws a response.
Map<String, Object?> surveyVoidChanges({required String reason, DateTime? at}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Survey response failed validation.',
      fieldErrors: <String, String>{'void_reason': 'A reason is required.'},
      code: 'feedback_void_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': SurveyStatus.voided.wireValue,
    'voided_at': now,
    'void_reason': reason.trim(),
    'updated_at': now,
  };
}

/// One grievance, routed to a department and owned by a person.
@immutable
final class FeedbackComplaint {
  /// Creates a grievance.
  const FeedbackComplaint({
    required this.id,
    required this.tenantId,
    required this.facilityId,
    required this.complaintNumber,
    required this.complainantName,
    required this.channel,
    required this.category,
    required this.severity,
    required this.description,
    required this.receivedAt,
    required this.loggedBy,
    required this.status,
    required this.createdBy,
    required this.updatedAt,
    this.patientId,
    this.complainantContact,
    this.routedDepartmentId,
    this.routedTo,
    this.routedAt,
    this.acknowledgedAt,
    this.investigationStartedAt,
    this.resolvedAt,
    this.resolvedBy,
    this.resolutionSummary,
    this.closedAt,
    this.closureNote,
    this.dismissedAt,
    this.dismissReason,
    this.voidedAt,
    this.voidReason,
    this.createdAt,
  });

  /// Validates and builds a new logged grievance row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String facilityId,
    required String complaintNumber,
    required String complainantName,
    required String description,
    required String loggedBy,
    required String createdBy,
    ComplaintChannel channel = ComplaintChannel.counter,
    ComplaintCategory category = ComplaintCategory.other,
    ComplaintSeverity severity = ComplaintSeverity.medium,
    String? patientId,
    String? complainantContact,
    String? routedDepartmentId,
    String? routedTo,
    DateTime? receivedAt,
    String complaintId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (facilityId.isEmpty) {
      fieldErrors['facility_id'] = 'A facility is required.';
    }
    if (complaintNumber.trim().isEmpty) {
      fieldErrors['complaint_number'] = 'A complaint number is required.';
    }
    if (complainantName.trim().isEmpty) {
      fieldErrors['complainant_name'] = 'Who complained is required.';
    }
    if (description.trim().isEmpty) {
      fieldErrors['description'] = 'What the complaint is about is required.';
    }
    if (loggedBy.isEmpty) {
      fieldErrors['logged_by'] = 'Who took it is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Grievance failed validation.',
        fieldErrors: fieldErrors,
        code: 'feedback_complaint_invalid',
      );
    }
    final DateTime at = (receivedAt ?? DateTime.now()).toUtc();
    final String stamp = at.toIso8601String();
    final String? department = _trimmed(routedDepartmentId);
    final String? owner = _trimmed(routedTo);
    return <String, Object?>{
      if (complaintId.isNotEmpty) 'id': complaintId,
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'complaint_number': complaintNumber.trim(),
      'patient_id': _trimmed(patientId),
      'complainant_name': complainantName.trim(),
      'complainant_contact': _trimmed(complainantContact),
      'channel': channel.wireValue,
      'category': category.wireValue,
      'severity': severity.wireValue,
      'description': description.trim(),
      'received_at': stamp,
      'routed_department_id': department,
      'routed_to': owner,
      'routed_at': department == null && owner == null ? null : stamp,
      'status': ComplaintStatus.logged.wireValue,
      'acknowledged_at': null,
      'investigation_started_at': null,
      'resolved_at': null,
      'resolved_by': null,
      'resolution_summary': null,
      'closed_at': null,
      'closure_note': null,
      'dismissed_at': null,
      'dismiss_reason': null,
      'voided_at': null,
      'void_reason': null,
      'logged_by': loggedBy,
      'created_by': createdBy,
      'created_at': stamp,
      'updated_at': stamp,
    };
  }

  /// Materializes a grievance from a local row.
  factory FeedbackComplaint.fromRow(Map<String, Object?> row) =>
      FeedbackComplaint(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        facilityId: row['facility_id']! as String,
        complaintNumber: row['complaint_number']! as String,
        complainantName: row['complainant_name']! as String,
        channel: ComplaintChannel.fromWire(
          (row['channel'] as String?) ?? ComplaintChannel.other.wireValue,
        ),
        category: ComplaintCategory.fromWire(
          (row['category'] as String?) ?? ComplaintCategory.other.wireValue,
        ),
        severity: ComplaintSeverity.fromWire(
          (row['severity'] as String?) ?? ComplaintSeverity.low.wireValue,
        ),
        description: row['description']! as String,
        receivedAt: _parse(row['received_at']),
        loggedBy: row['logged_by']! as String,
        status: ComplaintStatus.fromWire(
          (row['status'] as String?) ?? ComplaintStatus.logged.wireValue,
        ),
        createdBy: row['created_by']! as String,
        updatedAt: _parse(row['updated_at']),
        patientId: row['patient_id'] as String?,
        complainantContact: row['complainant_contact'] as String?,
        routedDepartmentId: row['routed_department_id'] as String?,
        routedTo: row['routed_to'] as String?,
        routedAt: _parseNullable(row['routed_at']),
        acknowledgedAt: _parseNullable(row['acknowledged_at']),
        investigationStartedAt: _parseNullable(row['investigation_started_at']),
        resolvedAt: _parseNullable(row['resolved_at']),
        resolvedBy: row['resolved_by'] as String?,
        resolutionSummary: row['resolution_summary'] as String?,
        closedAt: _parseNullable(row['closed_at']),
        closureNote: row['closure_note'] as String?,
        dismissedAt: _parseNullable(row['dismissed_at']),
        dismissReason: row['dismiss_reason'] as String?,
        voidedAt: _parseNullable(row['voided_at']),
        voidReason: row['void_reason'] as String?,
        createdAt: _parseNullable(row['created_at']),
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The facility the grievance concerns.
  final String facilityId;

  /// The hospital's complaint number.
  final String complaintNumber;

  /// Who complained.
  final String complainantName;

  /// How the grievance arrived.
  final ComplaintChannel channel;

  /// What it is about.
  final ComplaintCategory category;

  /// How pressing it is, which sets the resolution window.
  final ComplaintSeverity severity;

  /// The grievance itself.
  final String description;

  /// When it was received, UTC.
  final DateTime receivedAt;

  /// Who took it at the counter.
  final String loggedBy;

  /// Lifecycle status.
  final ComplaintStatus status;

  /// Who raised the row.
  final String createdBy;

  /// Last change, UTC.
  final DateTime updatedAt;

  /// The patient, when the grievance is tied to one.
  final String? patientId;

  /// How to reach the complainant.
  final String? complainantContact;

  /// The department the grievance is routed to.
  final String? routedDepartmentId;

  /// The person who owns the grievance.
  final String? routedTo;

  /// When it was routed, UTC.
  final DateTime? routedAt;

  /// When the complainant was told it is being looked at, UTC.
  final DateTime? acknowledgedAt;

  /// When the investigation opened, UTC.
  final DateTime? investigationStartedAt;

  /// When it was answered, UTC.
  final DateTime? resolvedAt;

  /// Who answered it.
  final String? resolvedBy;

  /// The answer.
  final String? resolutionSummary;

  /// When the complainant was told the answer, UTC.
  final DateTime? closedAt;

  /// How the close was recorded.
  final String? closureNote;

  /// When it was found to have no substance, UTC.
  final DateTime? dismissedAt;

  /// Why it had no substance.
  final String? dismissReason;

  /// When it was withdrawn, UTC.
  final DateTime? voidedAt;

  /// Why it was withdrawn.
  final String? voidReason;

  /// When the row was raised, UTC.
  final DateTime? createdAt;

  /// Whether the grievance still has to be worked.
  bool get isLive => status.isLive;

  /// Whether the grievance is settled.
  bool get isTerminal => status.isTerminal;

  /// Whether the complainant is still waiting to be acknowledged.
  bool get isUnacknowledged => status.awaitsAcknowledgement;

  /// Whether it was answered.
  bool get isResolved =>
      status == ComplaintStatus.resolved || status == ComplaintStatus.closed;

  /// Whether it is routed to anyone.
  bool get isRouted => routedDepartmentId != null || routedTo != null;

  /// The derived resolution window for this severity.
  Duration get resolutionWindow => complaintResolutionWindow(severity);
}

/// The change set that acknowledges a grievance.
Map<String, Object?> complaintAcknowledgeChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ComplaintStatus.acknowledged.wireValue,
    'acknowledged_at': now,
    'updated_at': now,
  };
}

/// The change set that routes or re-routes a grievance.
///
/// Routing does not move the status: the case is still logged or under
/// investigation, it simply now belongs to someone else.
Map<String, Object?> complaintRouteChanges({
  String? departmentId,
  String? routedTo,
  DateTime? at,
}) {
  final String? department = _trimmed(departmentId);
  final String? owner = _trimmed(routedTo);
  if (department == null && owner == null) {
    throw const ValidationError(
      message: 'Grievance failed validation.',
      fieldErrors: <String, String>{
        'routed_department_id': 'A department or an owner is required.',
      },
      code: 'feedback_routing_target_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'routed_department_id': ?department,
    'routed_to': ?owner,
    'routed_at': now,
    'updated_at': now,
  };
}

/// The change set that opens an investigation.
Map<String, Object?> complaintInvestigateChanges({DateTime? at}) {
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ComplaintStatus.investigating.wireValue,
    'investigation_started_at': now,
    'updated_at': now,
  };
}

/// The change set that answers a grievance.
Map<String, Object?> complaintResolveChanges({
  required String summary,
  required String resolvedBy,
  DateTime? at,
}) {
  final Map<String, String> fieldErrors = <String, String>{};
  if (summary.trim().isEmpty) {
    fieldErrors['resolution_summary'] = 'The answer is required.';
  }
  if (resolvedBy.isEmpty) {
    fieldErrors['resolved_by'] = 'Who answered it is required.';
  }
  if (fieldErrors.isNotEmpty) {
    throw ValidationError(
      message: 'Grievance failed validation.',
      fieldErrors: fieldErrors,
      code: 'feedback_resolution_invalid',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ComplaintStatus.resolved.wireValue,
    'resolved_at': now,
    'resolved_by': resolvedBy,
    'resolution_summary': summary.trim(),
    'updated_at': now,
  };
}

/// The change set that closes a resolved grievance.
Map<String, Object?> complaintCloseChanges({
  required String note,
  DateTime? at,
}) {
  if (note.trim().isEmpty) {
    throw const ValidationError(
      message: 'Grievance failed validation.',
      fieldErrors: <String, String>{'closure_note': 'A note is required.'},
      code: 'feedback_closure_note_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ComplaintStatus.closed.wireValue,
    'closed_at': now,
    'closure_note': note.trim(),
    'updated_at': now,
  };
}

/// The change set that dismisses a grievance.
Map<String, Object?> complaintDismissChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Grievance failed validation.',
      fieldErrors: <String, String>{'dismiss_reason': 'A reason is required.'},
      code: 'feedback_dismiss_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ComplaintStatus.dismissed.wireValue,
    'dismissed_at': now,
    'dismiss_reason': reason.trim(),
    'updated_at': now,
  };
}

/// The change set that withdraws a grievance filed in error.
Map<String, Object?> complaintVoidChanges({
  required String reason,
  DateTime? at,
}) {
  if (reason.trim().isEmpty) {
    throw const ValidationError(
      message: 'Grievance failed validation.',
      fieldErrors: <String, String>{'void_reason': 'A reason is required.'},
      code: 'feedback_complaint_void_reason_missing',
    );
  }
  final String now = (at ?? DateTime.now()).toUtc().toIso8601String();
  return <String, Object?>{
    'status': ComplaintStatus.voided.wireValue,
    'voided_at': now,
    'void_reason': reason.trim(),
    'updated_at': now,
  };
}

/// One routing event in a grievance's history.
@immutable
final class ComplaintRoutingEvent {
  /// Creates a routing event.
  const ComplaintRoutingEvent({
    required this.id,
    required this.tenantId,
    required this.complaintId,
    required this.eventType,
    required this.note,
    required this.occurredAt,
    required this.recordedBy,
    this.fromDepartmentId,
    this.toDepartmentId,
    this.assignedTo,
  });

  /// Validates and builds a routing event row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String complaintId,
    required String note,
    required String recordedBy,
    RoutingEventType eventType = RoutingEventType.routed,
    String? fromDepartmentId,
    String? toDepartmentId,
    String? assignedTo,
    DateTime? occurredAt,
    String eventId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (complaintId.isEmpty) {
      fieldErrors['complaint_id'] = 'The grievance is required.';
    }
    if (note.trim().isEmpty) {
      fieldErrors['note'] = 'A note is required.';
    }
    if (recordedBy.isEmpty) {
      fieldErrors['recorded_by'] = 'Who recorded it is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Routing event failed validation.',
        fieldErrors: fieldErrors,
        code: 'routing_event_invalid',
      );
    }
    final DateTime at = (occurredAt ?? DateTime.now()).toUtc();
    return <String, Object?>{
      if (eventId.isNotEmpty) 'id': eventId,
      'tenant_id': tenantId,
      'complaint_id': complaintId,
      'event_type': eventType.wireValue,
      'from_department_id': _trimmed(fromDepartmentId),
      'to_department_id': _trimmed(toDepartmentId),
      'assigned_to': _trimmed(assignedTo),
      'note': note.trim(),
      'occurred_at': at.toIso8601String(),
      'recorded_by': recordedBy,
      'created_at': at.toIso8601String(),
    };
  }

  /// Materializes a routing event from a local row.
  factory ComplaintRoutingEvent.fromRow(Map<String, Object?> row) =>
      ComplaintRoutingEvent(
        id: row['id']! as String,
        tenantId: row['tenant_id']! as String,
        complaintId: row['complaint_id']! as String,
        eventType: RoutingEventType.fromWire(
          (row['event_type'] as String?) ?? RoutingEventType.logged.wireValue,
        ),
        note: row['note']! as String,
        occurredAt: _parse(row['occurred_at']),
        recordedBy: row['recorded_by']! as String,
        fromDepartmentId: row['from_department_id'] as String?,
        toDepartmentId: row['to_department_id'] as String?,
        assignedTo: row['assigned_to'] as String?,
      );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The grievance this event belongs to.
  final String complaintId;

  /// What the event records.
  final RoutingEventType eventType;

  /// The note that explains it.
  final String note;

  /// When it happened, UTC.
  final DateTime occurredAt;

  /// Who recorded it.
  final String recordedBy;

  /// The department the case came from.
  final String? fromDepartmentId;

  /// The department the case went to.
  final String? toDepartmentId;

  /// The person now holding it.
  final String? assignedTo;

  /// Whether this event moved the case between departments.
  bool get isMovement =>
      eventType == RoutingEventType.routed ||
      eventType == RoutingEventType.rerouted ||
      eventType == RoutingEventType.escalated;
}

String? _trimmed(String? value) {
  if (value == null) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime _parse(Object? value) => value is String
    ? DateTime.parse(value).toUtc()
    : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

DateTime? _parseNullable(Object? value) =>
    value is String ? DateTime.parse(value).toUtc() : null;

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
