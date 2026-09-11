/// Master Patient Index repository contract and PowerSync implementation.
///
/// Read and write paths both target the encrypted local projection: search and
/// detail resolve offline, and writes create CRUD entries that upload through
/// the authorized mutation path. Nothing above this layer knows PowerSync
/// exists.
///
/// Testability seam: [PatientLocalStore] abstracts the SQL surface so unit
/// tests run against a deterministic fake instead of native SQLite.
library;

import 'dart:convert';

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/data/local/local_database.dart';
import 'package:nodex_hms/domain/patients/patient.dart';
import 'package:nodex_hms/domain/patients/patient_merge.dart';
import 'package:powersync_sqlcipher/sqlite3_common.dart';
import 'package:uuid/uuid.dart';

/// Minimal SQL surface the MPI repository needs from the local projection.
abstract interface class PatientLocalStore {
  /// Runs a read query, returning one map per row.
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  );

  /// Reads a single row by id, or null when absent.
  Future<Map<String, Object?>?> getById(String table, String id);

  /// Inserts a row including its `id`.
  Future<void> insert(String table, Map<String, Object?> row);

  /// Updates columns of one row by id.
  Future<void> update(String table, String id, Map<String, Object?> changes);
}

/// [PatientLocalStore] over the encrypted PowerSync database.
final class PowerSyncPatientStore implements PatientLocalStore {
  /// Creates a store over the given database.
  PowerSyncPatientStore({required this._database});
  final LocalDatabase _database;

  @override
  Future<List<Map<String, Object?>>> query(
    String sql,
    List<Object?> parameters,
  ) async {
    final List<Row> rows = await _database.database.getAll(sql, parameters);
    return rows
        .map((Row row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  @override
  Future<Map<String, Object?>?> getById(String table, String id) async {
    final List<Row> rows = await _database.database.getAll(
      'SELECT * FROM $table WHERE id = ?',
      <Object?>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(rows.first);
  }

  @override
  Future<void> insert(String table, Map<String, Object?> row) async {
    final List<String> columns = row.keys.toList(growable: false);
    final String placeholders = List<String>.filled(
      columns.length,
      '?',
    ).join(', ');
    await _database.database.execute(
      'INSERT INTO $table (${columns.join(', ')}) VALUES ($placeholders)',
      columns.map((String column) => row[column]).toList(growable: false),
    );
  }

  @override
  Future<void> update(
    String table,
    String id,
    Map<String, Object?> changes,
  ) async {
    final List<String> columns = changes.keys.toList(growable: false);
    final String assignments = columns.map((String c) => '$c = ?').join(', ');
    await _database.database.execute(
      'UPDATE $table SET $assignments WHERE id = ?',
      <Object?>[for (final String column in columns) changes[column], id],
    );
  }
}

/// Domain contract for Master Patient Index operations.
abstract interface class PatientRepository {
  /// Searches active patients in [tenantId] by MRN, name or phone.
  ///
  /// An empty [query] lists recently updated records. Matching is
  /// case-insensitive substring on names, prefix on phone, exact on MRN.
  Future<List<Patient>> searchPatients({
    required String tenantId,
    String query = '',
    int limit = 50,
  });

  /// Loads one patient by id, or null when absent from the local projection.
  Future<Patient?> getPatient(String id);

  /// True when [mrn] is already registered in [tenantId] locally.
  ///
  /// Best-effort fast fail for the registration desk: the server enforces
  /// (tenant_id, mrn) uniqueness finally, since another device may hold an
  /// unreplicated registration.
  Future<bool> mrnExists({required String tenantId, required String mrn});

  /// Persists a validated registration row, returning the new patient id.
  Future<String> insertPatient(Map<String, Object?> row);

  /// Applies validated contact changes to one patient.
  Future<void> updatePatientContact(String id, Map<String, Object?> changes);

  /// Deactivates a patient absorbed by a merge (never deleted).
  Future<void> deactivatePatient(String id);

  /// Active allergies for a patient, most severe first.
  Future<List<PatientAllergy>> getAllergies(
    String patientId, {
    bool activeOnly = true,
  });

  /// Persists a validated allergy report row, returning its id.
  Future<String> insertAllergy(Map<String, Object?> row);

  /// Retires an allergy with a reason. Clinical columns cannot be edited.
  Future<void> retireAllergy({
    required String allergyId,
    required String reason,
  });

  /// Records a master merge decision in the append-only history.
  Future<void> recordMerge({
    required String tenantId,
    required String survivingPatientId,
    required String mergedPatientId,
    required String reason,
    required Map<String, Object?> fieldChoices,
    required String mergedBy,
  });

  /// Previews a 3-way merge for conflict review.
  PatientMergeResult previewMerge({
    required Map<String, Object?> base,
    required Map<String, Object?> local,
    required Map<String, Object?> server,
  });
}

/// Default [PatientRepository] over a [PatientLocalStore].
final class DefaultPatientRepository implements PatientRepository {
  /// Creates a repository.
  DefaultPatientRepository({required this._store, required this._logger});

  static const String _module = 'domain.patients';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<Patient>> searchPatients({
    required String tenantId,
    String query = '',
    int limit = 50,
  }) async {
    final String trimmed = query.trim();
    try {
      if (trimmed.isEmpty) {
        final List<Map<String, Object?>> rows = await _store.query(
          'SELECT * FROM ${LocalTables.patients} '
          'WHERE tenant_id = ? AND is_active = 1 '
          'ORDER BY updated_at DESC LIMIT ?',
          <Object?>[tenantId, limit],
        );
        return rows.map(Patient.fromRow).toList(growable: false);
      }

      final String like = '%${trimmed.toLowerCase()}%';
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.patients} '
        'WHERE tenant_id = ? AND is_active = 1 AND ('
        'mrn = ? OR '
        'lower(first_name) LIKE ? OR lower(last_name) LIKE ? OR '
        'lower(first_name || \' \' || last_name) LIKE ? OR '
        'phone_number LIKE ?) '
        'ORDER BY last_name, first_name LIMIT ?',
        <Object?>[tenantId, trimmed, like, like, like, '$trimmed%', limit],
      );
      return rows.map(Patient.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'patient.search');
    }
  }

  @override
  Future<Patient?> getPatient(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.patients,
        id,
      );
      return row == null ? null : Patient.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'patient.get');
    }
  }

  @override
  Future<bool> mrnExists({
    required String tenantId,
    required String mrn,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT id FROM ${LocalTables.patients} '
        'WHERE tenant_id = ? AND mrn = ? LIMIT 1',
        <Object?>[tenantId, mrn.trim()],
      );
      return rows.isNotEmpty;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'patient.mrn_exists');
    }
  }

  @override
  Future<String> insertPatient(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.patients, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Patient registered locally; queued for upload.',
        operation: 'patient.register',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'patient.register');
    }
  }

  @override
  Future<void> updatePatientContact(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.patients, id, changes);
      _logger.info(
        _module,
        'Patient contact updated locally; queued for upload.',
        operation: 'patient.update_contact',
        outcome: 'queued',
      );
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'patient.update_contact');
    }
  }

  @override
  Future<void> deactivatePatient(String id) async {
    try {
      await _store.update(LocalTables.patients, id, <String, Object?>{
        'is_active': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'patient.deactivate');
    }
  }

  @override
  Future<List<PatientAllergy>> getAllergies(
    String patientId, {
    bool activeOnly = true,
  }) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.patientAllergies} '
        'WHERE patient_id = ?${activeOnly ? ' AND status = \'active\'' : ''} '
        'ORDER BY CASE severity '
        "WHEN 'severe' THEN 0 WHEN 'moderate' THEN 1 "
        "WHEN 'mild' THEN 2 ELSE 3 END, substance",
        <Object?>[patientId],
      );
      return rows.map(PatientAllergy.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'allergy.list');
    }
  }

  @override
  Future<String> insertAllergy(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.patientAllergies, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'allergy.record');
    }
  }

  @override
  Future<void> retireAllergy({
    required String allergyId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'Retiring an allergy requires a reason.',
        fieldErrors: <String, String>{
          'retired_reason': 'Enter why this allergy record is being retired.',
        },
        code: 'allergy_retire_reason_required',
      );
    }
    try {
      await _store.update(
        LocalTables.patientAllergies,
        allergyId,
        <String, Object?>{
          'status': 'retired',
          'retired_reason': reason.trim(),
          'retired_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'allergy.retire');
    }
  }

  @override
  Future<void> recordMerge({
    required String tenantId,
    required String survivingPatientId,
    required String mergedPatientId,
    required String reason,
    required Map<String, Object?> fieldChoices,
    required String mergedBy,
  }) async {
    if (reason.trim().isEmpty) {
      throw const ValidationError(
        message: 'A merge decision requires a recorded reason.',
        fieldErrors: <String, String>{
          'reason': 'Enter why these records are the same person.',
        },
        code: 'merge_reason_required',
      );
    }
    try {
      await _store.insert(LocalTables.patientMergeHistory, <String, Object?>{
        'id': const Uuid().v4(),
        'tenant_id': tenantId,
        'surviving_patient_id': survivingPatientId,
        'merged_patient_id': mergedPatientId,
        'merged_by': mergedBy,
        'reason': reason.trim(),
        'field_choices': jsonEncode(fieldChoices),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      _logger.info(
        _module,
        'Patient merge recorded; absorbed record deactivated.',
        operation: 'patient.merge',
        outcome: 'queued',
      );
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'patient.merge');
    }
  }

  @override
  PatientMergeResult previewMerge({
    required Map<String, Object?> base,
    required Map<String, Object?> local,
    required Map<String, Object?> server,
  }) => mergePatientRow(base: base, local: local, server: server);

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) {
      throw error;
    }
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Patient repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
