/// ICU critical care entities (Module 06).
///
/// ICU beds extend ward beds with ventilator linkage. Vitals, handovers, and
/// ventilator events are append-only clinical records tied to an ICU bed.
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';

/// ICU bed status.
enum IcuBedStatus {
  available('available'),
  occupied('occupied'),
  maintenance('maintenance'),
  isolation('isolation');

  const IcuBedStatus(this.wireValue);

  final String wireValue;

  String get label => switch (this) {
    IcuBedStatus.available => 'Available',
    IcuBedStatus.occupied => 'Occupied',
    IcuBedStatus.maintenance => 'Maintenance',
    IcuBedStatus.isolation => 'Isolation',
  };

  static IcuBedStatus fromWire(String value) => IcuBedStatus.values.firstWhere(
    (IcuBedStatus status) => status.wireValue == value,
    orElse: () => IcuBedStatus.available,
  );
}

/// An ICU bed linked to a ward bed and optional ventilator.
@immutable
final class IcuBed {
  const IcuBed({
    required this.id,
    required this.tenantId,
    required this.bedId,
    required this.status,
    this.ventilatorId,
    this.currentPatientId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String tenantId;
  final String bedId;
  final String? ventilatorId;
  final IcuBedStatus status;
  final String? currentPatientId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isOccupied => status == IcuBedStatus.occupied;

  factory IcuBed.fromRow(Map<String, Object?> row) {
    final Object? ventilator = row['ventilator_id'];
    final Object? patient = row['current_patient_id'];
    return IcuBed(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      bedId: row['bed_id']! as String,
      ventilatorId: ventilator is String ? ventilator : null,
      status: IcuBedStatus.fromWire(row['status']! as String),
      currentPatientId: patient is String ? patient : null,
      createdAt: row['created_at']! as DateTime,
      updatedAt: row['updated_at']! as DateTime,
    );
  }
}

/// A vitals snapshot recorded in the ICU.
@immutable
final class IcuVitals {
  const IcuVitals({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.icuBedId,
    required this.recordedBy,
    required this.recordedAt,
    this.heartRate,
    this.spo2,
    this.respiratoryRate,
    this.temperatureCelsius,
    this.systolicBp,
    this.diastolicBp,
    this.map_,
    this.cvp,
    this.etco2,
    this.gcsTotal,
    this.gcsEye,
    this.gcsVerbal,
    this.gcsMotor,
    this.fiO2,
    this.peep,
    this.tidalVolume,
    this.respiratoryMode,
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String patientId;
  final String icuBedId;
  final String recordedBy;
  final DateTime recordedAt;
  final int? heartRate;
  final int? spo2;
  final int? respiratoryRate;
  final double? temperatureCelsius;
  final int? systolicBp;
  final int? diastolicBp;
  final int? map_;
  final double? cvp;
  final int? etco2;
  final int? gcsTotal;
  final int? gcsEye;
  final int? gcsVerbal;
  final int? gcsMotor;
  final int? fiO2;
  final int? peep;
  final int? tidalVolume;
  final String? respiratoryMode;
  final DateTime createdAt;

  factory IcuVitals.fromRow(Map<String, Object?> row) {
    double? asDouble(Object? value) => value is num ? value.toDouble() : null;
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    return IcuVitals(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      icuBedId: row['icu_bed_id']! as String,
      recordedBy: row['recorded_by']! as String,
      recordedAt: row['recorded_at']! as DateTime,
      heartRate: asInt(row['heart_rate']),
      spo2: asInt(row['spo2']),
      respiratoryRate: asInt(row['respiratory_rate']),
      temperatureCelsius: asDouble(row['temperature_celsius']),
      systolicBp: asInt(row['systolic_bp']),
      diastolicBp: asInt(row['diastolic_bp']),
      map_: asInt(row['map']),
      cvp: asDouble(row['cvp']),
      etco2: asInt(row['etco2']),
      gcsTotal: asInt(row['gcs_total']),
      gcsEye: asInt(row['gcs_eye']),
      gcsVerbal: asInt(row['gcs_verbal']),
      gcsMotor: asInt(row['gcs_motor']),
      fiO2: asInt(row['fi_o2']),
      peep: asInt(row['peep']),
      tidalVolume: asInt(row['tidal_volume']),
      respiratoryMode: row['respiratory_mode'] as String?,
      createdAt: row['created_at']! as DateTime,
    );
  }
}

/// An ICU nursing handover between outgoing and incoming nurses.
@immutable
final class IcuNursingHandover {
  const IcuNursingHandover({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.icuBedId,
    required this.outgoingNurse,
    required this.incomingNurse,
    required this.handoverTime,
    required this.summary,
    this.concerns,
    this.plan,
    this.alerts,
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String patientId;
  final String icuBedId;
  final String outgoingNurse;
  final String incomingNurse;
  final DateTime handoverTime;
  final String summary;
  final String? concerns;
  final String? plan;
  final String? alerts;
  final DateTime createdAt;

  factory IcuNursingHandover.fromRow(Map<String, Object?> row) {
    final Object? concerns = row['concerns'];
    final Object? plan = row['plan'];
    final Object? alerts = row['alerts'];
    return IcuNursingHandover(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      icuBedId: row['icu_bed_id']! as String,
      outgoingNurse: row['outgoing_nurse']! as String,
      incomingNurse: row['incoming_nurse']! as String,
      handoverTime: row['handover_time']! as DateTime,
      summary: row['summary']! as String,
      concerns: concerns is String ? concerns : null,
      plan: plan is String ? plan : null,
      alerts: alerts is String ? alerts : null,
      createdAt: row['created_at']! as DateTime,
    );
  }
}

/// A ventilator event recorded against an ICU bed.
@immutable
final class VentilatorEvent {
  const VentilatorEvent({
    required this.id,
    required this.tenantId,
    required this.patientId,
    required this.icuBedId,
    required this.eventType,
    required this.recordedBy,
    required this.recordedAt,
    this.ventilatorId,
    this.mode,
    this.settings = const <String, Object?>{},
    required this.createdAt,
  });

  final String id;
  final String tenantId;
  final String patientId;
  final String icuBedId;
  final String? ventilatorId;
  final String eventType;
  final String? mode;
  final Map<String, Object?> settings;
  final String recordedBy;
  final DateTime recordedAt;
  final DateTime createdAt;

  factory VentilatorEvent.fromRow(Map<String, Object?> row) {
    final Object? ventilator = row['ventilator_id'];
    final Object? mode = row['mode'];
    final Object? settings = row['settings'];
    return VentilatorEvent(
      id: row['id']! as String,
      tenantId: row['tenant_id']! as String,
      patientId: row['patient_id']! as String,
      icuBedId: row['icu_bed_id']! as String,
      ventilatorId: ventilator is String ? ventilator : null,
      eventType: row['event_type']! as String,
      mode: mode is String ? mode : null,
      settings: settings is Map<String, Object?>
          ? settings
          : <String, Object?>{},
      recordedBy: row['recorded_by']! as String,
      recordedAt: row['recorded_at']! as DateTime,
      createdAt: row['created_at']! as DateTime,
    );
  }
}
