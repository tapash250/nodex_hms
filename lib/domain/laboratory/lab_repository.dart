/// Laboratory repository contract and local implementation (Module 17).
library;

import 'dart:convert';

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/laboratory/lab.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

/// Repository operations for the laboratory state machine.
abstract interface class LabRepository {
  /// Orders for one patient, newest first.
  Future<List<LabOrder>> listOrdersForPatient(String patientId);

  /// One order by id, or null.
  Future<LabOrder?> getOrder(String id);

  /// Specimens for an order.
  Future<List<LabSpecimen>> listSpecimens(String orderId);

  /// Results for an order, newest correction first.
  Future<List<LabResult>> listResults(String orderId);

  /// Every numeric result recorded for one patient, oldest first.
  ///
  /// A trend is a property of the patient, not of an order: the same analyte
  /// is followed across three orders taken in three months. This walks the
  /// patient's orders and collects the results, so the caller does not have to
  /// hold an order to see a curve.
  Future<List<LabResult>> listResultsForPatient(String patientId);

  /// Creates a local order.
  Future<String> createOrder(Map<String, Object?> row);

  /// Creates a pending specimen.
  Future<String> createSpecimen(Map<String, Object?> row);

  /// Applies collection transition.
  Future<void> collectSpecimen(String id, Map<String, Object?> changes);

  /// Creates an entered result.
  Future<String> enterResult(Map<String, Object?> row);

  /// Applies verification transition.
  Future<void> verifyResult(String id, Map<String, Object?> changes);

  /// Creates an explicit correction result.
  Future<String> correctResult(Map<String, Object?> row);
}

/// PowerSync-backed laboratory repository.
final class DefaultLabRepository implements LabRepository {
  /// Creates a repository over a local store.
  DefaultLabRepository({required this._store, required this._logger});

  static const String _module = 'domain.laboratory';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<LabOrder>> listOrdersForPatient(String patientId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.labOrders} WHERE patient_id = ? ORDER BY ordered_at DESC',
        <Object?>[patientId],
      );
      return rows.map(LabOrder.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'lab.orders');
    }
  }

  @override
  Future<LabOrder?> getOrder(String id) async {
    final Map<String, Object?>? row = await _store.getById(
      LocalTables.labOrders,
      id,
    );
    return row == null ? null : LabOrder.fromRow(row);
  }

  @override
  Future<List<LabSpecimen>> listSpecimens(String orderId) async {
    final List<Map<String, Object?>> rows = await _store.query(
      'SELECT * FROM ${LocalTables.labSpecimens} WHERE lab_order_id = ? ORDER BY created_at',
      <Object?>[orderId],
    );
    return rows.map(LabSpecimen.fromRow).toList(growable: false);
  }

  @override
  Future<List<LabResult>> listResults(String orderId) async {
    final List<Map<String, Object?>> rows = await _store.query(
      'SELECT * FROM ${LocalTables.labResults} WHERE lab_order_id = ? ORDER BY created_at DESC',
      <Object?>[orderId],
    );
    return rows.map(LabResult.fromRow).toList(growable: false);
  }

  @override
  Future<List<LabResult>> listResultsForPatient(String patientId) async {
    try {
      final List<LabOrder> orders = await listOrdersForPatient(patientId);
      final List<LabResult> results = <LabResult>[];
      for (final LabOrder order in orders) {
        results.addAll(await listResults(order.id));
      }
      // Oldest first: a trend reads forward in time.
      results.sort(
        (LabResult a, LabResult b) => a.enteredAt.compareTo(b.enteredAt),
      );
      return List<LabResult>.unmodifiable(results);
    } on Object catch (error, stackTrace) {
      if (error is NodexError) rethrow;
      final NodexError mapped = NodexErrorMapper.map(
        error,
        operation: 'lab.results.forPatient',
      );
      _logger.error(
        _module,
        'Laboratory repository failure.',
        operation: 'lab.results.forPatient',
        outcome: 'failed',
        errorCode: mapped.code,
        stackTrace: stackTrace,
      );
      throw mapped;
    }
  }

  @override
  Future<String> createOrder(Map<String, Object?> row) =>
      _insert(LocalTables.labOrders, row, 'lab.order');

  @override
  Future<String> createSpecimen(Map<String, Object?> row) =>
      _insert(LocalTables.labSpecimens, row, 'lab.specimen');

  @override
  Future<void> collectSpecimen(String id, Map<String, Object?> changes) =>
      _update(LocalTables.labSpecimens, id, changes, 'lab.specimen.collect');

  @override
  Future<String> enterResult(Map<String, Object?> row) =>
      _insert(LocalTables.labResults, row, 'lab.result.enter');

  @override
  Future<void> verifyResult(String id, Map<String, Object?> changes) =>
      _update(LocalTables.labResults, id, changes, 'lab.result.verify');

  @override
  Future<String> correctResult(Map<String, Object?> row) =>
      _insert(LocalTables.labResults, row, 'lab.result.correct');

  Future<String> _insert(
    String table,
    Map<String, Object?> row,
    String operation,
  ) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(table, <String, Object?>{
        ...row,
        'id': id,
        if (row['tests'] is List) 'tests': jsonEncode(row['tests']),
        if (row['field_changes'] is Map)
          'field_changes': jsonEncode(row['field_changes']),
      });
      _logger.info(
        _module,
        'Laboratory write committed locally.',
        operation: operation,
        outcome: 'queued',
      );
      return id;
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Future<void> _update(
    String table,
    String id,
    Map<String, Object?> changes,
    String operation,
  ) async {
    try {
      await _store.update(table, id, changes);
      _logger.info(
        _module,
        'Laboratory transition committed locally.',
        operation: operation,
        outcome: 'queued',
      );
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, operation);
    }
  }

  Never _mapped(Object error, StackTrace stackTrace, String operation) {
    if (error is NodexError) throw error;
    final NodexError mapped = NodexErrorMapper.map(error, operation: operation);
    _logger.error(
      _module,
      'Laboratory repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
