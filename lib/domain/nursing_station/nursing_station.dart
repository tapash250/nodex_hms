/// Nurse ward station entities (Module 06).
///
/// Specification scope: "Beds, vitals, handover, task queues, MAR, urgent
/// alerts."
///
/// Beds (Module 11) and the MAR (Module 25 medication administration) are not
/// modelled here: the ward station reads them. What lives here is the routine
/// general-ward observation, the shift handover and the ward task queue.
///
/// The alert band derived from an observation is deliberately conservative and
/// advisory. It is a triage *aid* for the board, not a validated early-warning
/// score, and it never replaces clinical judgement or the unit's charted
/// escalation tool. That is why it is a pure function over one observation
/// rather than a score that looks authoritative.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Level of consciousness, as observed.
enum ConsciousnessLevel {
  /// Fully awake.
  alert('alert'),

  /// Responds to voice.
  voice('voice'),

  /// Responds to pain.
  pain('pain'),

  /// Unresponsive.
  unresponsive('unresponsive');

  const ConsciousnessLevel(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    ConsciousnessLevel.alert => 'Alert',
    ConsciousnessLevel.voice => 'Responds to voice',
    ConsciousnessLevel.pain => 'Responds to pain',
    ConsciousnessLevel.unresponsive => 'Unresponsive',
  };

  /// Parses a stored value.
  static ConsciousnessLevel fromWire(String value) =>
      ConsciousnessLevel.values.firstWhere(
        (ConsciousnessLevel level) => level.wireValue == value,
        orElse: () => ConsciousnessLevel.alert,
      );
}

/// The advisory band a single observation falls into.
enum VitalAlert {
  /// Within normal limits.
  normal('normal'),

  /// A single parameter is outside normal limits.
  warning('warning'),

  /// A parameter is at a level that warrants immediate review.
  critical('critical');

  const VitalAlert(this.wireValue);

  /// Stored/label value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    VitalAlert.normal => 'Normal',
    VitalAlert.warning => 'Watch',
    VitalAlert.critical => 'Urgent',
  };

  /// Whether the observation should draw attention on the board.
  bool get isUrgent => this != VitalAlert.normal;
}

/// Derives the advisory [VitalAlert] band for an observation.
///
/// Thresholds are a simplified, single-observation triage aid. They are not a
/// validated early-warning score and must not be used as one.
VitalAlert wardVitalAlert(WardVital vital) {
  final double? temp = vital.temperatureCelsius;
  final int? pulse = vital.pulseBpm;
  final int? resp = vital.respiratoryRate;
  final int? systolic = vital.systolicBp;
  final int? spo2 = vital.spo2;
  final int? pain = vital.painScore;

  // Critical first: a parameter in this band overrides every warning.
  if (spo2 != null && spo2 <= 91) return VitalAlert.critical;
  if (systolic != null && systolic <= 90) return VitalAlert.critical;
  if (pulse != null && (pulse <= 40 || pulse >= 131)) {
    return VitalAlert.critical;
  }
  if (resp != null && (resp <= 8 || resp >= 25)) return VitalAlert.critical;
  if (temp != null && temp <= 35.0) return VitalAlert.critical;
  if (vital.consciousness != ConsciousnessLevel.alert) {
    return VitalAlert.critical;
  }

  if (spo2 != null && spo2 <= 93) return VitalAlert.warning;
  if (systolic != null && (systolic <= 100 || systolic >= 220)) {
    return VitalAlert.warning;
  }
  if (pulse != null && (pulse <= 50 || pulse >= 111)) return VitalAlert.warning;
  if (resp != null && (resp <= 11 || resp >= 21)) return VitalAlert.warning;
  if (temp != null && (temp <= 36.0 || temp >= 38.1)) return VitalAlert.warning;
  if (pain != null && pain >= 7) return VitalAlert.warning;
  if (vital.onOxygen) return VitalAlert.warning;

  return VitalAlert.normal;
}

/// A routine general-ward vital sign observation.
@immutable
final class WardVital {
  /// Creates an observation.
  const WardVital({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.wardId,
    required this.recordedBy,
    required this.observedAt,
    required this.consciousness,
    required this.onOxygen,
    this.encounterId,
    this.bedId,
    this.temperatureCelsius,
    this.pulseBpm,
    this.respiratoryRate,
    this.systolicBp,
    this.diastolicBp,
    this.spo2,
    this.painScore,
    this.notes,
    this.createdAt,
  });

  /// Validates and builds a new observation row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String patientId,
    required String wardId,
    required String recordedBy,
    String? encounterId,
    String? bedId,
    String? observedAt,
    double? temperatureCelsius,
    int? pulseBpm,
    int? respiratoryRate,
    int? systolicBp,
    int? diastolicBp,
    int? spo2,
    int? painScore,
    ConsciousnessLevel consciousness = ConsciousnessLevel.alert,
    bool onOxygen = false,
    String? notes,
    String vitalId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (patientId.isEmpty) {
      fieldErrors['patient_id'] = 'Patient is required.';
    }
    if (wardId.isEmpty) {
      fieldErrors['ward_id'] = 'Ward is required.';
    }
    if (recordedBy.isEmpty) {
      fieldErrors['recorded_by'] = 'Recorder is required.';
    }
    final bool hasMeasurement =
        temperatureCelsius != null ||
        pulseBpm != null ||
        respiratoryRate != null ||
        systolicBp != null ||
        diastolicBp != null ||
        spo2 != null ||
        painScore != null;
    if (!hasMeasurement) {
      fieldErrors['observed_at'] = 'Record at least one measurement.';
    }
    if (temperatureCelsius != null &&
        (temperatureCelsius < 25 || temperatureCelsius > 45)) {
      fieldErrors['temperature_celsius'] = 'Outside a plausible range.';
    }
    if (pulseBpm != null && (pulseBpm < 20 || pulseBpm > 300)) {
      fieldErrors['pulse_bpm'] = 'Outside a plausible range.';
    }
    if (respiratoryRate != null &&
        (respiratoryRate < 4 || respiratoryRate > 80)) {
      fieldErrors['respiratory_rate'] = 'Outside a plausible range.';
    }
    if (systolicBp != null && (systolicBp < 40 || systolicBp > 300)) {
      fieldErrors['systolic_bp'] = 'Outside a plausible range.';
    }
    if (diastolicBp != null && (diastolicBp < 20 || diastolicBp > 200)) {
      fieldErrors['diastolic_bp'] = 'Outside a plausible range.';
    }
    if (spo2 != null && (spo2 < 1 || spo2 > 100)) {
      fieldErrors['spo2'] = 'Outside a plausible range.';
    }
    if (painScore != null && (painScore < 0 || painScore > 10)) {
      fieldErrors['pain_score'] = 'Expected 0 to 10.';
    }
    if (systolicBp != null &&
        diastolicBp != null &&
        systolicBp <= diastolicBp) {
      fieldErrors['diastolic_bp'] = 'Must be below the systolic value.';
    }
    final DateTime? observed = observedAt == null
        ? DateTime.now().toUtc()
        : DateTime.tryParse(observedAt)?.toUtc();
    if (observed == null) {
      fieldErrors['observed_at'] = 'Expected an ISO-8601 timestamp.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Ward observation failed validation.',
        fieldErrors: fieldErrors,
        code: 'ward_vitals_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (vitalId.isNotEmpty) 'id': vitalId,
      'tenant_id': tenantId,
      'patient_id': patientId,
      'encounter_id': encounterId,
      'ward_id': wardId,
      'bed_id': bedId,
      'recorded_by': recordedBy,
      'observed_at': observed!.toIso8601String(),
      'temperature_celsius': temperatureCelsius,
      'pulse_bpm': pulseBpm,
      'respiratory_rate': respiratoryRate,
      'systolic_bp': systolicBp,
      'diastolic_bp': diastolicBp,
      'spo2': spo2,
      'pain_score': painScore,
      'consciousness': consciousness.wireValue,
      'on_oxygen': onOxygen,
      'notes': _trimmed(notes),
      'created_at': now,
    };
  }

  /// Materializes an observation from a local row.
  factory WardVital.fromRow(Map<String, Object?> row) => WardVital(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    patientId: row['patient_id']! as String,
    wardId: row['ward_id']! as String,
    recordedBy: row['recorded_by']! as String,
    observedAt: row['observed_at']! as String,
    consciousness: ConsciousnessLevel.fromWire(row['consciousness']! as String),
    onOxygen: _asBool(row['on_oxygen']),
    encounterId: row['encounter_id'] as String?,
    bedId: row['bed_id'] as String?,
    temperatureCelsius: _asDouble(row['temperature_celsius']),
    pulseBpm: _asIntOrNull(row['pulse_bpm']),
    respiratoryRate: _asIntOrNull(row['respiratory_rate']),
    systolicBp: _asIntOrNull(row['systolic_bp']),
    diastolicBp: _asIntOrNull(row['diastolic_bp']),
    spo2: _asIntOrNull(row['spo2']),
    painScore: _asIntOrNull(row['pain_score']),
    notes: row['notes'] as String?,
    createdAt: _parse(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The observed patient.
  final String patientId;

  /// The admitting encounter, when linked.
  final String? encounterId;

  /// The ward the observation was made in.
  final String wardId;

  /// The bed, when the patient is in one.
  final String? bedId;

  /// The clinician who recorded it.
  final String recordedBy;

  /// When the observation was made, ISO-8601.
  final String observedAt;

  /// Temperature in Celsius.
  final double? temperatureCelsius;

  /// Pulse, beats per minute.
  final int? pulseBpm;

  /// Respiratory rate, breaths per minute.
  final int? respiratoryRate;

  /// Systolic blood pressure.
  final int? systolicBp;

  /// Diastolic blood pressure.
  final int? diastolicBp;

  /// Peripheral oxygen saturation, percent.
  final int? spo2;

  /// Pain score, 0–10.
  final int? painScore;

  /// Level of consciousness.
  final ConsciousnessLevel consciousness;

  /// Whether supplemental oxygen is in use.
  final bool onOxygen;

  /// Free-text note.
  final String? notes;

  final DateTime? createdAt;

  /// The advisory band this observation falls into.
  VitalAlert get alert => wardVitalAlert(this);
}

/// A shift nursing handover for a ward.
@immutable
final class WardHandover {
  /// Creates a handover.
  const WardHandover({
    required this.id,
    required this.tenantId,
    required this.wardId,
    required this.fromUser,
    required this.handoverAt,
    required this.summary,
    this.shiftId,
    this.toUser,
    this.pendingItems,
    this.createdAt,
  });

  /// Validates and builds a new handover row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String wardId,
    required String fromUser,
    required String summary,
    String? shiftId,
    String? toUser,
    String? handoverAt,
    String? pendingItems,
    String handoverId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (wardId.isEmpty) {
      fieldErrors['ward_id'] = 'Ward is required.';
    }
    if (fromUser.isEmpty) {
      fieldErrors['from_user'] = 'Outgoing nurse is required.';
    }
    if (summary.trim().isEmpty) {
      fieldErrors['summary'] = 'A handover summary is required.';
    }
    final DateTime? at = handoverAt == null
        ? DateTime.now().toUtc()
        : DateTime.tryParse(handoverAt)?.toUtc();
    if (at == null) {
      fieldErrors['handover_at'] = 'Expected an ISO-8601 timestamp.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Ward handover failed validation.',
        fieldErrors: fieldErrors,
        code: 'ward_handover_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (handoverId.isNotEmpty) 'id': handoverId,
      'tenant_id': tenantId,
      'ward_id': wardId,
      'shift_id': shiftId,
      'from_user': fromUser,
      'to_user': toUser,
      'handover_at': at!.toIso8601String(),
      'summary': summary.trim(),
      'pending_items': _trimmed(pendingItems),
      'created_at': now,
    };
  }

  /// Materializes a handover from a local row.
  factory WardHandover.fromRow(Map<String, Object?> row) => WardHandover(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    wardId: row['ward_id']! as String,
    fromUser: row['from_user']! as String,
    handoverAt: row['handover_at']! as String,
    summary: row['summary']! as String,
    shiftId: row['shift_id'] as String?,
    toUser: row['to_user'] as String?,
    pendingItems: row['pending_items'] as String?,
    createdAt: _parse(row['created_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The ward handed over.
  final String wardId;

  /// The shift this handover closes, when linked.
  final String? shiftId;

  /// The outgoing nurse.
  final String fromUser;

  /// The incoming nurse, when named.
  final String? toUser;

  /// When the handover was recorded.
  final String handoverAt;

  /// The handover summary.
  final String summary;

  /// Work left for the incoming shift.
  final String? pendingItems;

  final DateTime? createdAt;
}

/// The kind of work a ward task represents.
enum WardTaskType {
  /// Take observations.
  observation('observation'),

  /// Administer medication.
  medication('medication'),

  /// Collect a sample.
  sample('sample'),

  /// Mobilise the patient.
  mobility('mobility'),

  /// Personal care.
  hygiene('hygiene'),

  /// Chart or file documentation.
  documentation('documentation'),

  /// Anything else.
  other('other');

  const WardTaskType(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    WardTaskType.observation => 'Observation',
    WardTaskType.medication => 'Medication',
    WardTaskType.sample => 'Sample',
    WardTaskType.mobility => 'Mobility',
    WardTaskType.hygiene => 'Hygiene',
    WardTaskType.documentation => 'Documentation',
    WardTaskType.other => 'Other',
  };

  /// Parses a stored value.
  static WardTaskType fromWire(String value) => WardTaskType.values.firstWhere(
    (WardTaskType type) => type.wireValue == value,
    orElse: () => WardTaskType.other,
  );
}

/// How soon a ward task needs doing.
enum WardTaskPriority {
  /// Can wait.
  routine('routine'),

  /// Should be done this shift.
  urgent('urgent'),

  /// Now.
  stat('stat');

  const WardTaskPriority(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    WardTaskPriority.routine => 'Routine',
    WardTaskPriority.urgent => 'Urgent',
    WardTaskPriority.stat => 'STAT',
  };

  /// Parses a stored value.
  static WardTaskPriority fromWire(String value) =>
      WardTaskPriority.values.firstWhere(
        (WardTaskPriority priority) => priority.wireValue == value,
        orElse: () => WardTaskPriority.routine,
      );
}

/// Where a ward task stands.
enum WardTaskStatus {
  /// Not yet started.
  open('open'),

  /// Being worked on.
  inProgress('in_progress'),

  /// Finished.
  done('done'),

  /// Abandoned.
  cancelled('cancelled');

  const WardTaskStatus(this.wireValue);

  /// Stored value.
  final String wireValue;

  /// Human-readable label.
  String get label => switch (this) {
    WardTaskStatus.open => 'Open',
    WardTaskStatus.inProgress => 'In progress',
    WardTaskStatus.done => 'Done',
    WardTaskStatus.cancelled => 'Cancelled',
  };

  /// Parses a stored value.
  static WardTaskStatus fromWire(String value) =>
      WardTaskStatus.values.firstWhere(
        (WardTaskStatus status) => status.wireValue == value,
        orElse: () => WardTaskStatus.open,
      );

  /// Whether the task is closed.
  bool get isTerminal =>
      this == WardTaskStatus.done || this == WardTaskStatus.cancelled;

  /// Whether the task still needs attention.
  bool get isOpen => !isTerminal;
}

/// A unit of delegated nursing work.
@immutable
final class WardTask {
  /// Creates a ward task.
  const WardTask({
    required this.id,
    required this.tenantId,
    required this.wardId,
    required this.title,
    required this.taskType,
    required this.priority,
    required this.status,
    required this.createdBy,
    this.patientId,
    this.encounterId,
    this.detail,
    this.dueAt,
    this.assignedTo,
    this.completedBy,
    this.completedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Validates and builds a new ward-task row.
  static Map<String, Object?> registerRow({
    required String tenantId,
    required String wardId,
    required String createdBy,
    required String title,
    String? patientId,
    String? encounterId,
    String? detail,
    WardTaskType taskType = WardTaskType.observation,
    WardTaskPriority priority = WardTaskPriority.routine,
    String? dueAt,
    String? assignedTo,
    String taskId = '',
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (wardId.isEmpty) {
      fieldErrors['ward_id'] = 'Ward is required.';
    }
    if (createdBy.isEmpty) {
      fieldErrors['created_by'] = 'Creator is required.';
    }
    if (title.trim().isEmpty) {
      fieldErrors['title'] = 'A task title is required.';
    }
    if (dueAt != null && DateTime.tryParse(dueAt) == null) {
      fieldErrors['due_at'] = 'Expected an ISO-8601 timestamp.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Ward task failed validation.',
        fieldErrors: fieldErrors,
        code: 'ward_task_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      if (taskId.isNotEmpty) 'id': taskId,
      'tenant_id': tenantId,
      'ward_id': wardId,
      'patient_id': patientId,
      'encounter_id': encounterId,
      'title': title.trim(),
      'detail': _trimmed(detail),
      'task_type': taskType.wireValue,
      'priority': priority.wireValue,
      'due_at': dueAt,
      'assigned_to': assignedTo,
      'status': WardTaskStatus.open.wireValue,
      'created_by': createdBy,
      'completed_by': null,
      'completed_at': null,
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Materializes a ward task from a local row.
  factory WardTask.fromRow(Map<String, Object?> row) => WardTask(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    wardId: row['ward_id']! as String,
    title: row['title']! as String,
    taskType: WardTaskType.fromWire(row['task_type']! as String),
    priority: WardTaskPriority.fromWire(row['priority']! as String),
    status: WardTaskStatus.fromWire(row['status']! as String),
    createdBy: row['created_by']! as String,
    patientId: row['patient_id'] as String?,
    encounterId: row['encounter_id'] as String?,
    detail: row['detail'] as String?,
    dueAt: row['due_at'] as String?,
    assignedTo: row['assigned_to'] as String?,
    completedBy: row['completed_by'] as String?,
    completedAt: _parse(row['completed_at']),
    createdAt: _parse(row['created_at']),
    updatedAt: _parse(row['updated_at']),
  );

  /// Database identifier.
  final String id;

  /// Tenant identifier.
  final String tenantId;

  /// The ward the work belongs to.
  final String wardId;

  /// The patient, when the task is patient-specific.
  final String? patientId;

  /// The linked encounter, when any.
  final String? encounterId;

  /// Short task title.
  final String title;

  /// Detail or instructions.
  final String? detail;

  /// The kind of work.
  final WardTaskType taskType;

  /// How soon it is needed.
  final WardTaskPriority priority;

  /// When it is due, ISO-8601, if set.
  final String? dueAt;

  /// Who owns it, if delegated.
  final String? assignedTo;

  /// Lifecycle status.
  final WardTaskStatus status;

  /// Who created it.
  final String createdBy;

  /// Who closed it, once closed.
  final String? completedBy;

  /// When it was closed.
  final DateTime? completedAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Whether the task is still open.
  bool get isOpen => status.isOpen;
}

/// The change set for (re)assigning a ward task.
Map<String, Object?> wardTaskAssignmentChanges({String? assignedTo}) =>
    <String, Object?>{
      'assigned_to': assignedTo,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

/// The change set for starting a ward task.
Map<String, Object?> wardTaskStartChanges() => <String, Object?>{
  'status': WardTaskStatus.inProgress.wireValue,
  'updated_at': DateTime.now().toUtc().toIso8601String(),
};

/// The change set for closing a ward task.
Map<String, Object?> wardTaskCloseChanges({
  required WardTaskStatus status,
  required String completedBy,
}) {
  assert(status.isTerminal, 'a task closes to done or cancelled');
  final String now = DateTime.now().toUtc().toIso8601String();
  return <String, Object?>{
    'status': status.wireValue,
    'completed_by': completedBy,
    'completed_at': now,
    'updated_at': now,
  };
}

String? _trimmed(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

DateTime? _parse(Object? value) =>
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

int? _asIntOrNull(Object? value) {
  if (value == null) {
    return null;
  }
  return _asInt(value);
}

double? _asDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.parse(value);
  }
  return null;
}

bool _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
