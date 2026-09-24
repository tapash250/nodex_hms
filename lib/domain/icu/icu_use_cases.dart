/// ICU use cases (Module 06).
///
/// Each write gates on the authorization policy before touching the
/// repository.
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/domain/icu/icu.dart';
import 'package:nodex_hms/domain/icu/icu_repository.dart';
import 'package:uuid/uuid.dart';

/// Assigns or updates an ICU bed. Requires `icu.bed.assign`.
final class AssignIcuBedUseCase {
  AssignIcuBedUseCase({required this._repository});

  final IcuRepository _repository;

  Future<IcuBed> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String bedId,
    required String? patientId,
    IcuBedStatus status = IcuBedStatus.occupied,
    String? ventilatorId,
    String? existingBedId,
  }) async {
    policy.require(NodexPermissions.icuBedAssign);
    final DateTime now = DateTime.now().toUtc();
    if (existingBedId != null) {
      final IcuBed? existing = await _repository.bedById(existingBedId);
      if (existing != null) {
        final IcuBed updated = IcuBed(
          id: existing.id,
          tenantId: existing.tenantId,
          bedId: existing.bedId,
          ventilatorId: ventilatorId ?? existing.ventilatorId,
          status: status,
          currentPatientId: patientId,
          createdAt: existing.createdAt,
          updatedAt: now,
        );
        return _repository.upsertBed(updated);
      }
    }
    final IcuBed bed = IcuBed(
      id: const Uuid().v4(),
      tenantId: tenantId,
      bedId: bedId,
      ventilatorId: ventilatorId,
      status: status,
      currentPatientId: patientId,
      createdAt: now,
      updatedAt: now,
    );
    return _repository.upsertBed(bed);
  }
}

/// Records an ICU vitals snapshot. Requires `icu.vitals.record`.
final class RecordIcuVitalsUseCase {
  RecordIcuVitalsUseCase({required this._repository});

  final IcuRepository _repository;

  Future<IcuVitals> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String icuBedId,
    required String recordedBy,
    int? heartRate,
    int? spo2,
    int? respiratoryRate,
    double? temperatureCelsius,
    int? systolicBp,
    int? diastolicBp,
    int? map_,
    double? cvp,
    int? etco2,
    int? gcsTotal,
    int? gcsEye,
    int? gcsVerbal,
    int? gcsMotor,
    int? fiO2,
    int? peep,
    int? tidalVolume,
    String? respiratoryMode,
  }) async {
    policy.require(NodexPermissions.icuVitalsRecord);
    final DateTime now = DateTime.now().toUtc();
    final IcuVitals vitals = IcuVitals(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      icuBedId: icuBedId,
      recordedBy: recordedBy,
      recordedAt: now,
      heartRate: heartRate,
      spo2: spo2,
      respiratoryRate: respiratoryRate,
      temperatureCelsius: temperatureCelsius,
      systolicBp: systolicBp,
      diastolicBp: diastolicBp,
      map_: map_,
      cvp: cvp,
      etco2: etco2,
      gcsTotal: gcsTotal,
      gcsEye: gcsEye,
      gcsVerbal: gcsVerbal,
      gcsMotor: gcsMotor,
      fiO2: fiO2,
      peep: peep,
      tidalVolume: tidalVolume,
      respiratoryMode: respiratoryMode,
      createdAt: now,
    );
    return _repository.recordVitals(vitals);
  }
}

/// Records a nursing handover. Requires `icu.handover.record`.
final class RecordIcuHandoverUseCase {
  RecordIcuHandoverUseCase({required this._repository});

  final IcuRepository _repository;

  Future<IcuNursingHandover> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String icuBedId,
    required String outgoingNurse,
    required String incomingNurse,
    required String summary,
    DateTime? handoverTime,
    String? concerns,
    String? plan,
    String? alerts,
  }) async {
    policy.require(NodexPermissions.icuHandoverRecord);
    final DateTime now = DateTime.now().toUtc();
    final IcuNursingHandover handover = IcuNursingHandover(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      icuBedId: icuBedId,
      outgoingNurse: outgoingNurse,
      incomingNurse: incomingNurse,
      handoverTime: handoverTime ?? now,
      summary: summary,
      concerns: concerns,
      plan: plan,
      alerts: alerts,
      createdAt: now,
    );
    return _repository.recordHandover(handover);
  }
}

/// Records a ventilator event. Requires `ventilator.event.record`.
final class RecordVentilatorEventUseCase {
  RecordVentilatorEventUseCase({required this._repository});

  final IcuRepository _repository;

  Future<VentilatorEvent> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String patientId,
    required String icuBedId,
    required String eventType,
    required String recordedBy,
    String? ventilatorId,
    String? mode,
    Map<String, Object?> settings = const <String, Object?>{},
  }) async {
    policy.require(NodexPermissions.ventilatorEventRecord);
    final DateTime now = DateTime.now().toUtc();
    final VentilatorEvent event = VentilatorEvent(
      id: const Uuid().v4(),
      tenantId: tenantId,
      patientId: patientId,
      icuBedId: icuBedId,
      ventilatorId: ventilatorId,
      eventType: eventType,
      mode: mode,
      settings: settings,
      recordedBy: recordedBy,
      recordedAt: now,
      createdAt: now,
    );
    return _repository.recordVentilatorEvent(event);
  }
}
