/// Practitioner directory repository contract and local implementation
/// (Module 08).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/roster/practitioner.dart';
import 'package:uuid/uuid.dart';

abstract interface class PractitionerRepository {
  Future<List<PractitionerProfile>> listProfiles(
    String tenantId, {
    String? specialty,
    int limit = 200,
  });
  Future<PractitionerProfile?> profileById(String id);
  Future<PractitionerProfile?> profileForUser(String tenantId, String userId);
  Future<String> registerProfile(Map<String, Object?> row);
  Future<void> updateProfile(String id, Map<String, Object?> changes);
  Future<List<OnCallRotation>> listOnCalls(String practitionerId);
  Future<List<OnCallRotation>> upcomingOnCalls(String tenantId, DateTime at);
  Future<String> registerOnCall(Map<String, Object?> row);
  Future<void> updateOnCall(String id, Map<String, Object?> changes);
}

final class DefaultPractitionerRepository implements PractitionerRepository {
  DefaultPractitionerRepository({required this._store, required this._logger});
  static const String _module = 'domain.roster';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<PractitionerProfile>> listProfiles(
    String tenantId, {
    String? specialty,
    int limit = 200,
  }) async {
    try {
      final String sql = specialty == null
          ? 'select * from ${LocalTables.practitionerProfiles} '
                'where tenant_id = ? order by specialty, sub_specialty limit ?'
          : 'select * from ${LocalTables.practitionerProfiles} '
                'where tenant_id = ? and specialty = ? '
                'order by sub_specialty limit ?';
      final List<Object?> params = specialty == null
          ? <Object?>[tenantId, limit]
          : <Object?>[tenantId, specialty, limit];
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(PractitionerProfile.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.listProfiles');
    }
  }

  @override
  Future<PractitionerProfile?> profileById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.practitionerProfiles,
        id,
      );
      return row == null ? null : PractitionerProfile.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.profileById');
    }
  }

  @override
  Future<PractitionerProfile?> profileForUser(
    String tenantId,
    String userId,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.practitionerProfiles} '
        'where tenant_id = ? and user_id = ?',
        <Object?>[tenantId, userId],
      );
      return rows.isEmpty ? null : PractitionerProfile.fromRow(rows.first);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.profileForUser');
    }
  }

  @override
  Future<String> registerProfile(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.practitionerProfiles, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.registerProfile');
    }
  }

  @override
  Future<void> updateProfile(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.practitionerProfiles, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.updateProfile');
    }
  }

  @override
  Future<List<OnCallRotation>> listOnCalls(String practitionerId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.practitionerOnCalls} '
        'where practitioner_id = ? order by starts_at',
        <Object?>[practitionerId],
      );
      return rows.map(OnCallRotation.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.listOnCalls');
    }
  }

  @override
  Future<List<OnCallRotation>> upcomingOnCalls(
    String tenantId,
    DateTime at,
  ) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'select * from ${LocalTables.practitionerOnCalls} '
        'where tenant_id = ? and ends_at >= ? order by starts_at',
        <Object?>[tenantId, at.toUtc().toIso8601String()],
      );
      return rows.map(OnCallRotation.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.upcomingOnCalls');
    }
  }

  @override
  Future<String> registerOnCall(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.practitionerOnCalls, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.registerOnCall');
    }
  }

  @override
  Future<void> updateOnCall(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.practitionerOnCalls, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'roster.updateOnCall');
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
