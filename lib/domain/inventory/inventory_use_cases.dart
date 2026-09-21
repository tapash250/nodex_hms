/// Inventory management use cases (Module 13).
library;

import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/inventory/inventory.dart';
import 'package:nodex_hms/domain/inventory/inventory_repository.dart';

/// Registers a stock item.
final class RegisterStockItemUseCase {
  RegisterStockItemUseCase({required this._repository});

  final InventoryRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String itemCode,
    required String name,
    required String category,
    required String unit,
    required String createdBy,
    String? description,
    double? reorderLevel,
    int? standardCostMinor,
    bool requiresBatch = false,
    bool requiresExpiry = false,
  }) async {
    policy.require(NodexPermissions.inventoryMovement);
    return _repository.registerItem(
      StockItem.registerRow(
        tenantId: tenantId,
        itemCode: itemCode,
        name: name,
        category: category,
        unit: unit,
        description: description,
        reorderLevel: reorderLevel,
        standardCostMinor: standardCostMinor,
        requiresBatch: requiresBatch,
        requiresExpiry: requiresExpiry,
        createdBy: createdBy,
      ),
    );
  }
}

/// Sets item status (e.g., maintenance, discontinued).
final class SetItemStatusUseCase {
  SetItemStatusUseCase({required this._repository});

  final InventoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required StockItem item,
    required StockItemStatus status,
  }) async {
    policy.require(NodexPermissions.inventoryMovement);
    if (!item.status.isEditable) {
      throw const AuthorizationError(
        message: 'This item cannot be modified.',
        code: 'stock_item_not_editable',
      );
    }
    await _repository.updateItem(
      item.id,
      StockItem.statusChanges(status: status),
    );
  }
}

/// Registers a storage location.
final class RegisterLocationUseCase {
  RegisterLocationUseCase({required this._repository});

  final InventoryRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String locationCode,
    required String name,
    required String locationType,
    String? facilityId,
    String? wardId,
  }) async {
    policy.require(NodexPermissions.inventoryMovement);
    return _repository.registerLocation(
      StockLocation.registerRow(
        tenantId: tenantId,
        locationCode: locationCode,
        name: name,
        locationType: locationType,
        facilityId: facilityId,
        wardId: wardId,
      ),
    );
  }
}

/// Registers a batch for an item.
final class RegisterBatchUseCase {
  RegisterBatchUseCase({required this._repository});

  final InventoryRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String itemId,
    required String batchNumber,
    required int quantityMinor,
    String? expiryDate,
    String? manufacturedDate,
    int? costPerUnitMinor,
  }) async {
    policy.require(NodexPermissions.inventoryMovement);
    return _repository.registerBatch(
      StockBatch.eventRow(
        tenantId: tenantId,
        itemId: itemId,
        batchNumber: batchNumber,
        quantityMinor: quantityMinor,
        expiryDate: expiryDate,
        manufacturedDate: manufacturedDate,
      ),
    );
  }
}

/// Updates batch status.
final class UpdateBatchStatusUseCase {
  UpdateBatchStatusUseCase({required this._repository});

  final InventoryRepository _repository;

  Future<void> call({
    required AuthorizationPolicy policy,
    required StockBatch batch,
    required BatchStatus status,
  }) async {
    policy.require(NodexPermissions.inventoryMovement);
    await _repository.updateBatch(batch.id, {'status': status.wireValue});
  }
}

/// Records a stock movement.
final class RecordMovementUseCase {
  RecordMovementUseCase({required this._repository});

  final InventoryRepository _repository;

  Future<String> call({
    required AuthorizationPolicy policy,
    required String tenantId,
    required String itemId,
    required MovementType movementType,
    required int quantityMinor,
    required String recordedBy,
    String? batchId,
    String? fromLocationId,
    String? toLocationId,
    int? unitCostMinor,
    String? referenceType,
    String? referenceId,
    String? reason,
  }) async {
    policy.require(NodexPermissions.inventoryMovement);
    return _repository.recordMovement(
      StockMovement.eventRow(
        tenantId: tenantId,
        itemId: itemId,
        movementType: movementType,
        quantityMinor: quantityMinor,
        recordedBy: recordedBy,
        batchId: batchId,
        fromLocationId: fromLocationId,
        toLocationId: toLocationId,
        unitCostMinor: unitCostMinor,
        reason: reason,
      ),
    );
  }
}
