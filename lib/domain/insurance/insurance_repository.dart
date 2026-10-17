/// Health Insurance & TPA repository contract and local implementation
/// (Module 32).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/insurance/insurance.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

abstract interface class InsuranceRepository {
  /// Lists payers by tenant, by code.
  Future<List<InsurancePayer>> listPayers(String tenantId, {int limit = 300});
  Future<InsurancePayer?> payerById(String id);
  Future<String> registerPayer(Map<String, Object?> row);
  Future<void> updatePayer(String id, Map<String, Object?> changes);

  /// Lists policies, newest validity first, optionally for one patient or
  /// payer.
  Future<List<InsurancePolicy>> listPolicies(
    String tenantId, {
    String? patientId,
    String? payerId,
    int limit = 500,
  });
  Future<InsurancePolicy?> policyById(String id);
  Future<String> registerPolicy(Map<String, Object?> row);
  Future<void> updatePolicy(String id, Map<String, Object?> changes);

  /// Lists pre-authorisation requests, newest first, optionally for one policy
  /// or patient.
  Future<List<PreAuthorisationRequest>> listPreAuthorisations(
    String tenantId, {
    String? policyId,
    String? patientId,
    int limit = 500,
  });
  Future<PreAuthorisationRequest?> preAuthorisationById(String id);
  Future<String> registerPreAuthorisation(Map<String, Object?> row);
  Future<void> updatePreAuthorisation(String id, Map<String, Object?> changes);

  /// Lists claims, newest first, optionally for one policy, patient or status.
  Future<List<InsuranceClaim>> listClaims(
    String tenantId, {
    String? policyId,
    String? patientId,
    String? status,
    int limit = 500,
  });
  Future<InsuranceClaim?> claimById(String id);
  Future<String> registerClaim(Map<String, Object?> row);
  Future<void> updateClaim(String id, Map<String, Object?> changes);
}

final class DefaultInsuranceRepository implements InsuranceRepository {
  DefaultInsuranceRepository({required this._store, required this._logger});

  static const String _module = 'domain.insurance';
  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<InsurancePayer>> listPayers(
    String tenantId, {
    int limit = 300,
  }) async {
    try {
      const String sql =
          'select * from ${LocalTables.insurancePayers} '
          'where tenant_id = ? order by code asc limit ?';
      final List<Map<String, Object?>> rows = await _store.query(sql, <Object?>[
        tenantId,
        limit,
      ]);
      return rows.map(InsurancePayer.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.listPayers');
    }
  }

  @override
  Future<InsurancePayer?> payerById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.insurancePayers,
        id,
      );
      return row == null ? null : InsurancePayer.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.payerById');
    }
  }

  @override
  Future<String> registerPayer(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.insurancePayers, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.registerPayer');
    }
  }

  @override
  Future<void> updatePayer(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.insurancePayers, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.updatePayer');
    }
  }

  @override
  Future<List<InsurancePolicy>> listPolicies(
    String tenantId, {
    String? patientId,
    String? payerId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (patientId != null) {
        conditions.add('patient_id = ?');
        params.add(patientId);
      }
      if (payerId != null) {
        conditions.add('payer_id = ?');
        params.add(payerId);
      }
      final String sql =
          'select * from ${LocalTables.insurancePolicies} '
          'where ${conditions.join(' and ')} '
          'order by valid_to desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(InsurancePolicy.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.listPolicies');
    }
  }

  @override
  Future<InsurancePolicy?> policyById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.insurancePolicies,
        id,
      );
      return row == null ? null : InsurancePolicy.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.policyById');
    }
  }

  @override
  Future<String> registerPolicy(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.insurancePolicies, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.registerPolicy');
    }
  }

  @override
  Future<void> updatePolicy(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.insurancePolicies, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.updatePolicy');
    }
  }

  @override
  Future<List<PreAuthorisationRequest>> listPreAuthorisations(
    String tenantId, {
    String? policyId,
    String? patientId,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (policyId != null) {
        conditions.add('policy_id = ?');
        params.add(policyId);
      }
      if (patientId != null) {
        conditions.add('patient_id = ?');
        params.add(patientId);
      }
      final String sql =
          'select * from ${LocalTables.preAuthorisationRequests} '
          'where ${conditions.join(' and ')} '
          'order by requested_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(PreAuthorisationRequest.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.listPreAuthorisations');
    }
  }

  @override
  Future<PreAuthorisationRequest?> preAuthorisationById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.preAuthorisationRequests,
        id,
      );
      return row == null ? null : PreAuthorisationRequest.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.preAuthorisationById');
    }
  }

  @override
  Future<String> registerPreAuthorisation(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(
        LocalTables.preAuthorisationRequests,
        <String, Object?>{...row, 'id': id},
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.registerPreAuthorisation');
    }
  }

  @override
  Future<void> updatePreAuthorisation(
    String id,
    Map<String, Object?> changes,
  ) async {
    try {
      await _store.update(LocalTables.preAuthorisationRequests, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.updatePreAuthorisation');
    }
  }

  @override
  Future<List<InsuranceClaim>> listClaims(
    String tenantId, {
    String? policyId,
    String? patientId,
    String? status,
    int limit = 500,
  }) async {
    try {
      final List<String> conditions = <String>['tenant_id = ?'];
      final List<Object?> params = <Object?>[tenantId];
      if (policyId != null) {
        conditions.add('policy_id = ?');
        params.add(policyId);
      }
      if (patientId != null) {
        conditions.add('patient_id = ?');
        params.add(patientId);
      }
      if (status != null) {
        conditions.add('status = ?');
        params.add(status);
      }
      final String sql =
          'select * from ${LocalTables.insuranceClaims} '
          'where ${conditions.join(' and ')} '
          'order by created_at desc limit ?';
      params.add(limit);
      final List<Map<String, Object?>> rows = await _store.query(sql, params);
      return rows.map(InsuranceClaim.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.listClaims');
    }
  }

  @override
  Future<InsuranceClaim?> claimById(String id) async {
    try {
      final Map<String, Object?>? row = await _store.getById(
        LocalTables.insuranceClaims,
        id,
      );
      return row == null ? null : InsuranceClaim.fromRow(row);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.claimById');
    }
  }

  @override
  Future<String> registerClaim(Map<String, Object?> row) async {
    final String id = (row['id'] as String?) ?? const Uuid().v4();
    try {
      await _store.insert(LocalTables.insuranceClaims, <String, Object?>{
        ...row,
        'id': id,
      });
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.registerClaim');
    }
  }

  @override
  Future<void> updateClaim(String id, Map<String, Object?> changes) async {
    try {
      await _store.update(LocalTables.insuranceClaims, id, changes);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'insurance.updateClaim');
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
