/// Inventory repository contract and local implementation (Module 13).
library;

import 'package:nodex_hms/core/errors/error_mapper.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/core/logging/nodex_logger.dart';
import 'package:nodex_hms/core/storage/local_schema.dart';
import 'package:nodex_hms/domain/inventory/inventory.dart';
import 'package:nodex_hms/domain/patients/patient_repository.dart';
import 'package:uuid/uuid.dart';

/// Repository operations for inventory management.
abstract interface class InventoryRepository {
  /// Items for the local scope, ordered by code.
  Future<List<StockItem>> listItems({String? status});

  /// One item by id, or null.
  Future<StockItem?> getItem(String id);

  /// Batches for one item, newest first.
  Future<List<StockBatch>> listBatches(String itemId);

  /// Active batches for one item (available + reserved).
  Future<List<StockBatch>> listActiveBatches(String itemId);

  /// Movements for one item, newest first.
  Future<List<StockMovement>> listMovements(String itemId);

  /// Active batches at a specific location.
  Future<List<StockBatch>> listBatchesAtLocation(String locationId);

  /// Registers a new stock item.
  Future<String> registerItem(Map<String, Object?> row);

  /// Applies a status transition to an item.
  Future<void> updateItem(String id, Map<String, Object?> changes);

  /// Registers a storage location.
  Future<String> registerLocation(Map<String, Object?> row);

  /// Creates a batch.
  Future<String> registerBatch(Map<String, Object?> row);

  /// Applies a batch status transition.
  Future<void> updateBatch(String id, Map<String, Object?> changes);

  /// Records a stock movement.
  Future<String> recordMovement(Map<String, Object?> row);
}

/// PowerSync-backed inventory repository.
final class DefaultInventoryRepository implements InventoryRepository {
  DefaultInventoryRepository({required this._store, required this._logger});

  static const String _module = 'domain.inventory';

  final PatientLocalStore _store;
  final NodexLogger _logger;

  @override
  Future<List<StockItem>> listItems({String? status}) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        status != null
            ? 'SELECT * FROM ${LocalTables.stockItems} WHERE status = ? ORDER BY item_code'
            : 'SELECT * FROM ${LocalTables.stockItems} ORDER BY item_code',
        status != null ? <Object?>[status] : const <Object?>[],
      );
      return rows.map(StockItem.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'inv.items');
    }
  }

  @override
  Future<StockItem?> getItem(String id) async {
    final Map<String, Object?>? row = await _store.getById(
      LocalTables.stockItems,
      id,
    );
    return row == null ? null : StockItem.fromRow(row);
  }

  @override
  Future<List<StockBatch>> listBatches(String itemId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.stockBatches} WHERE item_id = ? ORDER BY received_at DESC',
        <Object?>[itemId],
      );
      return rows.map(StockBatch.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'inv.batches');
    }
  }

  @override
  Future<List<StockBatch>> listActiveBatches(String itemId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.stockBatches} WHERE item_id = ? AND status IN (?, ?) ORDER BY received_at DESC',
        <Object?>[
          itemId,
          BatchStatus.available.wireValue,
          BatchStatus.reserved.wireValue,
        ],
      );
      return rows.map(StockBatch.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'inv.active_batches');
    }
  }

  @override
  Future<List<StockMovement>> listMovements(String itemId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.stockMovements} WHERE item_id = ? ORDER BY recorded_at DESC',
        <Object?>[itemId],
      );
      return rows.map(StockMovement.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'inv.movements');
    }
  }

  @override
  Future<List<StockBatch>> listBatchesAtLocation(String locationId) async {
    try {
      final List<Map<String, Object?>> rows = await _store.query(
        'SELECT * FROM ${LocalTables.stockBatches} WHERE batch_id IN (SELECT id FROM ${LocalTables.stockBatches} WHERE item_id IN (SELECT item_id FROM ${LocalTables.stockBatches} WHERE batch_id IN (SELECT batch_id FROM ${LocalTables.stockMovements} WHERE to_location_id = ? OR from_location_id = ?)))',
        <Object?>[locationId, locationId],
      );
      return rows.map(StockBatch.fromRow).toList(growable: false);
    } on Object catch (error, stackTrace) {
      throw _mapped(error, stackTrace, 'inv.location_batches');
    }
  }

  @override
  Future<String> registerItem(Map<String, Object?> row) =>
      _insert(LocalTables.stockItems, row, 'inv.item.register');

  @override
  Future<void> updateItem(String id, Map<String, Object?> changes) =>
      _update(LocalTables.stockItems, id, changes, 'inv.item.update');

  @override
  Future<String> registerLocation(Map<String, Object?> row) =>
      _insert(LocalTables.stockLocations, row, 'inv.location.register');

  @override
  Future<String> registerBatch(Map<String, Object?> row) =>
      _insert(LocalTables.stockBatches, row, 'inv.batch.register');

  @override
  Future<void> updateBatch(String id, Map<String, Object?> changes) =>
      _update(LocalTables.stockBatches, id, changes, 'inv.batch.update');

  @override
  Future<String> recordMovement(Map<String, Object?> row) =>
      _insert(LocalTables.stockMovements, row, 'inv.movement');

  Future<String> _insert(
    String table,
    Map<String, Object?> row,
    String operation,
  ) async {
    final String id = const Uuid().v4();
    try {
      await _store.insert(table, <String, Object?>{...row, 'id': id});
      _logger.info(
        _module,
        'Inventory write committed locally.',
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
        'Inventory transition committed locally.',
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
      'Inventory repository failure.',
      operation: operation,
      outcome: 'failed',
      errorCode: mapped.code,
      stackTrace: stackTrace,
    );
    throw mapped;
  }
}
