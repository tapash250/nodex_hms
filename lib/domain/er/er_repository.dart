/// ER and triage repository contract and PowerSync-backed implementation
/// (Module 05).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/er/er.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';

/// Read and write access to triage assessments and ER visits.
abstract interface class ErRepository {
  Future<TriageAssessment?> triageById(String id);

  Future<List<TriageAssessment>> triageForPatient(String patientId);

  Future<TriageAssessment> createTriage(TriageAssessment assessment);

  Future<TriageAssessment> updateTriage(
    String id,
    Map<String, Object?> changes,
  );

  Future<ErVisit?> visitById(String id);

  Future<List<ErVisit>> visitsForPatient(String patientId);

  Future<List<ErVisit>> openVisits();

  Future<ErVisit> createVisit(ErVisit visit);

  Future<ErVisit> updateVisit(String id, Map<String, Object?> changes);
}

/// Default repository over the encrypted local projection.
final class DefaultErRepository implements ErRepository {
  const DefaultErRepository({required this._store, required this._logger});

  static const String _module = 'domain.er';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<TriageAssessment?> triageById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.triageAssessments} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return TriageAssessment.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.triageById');
    }
  }

  @override
  Future<List<TriageAssessment>> triageForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.triageAssessments} where patient_id = ? '
        'order by created_at desc',
        <Object?>[patientId],
      );
      return rows.map(TriageAssessment.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.triageForPatient');
    }
  }

  @override
  Future<TriageAssessment> createTriage(TriageAssessment assessment) async {
    try {
      await _store.insert(LocalTables.triageAssessments, <String, Object?>{
        'id': assessment.id,
        'tenant_id': assessment.tenantId,
        'patient_id': assessment.patientId,
        'encounter_id': assessment.encounterId,
        'assessed_by': assessment.assessedBy,
        'acuity': assessment.acuity.wireValue,
        'chief_complaint': assessment.chiefComplaint,
        'vitals': assessment.vitals,
        'red_flags': assessment.redFlags,
        'disposition': assessment.disposition.wireValue,
        'escalated': assessment.escalated,
        'escalated_by': assessment.escalatedBy,
        'escalated_at': assessment.escalatedAt,
        'created_at': assessment.createdAt,
        'updated_at': assessment.updatedAt,
      });
      return assessment;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.createTriage');
    }
  }

  @override
  Future<TriageAssessment> updateTriage(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.triageAssessments, id, changes);
      final TriageAssessment? updated = await triageById(id);
      if (updated == null) {
        throw StateError('Triage assessment $id disappeared after update.');
      }
      return updated;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.updateTriage');
    }
  }

  @override
  Future<ErVisit?> visitById(String id) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.erVisits} where id = ?',
        <Object?>[id],
      );
      if (rows.isEmpty) return null;
      return ErVisit.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.visitById');
    }
  }

  @override
  Future<List<ErVisit>> visitsForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.erVisits} where patient_id = ? '
        'order by started_at desc',
        <Object?>[patientId],
      );
      return rows.map(ErVisit.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.visitsForPatient');
    }
  }

  @override
  Future<List<ErVisit>> openVisits() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.erVisits} '
        "where status in ('in_progress','admitted') "
        'order by started_at asc',
        const <Object?>[],
      );
      return rows.map(ErVisit.fromRow).toList();
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.openVisits');
    }
  }

  @override
  Future<ErVisit> createVisit(ErVisit visit) async {
    try {
      await _store.insert(LocalTables.erVisits, <String, Object?>{
        'id': visit.id,
        'tenant_id': visit.tenantId,
        'patient_id': visit.patientId,
        'triage_id': visit.triageId,
        'encounter_id': visit.encounterId,
        'provider_id': visit.providerId,
        'status': visit.status.wireValue,
        'arrival_mode': visit.arrivalMode?.wireValue,
        'bed_id': visit.bedId,
        'started_at': visit.startedAt,
        'disposition': visit.disposition,
        'disposition_reason': visit.dispositionReason,
        'discharged_at': visit.dischargedAt,
        'created_at': visit.createdAt,
        'updated_at': visit.updatedAt,
      });
      return visit;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.createVisit');
    }
  }

  @override
  Future<ErVisit> updateVisit(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.erVisits, id, changes);
      final ErVisit? updated = await visitById(id);
      if (updated == null) {
        throw StateError('ER visit $id disappeared after update.');
      }
      return updated;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'er.updateVisit');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'ER repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
