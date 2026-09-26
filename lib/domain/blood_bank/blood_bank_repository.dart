/// Blood bank repository contract and PowerSync-backed implementation
/// (Module 26).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/blood_bank/blood_bank.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Read and write access to transfusion requests, blood units, and
/// transfusions.
abstract interface class BloodBankRepository {
  Future<TransfusionRequest?> requestById(String id);

  Future<List<TransfusionRequest>> requestsForPatient(String patientId);

  Future<List<TransfusionRequest>> allRequests();

  Future<TransfusionRequest> upsertRequest(TransfusionRequest request);

  Future<BloodUnit?> bloodUnitById(String id);

  Future<List<BloodUnit>> bloodUnitsForPatient(String patientId);

  Future<List<BloodUnit>> bloodUnitsForRequest(String transfusionRequestId);

  Future<List<BloodUnit>> allBloodUnits();

  Future<BloodUnit> upsertBloodUnit(BloodUnit unit);

  Future<Transfusion?> transfusionById(String id);

  Future<List<Transfusion>> transfusionsForPatient(String patientId);

  Future<Transfusion> upsertTransfusion(Transfusion transfusion);
}

/// Default repository over the encrypted local projection.
final class DefaultBloodBankRepository implements BloodBankRepository {
  const DefaultBloodBankRepository({
    required this._store,
    required this._logger,
  });

  static const String _module = 'domain.blood_bank';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<TransfusionRequest?> requestById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.transfusionRequests} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return TransfusionRequest.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.requestById');
    }
  }

  @override
  Future<List<TransfusionRequest>> requestsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.transfusionRequests} '
        'where patient_id = ? order by requested_at desc',
        <Object?>[patientId],
      );
      return rows.map(TransfusionRequest.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.requestsForPatient');
    }
  }

  @override
  Future<List<TransfusionRequest>> allRequests() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.transfusionRequests} '
        'order by requested_at desc',
        const <Object?>[],
      );
      return rows.map(TransfusionRequest.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.allRequests');
    }
  }

  @override
  Future<TransfusionRequest> upsertRequest(TransfusionRequest request) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.transfusionRequests,
        request.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'patient_id': request.patientId,
        'encounter_id': request.encounterId,
        'requested_by': request.requestedBy,
        'requested_blood_group': request.requestedBloodGroup.wireValue,
        'component': request.component.wireValue,
        'units_requested': request.unitsRequested,
        'indication': request.indication,
        'urgency': request.urgency.wireValue,
        'status': request.status.wireValue,
        'crossmatch_result': request.crossmatchResult.wireValue,
        'requested_at': request.requestedAt,
        'approved_by': request.approvedBy,
        'approved_at': request.approvedAt,
        'updated_at': request.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.transfusionRequests, <String, Object?>{
          ...changes,
          'id': request.id,
          'tenant_id': request.tenantId,
          'created_at': request.createdAt,
        });
      } else {
        await _store.update(
          LocalTables.transfusionRequests,
          request.id,
          changes,
        );
      }
      return request;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.upsertRequest');
    }
  }

  @override
  Future<BloodUnit?> bloodUnitById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.bloodUnits} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return BloodUnit.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.bloodUnitById');
    }
  }

  @override
  Future<List<BloodUnit>> bloodUnitsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.bloodUnits} where patient_id = ? '
        'order by expires_at',
        <Object?>[patientId],
      );
      return rows.map(BloodUnit.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.bloodUnitsForPatient');
    }
  }

  @override
  Future<List<BloodUnit>> bloodUnitsForRequest(
    String transfusionRequestId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.bloodUnits} where '
        'transfusion_request_id = ? order by expires_at',
        <Object?>[transfusionRequestId],
      );
      return rows.map(BloodUnit.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.bloodUnitsForRequest');
    }
  }

  @override
  Future<List<BloodUnit>> allBloodUnits() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.bloodUnits} order by status, '
        'unit_number',
        const <Object?>[],
      );
      return rows.map(BloodUnit.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.allBloodUnits');
    }
  }

  @override
  Future<BloodUnit> upsertBloodUnit(BloodUnit unit) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.bloodUnits,
        unit.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'unit_number': unit.unitNumber,
        'blood_group': unit.bloodGroup.wireValue,
        'component': unit.component.wireValue,
        'volume_ml': unit.volumeMl,
        'collected_at': unit.collectedAt,
        'expires_at': unit.expiresAt,
        'status': unit.status.wireValue,
        'location_id': unit.locationId,
        'patient_id': unit.patientId,
        'transfusion_request_id': unit.transfusionRequestId,
        'updated_at': unit.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.bloodUnits, <String, Object?>{
          ...changes,
          'id': unit.id,
          'tenant_id': unit.tenantId,
          'created_by': unit.createdBy,
          'created_at': unit.createdAt,
        });
      } else {
        await _store.update(LocalTables.bloodUnits, unit.id, changes);
      }
      return unit;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.upsertBloodUnit');
    }
  }

  @override
  Future<Transfusion?> transfusionById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.transfusions} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return Transfusion.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.transfusionById');
    }
  }

  @override
  Future<List<Transfusion>> transfusionsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.transfusions} where patient_id = ? '
        'order by started_at desc',
        <Object?>[patientId],
      );
      return rows.map(Transfusion.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.transfusionsForPatient');
    }
  }

  @override
  Future<Transfusion> upsertTransfusion(Transfusion transfusion) async {
    try {
      final Map<String, Object?>? existing = await _store.getById(
        LocalTables.transfusions,
        transfusion.id,
      );
      final Map<String, Object?> changes = <String, Object?>{
        'transfusion_request_id': transfusion.transfusionRequestId,
        'blood_unit_id': transfusion.bloodUnitId,
        'patient_id': transfusion.patientId,
        'recorded_by': transfusion.recordedBy,
        'started_at': transfusion.startedAt,
        'finished_at': transfusion.finishedAt,
        'status': transfusion.status.wireValue,
        'volume_ml': transfusion.volumeMl,
        'reaction_notes': transfusion.reactionNotes,
        'updated_at': transfusion.updatedAt,
      };
      if (existing == null) {
        await _store.insert(LocalTables.transfusions, <String, Object?>{
          ...changes,
          'id': transfusion.id,
          'tenant_id': transfusion.tenantId,
          'created_at': transfusion.createdAt,
        });
      } else {
        await _store.update(LocalTables.transfusions, transfusion.id, changes);
      }
      return transfusion;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'blood_bank.upsertTransfusion');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Blood bank repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
