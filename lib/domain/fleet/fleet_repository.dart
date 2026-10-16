/// Fleet & ambulance dispatch repository contract and local implementation
/// (Module 27).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/fleet/fleet.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class FleetRepository {
  /// Lists vehicles by tenant. Archived vehicles are filtered by the caller.
  Future<List<Ambulance>> listAmbulances(
    String tenantId, {
    String? facilityId,
    int limit = 300,
  });
  Future<Ambulance?> ambulanceById(String id);
  Future<String> registerAmbulance(Map<String, Object?> row);
  Future<void> updateAmbulance(String id, Map<String, Object?> changes);

  /// Lists duty assignments by tenant, optionally for one vehicle.
  Future<List<AmbulanceDuty>> listDuties(
    String tenantId, {
    String? ambulanceId,
    int limit = 500,
  });
  Future<String> registerDuty(Map<String, Object?> row);
  Future<void> updateDuty(String id, Map<String, Object?> changes);

  /// Lists dispatch jobs by tenant, optionally by facility, vehicle or patient.
  Future<List<AmbulanceDispatch>> listDispatches(
    String tenantId, {
    String? facilityId,
    String? ambulanceId,
    String? patientId,
    int limit = 500,
  });
  Future<AmbulanceDispatch?> dispatchById(String id);
  Future<String> createDispatch(Map<String, Object?> row);
  Future<void> updateDispatch(String id, Map<String, Object?> changes);

  /// Lists last-known-position pings, newest first.
  Future<List<TrackingPing>> listPings(
    String tenantId, {
    String? ambulanceId,
    String? dispatchId,
    int limit = 200,
  });
  Future<String> registerPing(Map<String, Object?> row);
}

final class DefaultFleetRepository implements FleetRepository {
  DefaultFleetRepository({required this._store, required this._logger});

  static const String _module = 'domain.fleet';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<Ambulance>> listAmbulances(
    String tenantId, {
    String? facilityId,
    int limit = 300,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (facilityId != null) {
        conditions.add('facility_id = ?');
        params.add(facilityId);
      }
      final String sql =
          'select * from ${LocalTables.ambulances} '
          'where ${conditions.join(' and ')} '
          'order by call_sign asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(Ambulance.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.listAmbulances');
    }
  }

  @override
  Future<Ambulance?> ambulanceById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.ambulances,
        id,
      );
      return row == null ? null : Ambulance.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.ambulanceById');
    }
  }

  @override
  Future<String> registerAmbulance(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.ambulances, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.registerAmbulance');
    }
  }

  @override
  Future<void> updateAmbulance(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.ambulances, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.updateAmbulance');
    }
  }

  @override
  Future<List<AmbulanceDuty>> listDuties(
    String tenantId, {
    String? ambulanceId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (ambulanceId != null) {
        conditions.add('ambulance_id = ?');
        params.add(ambulanceId);
      }
      final String sql =
          'select * from ${LocalTables.ambulanceDutyAssignments} '
          'where ${conditions.join(' and ')} '
          'order by starts_at asc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(AmbulanceDuty.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.listDuties');
    }
  }

  @override
  Future<String> registerDuty(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(
        LocalTables.ambulanceDutyAssignments,
        <String, Object?>{...row, 'id': id},
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.registerDuty');
    }
  }

  @override
  Future<void> updateDuty(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.ambulanceDutyAssignments, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.updateDuty');
    }
  }

  @override
  Future<List<AmbulanceDispatch>> listDispatches(
    String tenantId, {
    String? facilityId,
    String? ambulanceId,
    String? patientId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (facilityId != null) {
        conditions.add('facility_id = ?');
        params.add(facilityId);
      }
      if (ambulanceId != null) {
        conditions.add('ambulance_id = ?');
        params.add(ambulanceId);
      }
      if (patientId != null) {
        conditions.add('patient_id = ?');
        params.add(patientId);
      }
      final String sql =
          'select * from ${LocalTables.ambulanceDispatches} '
          'where ${conditions.join(' and ')} '
          'order by requested_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(AmbulanceDispatch.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.listDispatches');
    }
  }

  @override
  Future<AmbulanceDispatch?> dispatchById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.ambulanceDispatches,
        id,
      );
      return row == null ? null : AmbulanceDispatch.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.dispatchById');
    }
  }

  @override
  Future<String> createDispatch(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.ambulanceDispatches, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.createDispatch');
    }
  }

  @override
  Future<void> updateDispatch(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.ambulanceDispatches, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.updateDispatch');
    }
  }

  @override
  Future<List<TrackingPing>> listPings(
    String tenantId, {
    String? ambulanceId,
    String? dispatchId,
    int limit = 200,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (ambulanceId != null) {
        conditions.add('ambulance_id = ?');
        params.add(ambulanceId);
      }
      if (dispatchId != null) {
        conditions.add('dispatch_id = ?');
        params.add(dispatchId);
      }
      final String sql =
          'select * from ${LocalTables.ambulanceTrackingPings} '
          'where ${conditions.join(' and ')} '
          'order by recorded_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(TrackingPing.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.listPings');
    }
  }

  @override
  Future<String> registerPing(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.ambulanceTrackingPings, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'fleet.registerPing');
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
