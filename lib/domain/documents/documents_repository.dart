/// Documents & Biometric E-Consent Vault repository contract and local
/// implementation (Module 33).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/documents/documents.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class DocumentsRepository {
  /// Lists consent template versions, newest version first, optionally for one
  /// code.
  Future<List<ConsentTemplate>> listTemplates(
    String tenantId, {
    String? code,
    int limit = 300,
  });
  Future<ConsentTemplate?> templateById(String id);
  Future<String> registerTemplate(Map<String, Object?> row);
  Future<void> updateTemplate(String id, Map<String, Object?> changes);

  /// Lists consent records, newest first, optionally for one patient, template
  /// or status.
  Future<List<ConsentRecord>> listConsents(
    String tenantId, {
    String? patientId,
    String? templateId,
    String? status,
    int limit = 500,
  });
  Future<ConsentRecord?> consentById(String id);
  Future<String> registerConsent(Map<String, Object?> row);
  Future<void> updateConsent(String id, Map<String, Object?> changes);

  /// Lists vault entries, newest first, optionally for one patient, consent or
  /// kind.
  Future<List<VaultDocument>> listDocuments(
    String tenantId, {
    String? patientId,
    String? consentId,
    String? kind,
    int limit = 500,
  });
  Future<VaultDocument?> documentById(String id);
  Future<String> registerDocument(Map<String, Object?> row);
  Future<void> updateDocument(String id, Map<String, Object?> changes);
}

final class DefaultDocumentsRepository implements DocumentsRepository {
  DefaultDocumentsRepository({required this._store, required this._logger});

  static const String _module = 'domain.documents';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<ConsentTemplate>> listTemplates(
    String tenantId, {
    String? code,
    int limit = 300,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (code != null) {
        conditions.add('code = ?');
        params.add(code);
      }
      final String sql =
          'select * from ${LocalTables.consentTemplates} '
          'where ${conditions.join(' and ')} '
          'order by code asc, version desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(ConsentTemplate.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.listTemplates');
    }
  }

  @override
  Future<ConsentTemplate?> templateById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.consentTemplates,
        id,
      );
      return row == null ? null : ConsentTemplate.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.templateById');
    }
  }

  @override
  Future<String> registerTemplate(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.consentTemplates, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.registerTemplate');
    }
  }

  @override
  Future<void> updateTemplate(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.consentTemplates, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.updateTemplate');
    }
  }

  @override
  Future<List<ConsentRecord>> listConsents(
    String tenantId, {
    String? patientId,
    String? templateId,
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (patientId != null) {
        conditions.add('patient_id = ?');
        params.add(patientId);
      }
      if (templateId != null) {
        conditions.add('template_id = ?');
        params.add(templateId);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.consentRecords} '
          'where ${conditions.join(' and ')} '
          'order by created_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(ConsentRecord.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.listConsents');
    }
  }

  @override
  Future<ConsentRecord?> consentById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.consentRecords,
        id,
      );
      return row == null ? null : ConsentRecord.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.consentById');
    }
  }

  @override
  Future<String> registerConsent(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.consentRecords, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.registerConsent');
    }
  }

  @override
  Future<void> updateConsent(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.consentRecords, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.updateConsent');
    }
  }

  @override
  Future<List<VaultDocument>> listDocuments(
    String tenantId, {
    String? patientId,
    String? consentId,
    String? kind,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (patientId != null) {
        conditions.add('patient_id = ?');
        params.add(patientId);
      }
      if (consentId != null) {
        conditions.add('consent_id = ?');
        params.add(consentId);
      }
      if (kind != null) {
        conditions.add('kind = ?');
        params.add(kind);
      }
      final String sql =
          'select * from ${LocalTables.documentVaultDocuments} '
          'where ${conditions.join(' and ')} '
          'order by issued_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(VaultDocument.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.listDocuments');
    }
  }

  @override
  Future<VaultDocument?> documentById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.documentVaultDocuments,
        id,
      );
      return row == null ? null : VaultDocument.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.documentById');
    }
  }

  @override
  Future<String> registerDocument(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.documentVaultDocuments, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.registerDocument');
    }
  }

  @override
  Future<void> updateDocument(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.documentVaultDocuments, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'documents.updateDocument');
    }
  }

  NodexError _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) {
      return error;
    }
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Local store operation failed.',
      operation: operation,
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    return mapped;
  }
}
