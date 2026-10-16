/// Hospital contacts directory repository contract and local implementation
/// (Module 42).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/contacts/contact.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class ContactRepository {
  Future<List<DirectoryContact>> listContacts(
    String tenantId, {
    ContactCategory? category,
    String? facilityId,
    bool includeArchived = false,
    int limit = 300,
  });
  Future<DirectoryContact?> contactById(String id);
  Future<String> registerContact(Map<String, Object?> row);
  Future<void> updateContact(String id, Map<String, Object?> changes);
}

final class DefaultContactRepository implements ContactRepository {
  DefaultContactRepository({required this._store, required this._logger});

  static const String _module = 'domain.contacts';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<DirectoryContact>> listContacts(
    String tenantId, {
    ContactCategory? category,
    String? facilityId,
    bool includeArchived = false,
    int limit = 300,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (category != null) {
        conditions.add('category = ?');
        params.add(category.wireValue);
      }
      if (facilityId != null) {
        conditions.add('facility_id = ?');
        params.add(facilityId);
      }
      if (!includeArchived) {
        conditions.add('status = ?');
        params.add(ContactStatus.active.wireValue);
      }
      final String sql =
          'select * from ${LocalTables.directoryContacts} '
          'where ${conditions.join(' and ')} '
          'order by is_emergency desc, display_order asc, lower(name) asc '
          'limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(DirectoryContact.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'contacts.listContacts');
    }
  }

  @override
  Future<DirectoryContact?> contactById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.directoryContacts,
        id,
      );
      return row == null ? null : DirectoryContact.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'contacts.contactById');
    }
  }

  @override
  Future<String> registerContact(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.directoryContacts, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'contacts.registerContact');
    }
  }

  @override
  Future<void> updateContact(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.directoryContacts, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'contacts.updateContact');
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
