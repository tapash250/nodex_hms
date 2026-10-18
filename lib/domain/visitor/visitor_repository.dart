/// Visitor and pass repository contract and local implementation (Module 37).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:nodex_hms/domain/visitor/visitor.dart';
import 'package:uuid/uuid.dart';

abstract interface class VisitorRepository {
  /// Lists visiting windows, by ward and weekday.
  Future<List<WardVisitingWindow>> listVisitingWindows(
    String tenantId, {
    String? wardId,
    String? status,
    int limit = 500,
  });
  Future<WardVisitingWindow?> visitingWindowById(String id);
  Future<String> registerVisitingWindow(Map<String, Object?> row);
  Future<void> updateVisitingWindow(String id, Map<String, Object?> changes);

  /// Lists registrations, newest first.
  Future<List<VisitorRegistration>> listRegistrations(
    String tenantId, {
    String? status,
    String? wardId,
    int limit = 500,
  });
  Future<VisitorRegistration?> registrationById(String id);
  Future<String> registerRegistration(Map<String, Object?> row);
  Future<void> updateRegistration(String id, Map<String, Object?> changes);

  /// Lists passes, soonest to fall out of validity first.
  Future<List<VisitorPass>> listPasses(
    String tenantId, {
    String? status,
    String? registrationId,
    int limit = 500,
  });
  Future<VisitorPass?> passById(String id);
  Future<String> registerPass(Map<String, Object?> row);
  Future<void> updatePass(String id, Map<String, Object?> changes);

  /// Lists the badge print log, oldest first.
  Future<List<VisitorBadgePrint>> listBadgePrints(
    String tenantId, {
    String? passId,
    int limit = 500,
  });
  Future<String> appendBadgePrint(Map<String, Object?> row);
}

final class DefaultVisitorRepository implements VisitorRepository {
  DefaultVisitorRepository({required this._store, required this._logger});

  static const String _module = 'domain.visitor';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<WardVisitingWindow>> listVisitingWindows(
    String tenantId, {
    String? wardId,
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (wardId != null) {
        conditions.add('ward_id = ?');
        params.add(wardId);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.wardVisitingWindows} '
          'where ${conditions.join(' and ')} '
          'order by ward_id asc, day_of_week asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(WardVisitingWindow.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.listVisitingWindows');
    }
  }

  @override
  Future<WardVisitingWindow?> visitingWindowById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.wardVisitingWindows,
        id,
      );
      return row == null ? null : WardVisitingWindow.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.visitingWindowById');
    }
  }

  @override
  Future<String> registerVisitingWindow(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.wardVisitingWindows, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.registerVisitingWindow');
    }
  }

  @override
  Future<void> updateVisitingWindow(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.wardVisitingWindows, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.updateVisitingWindow');
    }
  }

  @override
  Future<List<VisitorRegistration>> listRegistrations(
    String tenantId, {
    String? status,
    String? wardId,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      if (wardId != null) {
        conditions.add('ward_id = ?');
        params.add(wardId);
      }
      final String sql =
          'select * from ${LocalTables.visitorRegistrations} '
          'where ${conditions.join(' and ')} '
          'order by registered_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(VisitorRegistration.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.listRegistrations');
    }
  }

  @override
  Future<VisitorRegistration?> registrationById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.visitorRegistrations,
        id,
      );
      return row == null ? null : VisitorRegistration.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.registrationById');
    }
  }

  @override
  Future<String> registerRegistration(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.visitorRegistrations, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.registerRegistration');
    }
  }

  @override
  Future<void> updateRegistration(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.visitorRegistrations, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.updateRegistration');
    }
  }

  @override
  Future<List<VisitorPass>> listPasses(
    String tenantId, {
    String? status,
    String? registrationId,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      if (registrationId != null) {
        conditions.add('registration_id = ?');
        params.add(registrationId);
      }
      final String sql =
          'select * from ${LocalTables.visitorPasses} '
          'where ${conditions.join(' and ')} '
          'order by valid_until asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(VisitorPass.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.listPasses');
    }
  }

  @override
  Future<VisitorPass?> passById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.visitorPasses,
        id,
      );
      return row == null ? null : VisitorPass.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.passById');
    }
  }

  @override
  Future<String> registerPass(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.visitorPasses, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.registerPass');
    }
  }

  @override
  Future<void> updatePass(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.visitorPasses, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.updatePass');
    }
  }

  @override
  Future<List<VisitorBadgePrint>> listBadgePrints(
    String tenantId, {
    String? passId,
    int limit = 500,
  }) async {
    try {
      final List<Object?> params = <Object?>[tenantId];
      final List<String> conditions = <String>['tenant_id = ?'];
      if (passId != null) {
        conditions.add('pass_id = ?');
        params.add(passId);
      }
      final String sql =
          'select * from ${LocalTables.visitorBadgePrints} '
          'where ${conditions.join(' and ')} '
          'order by print_ordinal asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(VisitorBadgePrint.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.listBadgePrints');
    }
  }

  @override
  Future<String> appendBadgePrint(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.visitorBadgePrints, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'visitor.appendBadgePrint');
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
