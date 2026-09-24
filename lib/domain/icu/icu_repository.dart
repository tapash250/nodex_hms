/// ICU repository contract and PowerSync-backed implementation (Module 06).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/icu/icu.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Read and write access to ICU beds, vitals, handovers, and ventilator
/// events.
abstract interface class IcuRepository {
  Future<IcuBed?> bedById(String id);

  Future<List<IcuBed>> allBeds();

  Future<List<IcuBed>> bedsForPatient(String patientId);

  Future<IcuBed> upsertBed(IcuBed bed);

  Future<IcuVitals?> vitalsById(String id);

  Future<List<IcuVitals>> vitalsForPatient(String patientId);

  Future<List<IcuVitals>> vitalsForBed(String icuBedId);

  Future<IcuVitals> recordVitals(IcuVitals vitals);

  Future<IcuNursingHandover?> handoverById(String id);

  Future<List<IcuNursingHandover>> handoversForPatient(String patientId);

  Future<IcuNursingHandover> recordHandover(IcuNursingHandover handover);

  Future<VentilatorEvent?> ventilatorEventById(String id);

  Future<List<VentilatorEvent>> ventilatorEventsForBed(String icuBedId);

  Future<VentilatorEvent> recordVentilatorEvent(VentilatorEvent event);
}

/// Default repository over the encrypted local projection.
final class DefaultIcuRepository implements IcuRepository {
  const DefaultIcuRepository({required this._store, required this._logger});

  static const String _module = 'domain.icu';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<IcuBed?> bedById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.icuBeds} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return IcuBed.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.bedById');
    }
  }

  @override
  Future<List<IcuBed>> allBeds() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.icuBeds} order by status, bed_id',
        const <Object?>[],
      );
      return rows.map(IcuBed.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.allBeds');
    }
  }

  @override
  Future<List<IcuBed>> bedsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.icuBeds} where current_patient_id = ?',
        <Object?>[patientId],
      );
      return rows.map(IcuBed.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.bedsForPatient');
    }
  }

  @override
  Future<IcuBed> upsertBed(IcuBed bed) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.icuBeds,
        bed.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'bed_id': bed.bedId,
        'ventilator_id': bed.ventilatorId,
        'status': bed.status.wireValue,
        'current_patient_id': bed.currentPatientId,
        'updated_at': bed.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.icuBeds, <String, Object?>{
          ...changes,
          'id': bed.id,
          'tenant_id': bed.tenantId,
          'created_at': bed.createdAt,
        });
      } else {
        await _store.update(LocalTables.icuBeds, bed.id, changes);
      }
      return bed;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.upsertBed');
    }
  }

  @override
  Future<IcuVitals?> vitalsById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.icuVitals} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return IcuVitals.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.vitalsById');
    }
  }

  @override
  Future<List<IcuVitals>> vitalsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.icuVitals} where patient_id = ? '
        'order by recorded_at desc',
        <Object?>[patientId],
      );
      return rows.map(IcuVitals.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.vitalsForPatient');
    }
  }

  @override
  Future<List<IcuVitals>> vitalsForBed(String icuBedId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.icuVitals} where icu_bed_id = ? '
        'order by recorded_at desc',
        <Object?>[icuBedId],
      );
      return rows.map(IcuVitals.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.vitalsForBed');
    }
  }

  @override
  Future<IcuVitals> recordVitals(IcuVitals vitals) async {
    try {
      await _store.insert(LocalTables.icuVitals, <String, Object?>{
        'id': vitals.id,
        'tenant_id': vitals.tenantId,
        'patient_id': vitals.patientId,
        'icu_bed_id': vitals.icuBedId,
        'recorded_by': vitals.recordedBy,
        'recorded_at': vitals.recordedAt,
        'heart_rate': vitals.heartRate,
        'spo2': vitals.spo2,
        'respiratory_rate': vitals.respiratoryRate,
        'temperature_celsius': vitals.temperatureCelsius,
        'systolic_bp': vitals.systolicBp,
        'diastolic_bp': vitals.diastolicBp,
        'map': vitals.map_,
        'cvp': vitals.cvp,
        'etco2': vitals.etco2,
        'gcs_total': vitals.gcsTotal,
        'gcs_eye': vitals.gcsEye,
        'gcs_verbal': vitals.gcsVerbal,
        'gcs_motor': vitals.gcsMotor,
        'fi_o2': vitals.fiO2,
        'peep': vitals.peep,
        'tidal_volume': vitals.tidalVolume,
        'respiratory_mode': vitals.respiratoryMode,
        'created_at': vitals.createdAt,
      });
      return vitals;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.recordVitals');
    }
  }

  @override
  Future<IcuNursingHandover?> handoverById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.icuNursingHandover} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return IcuNursingHandover.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.handoverById');
    }
  }

  @override
  Future<List<IcuNursingHandover>> handoversForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.icuNursingHandover} where patient_id = ? '
        'order by handover_time desc',
        <Object?>[patientId],
      );
      return rows.map(IcuNursingHandover.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.handoversForPatient');
    }
  }

  @override
  Future<IcuNursingHandover> recordHandover(IcuNursingHandover handover) async {
    try {
      await _store.insert(LocalTables.icuNursingHandover, <String, Object?>{
        'id': handover.id,
        'tenant_id': handover.tenantId,
        'patient_id': handover.patientId,
        'icu_bed_id': handover.icuBedId,
        'outgoing_nurse': handover.outgoingNurse,
        'incoming_nurse': handover.incomingNurse,
        'handover_time': handover.handoverTime,
        'summary': handover.summary,
        'concerns': handover.concerns,
        'plan': handover.plan,
        'alerts': handover.alerts,
        'created_at': handover.createdAt,
      });
      return handover;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.recordHandover');
    }
  }

  @override
  Future<VentilatorEvent?> ventilatorEventById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.ventilatorEvents} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return VentilatorEvent.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.ventilatorEventById');
    }
  }

  @override
  Future<List<VentilatorEvent>> ventilatorEventsForBed(String icuBedId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.ventilatorEvents} where icu_bed_id = ? '
        'order by recorded_at desc',
        <Object?>[icuBedId],
      );
      return rows.map(VentilatorEvent.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.ventilatorEventsForBed');
    }
  }

  @override
  Future<VentilatorEvent> recordVentilatorEvent(VentilatorEvent event) async {
    try {
      await _store.insert(LocalTables.ventilatorEvents, <String, Object?>{
        'id': event.id,
        'tenant_id': event.tenantId,
        'patient_id': event.patientId,
        'icu_bed_id': event.icuBedId,
        'ventilator_id': event.ventilatorId,
        'event_type': event.eventType,
        'mode': event.mode,
        'settings': event.settings,
        'recorded_by': event.recordedBy,
        'recorded_at': event.recordedAt,
        'created_at': event.createdAt,
      });
      return event;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'icu.recordVentilatorEvent');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'ICU repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
