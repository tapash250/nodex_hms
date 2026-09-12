/// Clinical encounter repository contract and local implementation (Module 16).
///
/// Reads and writes target the encrypted local projection. Encounters are
/// tenant-scoped and patient-scoped; the local store seam keeps the repository
/// unit-testable without native SQLite.
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/encounters/encounter.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

/// Domain contract for encounter operations.
abstract interface class EncounterRepository {
  /// Encounters for [patientId], newest first.
  Future<List<ClinicalEncounter>> listForPatient(
    String patientId, {
    int limit = 50,
  });

  /// One encounter by id, or null when absent from the local projection.
  Future<ClinicalEncounter?> getEncounter(String id);

  /// Active encounters for [attendingPhysicianId] in [tenantId].
  Future<List<ClinicalEncounter>> listForPhysician({
    required String tenantId,
    required String attendingPhysicianId,
    int limit = 50,
  });

  /// Persists a validated draft row, returning the new encounter id.
  Future<String> createEncounter(Map<String, Object?> row);

  /// Applies validated content changes to an unsigned encounter.
  Future<void> updateEncounter(String id, Map<String, Object?> changes);

  /// Signs and freezes an encounter.
  Future<void> signEncounter(String id);

  /// Amendments recorded against [encounterId], newest first.
  Future<List<EncounterAmendment>> listAmendments(String encounterId);

  /// Records an amendment and moves the encounter to `amended`.
  Future<String> amendEncounter({
    required String encounterId,
    required Map<String, Object?> amendmentRow,
  });
}

/// Default [EncounterRepository] over a [PatientLocalStore].
///
/// Reuses the patient store seam: both are thin SQL surfaces over the same
/// encrypted projection, and duplicating the interface would add no safety.
final class DefaultEncounterRepository implements EncounterRepository {
  /// Creates a repository.
  DefaultEncounterRepository({required this._store, required this._logger});

  static const String _module = 'domain.encounters';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<ClinicalEncounter>> listForPatient(
    String patientId, {
    int limit = 50,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.clinicalEncounters} '
        'WHERE patient_id = ? ORDER BY created_at DESC LIMIT ?',
        <Object?>[patientId, limit],
      );
      return rows.map(ClinicalEncounter.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'encounter.list_for_patient');
    }
  }

  @override
  Future<ClinicalEncounter?> getEncounter(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.clinicalEncounters,
        id,
      );
      return row == null ? null : ClinicalEncounter.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'encounter.get');
    }
  }

  @override
  Future<List<ClinicalEncounter>> listForPhysician({
    required String tenantId,
    required String attendingPhysicianId,
    int limit = 50,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.clinicalEncounters} '
        'WHERE tenant_id = ? AND attending_physician_id = ? '
        "AND status IN ('in_progress', 'planned') "
        'ORDER BY updated_at DESC LIMIT ?',
        <Object?>[tenantId, attendingPhysicianId, limit],
      );
      return rows.map(ClinicalEncounter.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'encounter.list_for_physician');
    }
  }

  @override
  Future<String> createEncounter(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.clinicalEncounters, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Encounter created locally; queued for upload.',
        operation: 'encounter.create',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'encounter.create');
    }
  }

  @override
  Future<void> updateEncounter(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.clinicalEncounters, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'encounter.update');
    }
  }

  @override
  Future<void> signEncounter(String id) =>
      updateEncounter(id, ClinicalEncounter.signChanges());

  @override
  Future<List<EncounterAmendment>> listAmendments(String encounterId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.encounterAmendments} '
        'WHERE encounter_id = ? ORDER BY created_at DESC',
        <Object?>[encounterId],
      );
      return rows.map(EncounterAmendment.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'encounter.list_amendments');
    }
  }

  @override
  Future<String> amendEncounter({
    required String encounterId,
    required Map<String, Object?> amendmentRow,
  }) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.encounterAmendments, <String, Object?>{
        ...amendmentRow,
        'id': id,
      });
      // The amendment and the status move are separate writes on purpose:
      // the amendment row is the evidence, and the status change is derived
      // from its existence. A crash between them leaves the encounter signed
      // with an amendment on record, which is recoverable and honest.
      await _store.update(
        LocalTables.clinicalEncounters,
        encounterId,
        <String, Object?>{
          'status': EncounterStatus.amended.wireValue,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      _logger.info(
        _module,
        'Amendment recorded; encounter marked amended.',
        operation: 'encounter.amend',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'encounter.amend');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) {
      throw error;
    }
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Encounter repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
