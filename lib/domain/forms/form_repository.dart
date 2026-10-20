/// Form repository (Module 47).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/forms/form_template.dart';
import 'package:nodex_hms/domain/forms/icd10.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

/// Repository operations for clinical forms.
abstract interface class FormRepository {
  /// The templates a clinician may fill in.
  Future<List<FormTemplate>> listTemplates();

  /// One template by id, or null.
  Future<FormTemplate?> getTemplate(String id);

  /// The ICD-10 catalogue held on the device.
  Future<List<Icd10Code>> listIcd10Codes();

  /// Records a filled form.
  Future<String> submitResponse(Map<String, Object?> row);

  /// The responses recorded for a patient.
  Future<List<FormResponse>> listResponses(String patientId);
}

/// PowerSync-backed form repository.
final class DefaultFormRepository implements FormRepository {
  /// Creates a repository over a local store.
  DefaultFormRepository({required this._store, required this._logger});

  static const String _module = 'domain.forms';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<FormTemplate>> listTemplates() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.formTemplates} WHERE status = ? '
        'ORDER BY title',
        <Object?>['published'],
      );
      return rows.map(FormTemplate.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'forms.list');
    }
  }

  @override
  Future<FormTemplate?> getTemplate(String id) async {
    final Map<String, Object?>? row = await _store.getById(
      LocalTables.formTemplates,
      id,
    );
    return row == null ? null : FormTemplate.fromRow(row);
  }

  @override
  Future<List<Icd10Code>> listIcd10Codes() async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.icd10Codes} ORDER BY code',
        const <Object?>[],
      );
      return rows.map(Icd10Code.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'forms.icd10.list');
    }
  }

  @override
  Future<String> submitResponse(Map<String, Object?> row) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(LocalTables.formResponses, <String, Object?>{
        ...row,
        'id': id,
      });
      _logger.info(
        _module,
        'Form response recorded locally.',
        operation: 'forms.submit',
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'forms.submit');
    }
  }

  @override
  Future<List<FormResponse>> listResponses(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.formResponses} WHERE patient_id = ? '
        'ORDER BY submitted_at DESC',
        <Object?>[patientId],
      );
      return rows.map(FormResponse.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'forms.responses');
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Form repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
