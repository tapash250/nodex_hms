/// Inventory management entities (Module 13).
///
/// Stock items are master data; movements are append-only events that
/// derive current stock levels (ConflictPolicy.transactional: balances
/// replay rather than overwrite).
// ignore_for_file: sort_constructors_first
library;

import 'package:meta/meta.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';

/// Stock item status.
enum StockItemStatus {
  active('active'),
  inactive('inactive'),
  discontinued('discontinued');

  const StockItemStatus(this.wireValue);

  final String wireValue;

  /// Whether the item can still be modified. A discontinued item is retired
  /// and must not be edited.
  bool get isEditable => this != StockItemStatus.discontinued;

  static StockItemStatus fromWire(String value) =>
      StockItemStatus.values.firstWhere(
        (StockItemStatus status) => status.wireValue == value,
        orElse: () => StockItemStatus.active,
      );
}

/// Batch status.
enum BatchStatus {
  available('available'),
  reserved('reserved'),
  expired('expired'),
  recalled('recalled'),
  consumed('consumed');

  const BatchStatus(this.wireValue);

  final String wireValue;

  static BatchStatus fromWire(String value) => BatchStatus.values.firstWhere(
    (BatchStatus status) => status.wireValue == value,
    orElse: () => BatchStatus.available,
  );
}

/// Movement type.
enum MovementType {
  receipt('receipt'),
  issue('issue'),
  transfer('transfer'),
  adjustment('adjustment'),
  return_('return'),
  writeOff('write_off'),
  cycleCount('cycle_count');

  const MovementType(this.wireValue);

  final String wireValue;

  static MovementType fromWire(String value) => MovementType.values.firstWhere(
    (MovementType type) => type.wireValue == value,
    orElse: () => MovementType.adjustment,
  );
}

/// Stock item master data.
@immutable
final class StockItem {
  const StockItem({
    required this.id,
    required this.tenantId,
    required this.itemCode,
    required this.name,
    required this.category,
    required this.unit,
    required this.status,
    required this.createdAt,
    this.description,
    this.reorderLevel,
    this.standardCostMinor,
    this.requiresBatch,
    this.requiresExpiry,
  });

  static Map<String, Object?> registerRow({
    required String tenantId,
    required String itemCode,
    required String name,
    required String category,
    required String unit,
    String? description,
    double? reorderLevel,
    int? standardCostMinor,
    bool requiresBatch = false,
    bool requiresExpiry = false,
    required String createdBy,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (itemCode.trim().isEmpty) {
      fieldErrors['item_code'] = 'Item code is required.';
    }
    if (name.trim().isEmpty) {
      fieldErrors['name'] = 'Name is required.';
    }
    if (category.trim().isEmpty) {
      fieldErrors['category'] = 'Category is required.';
    }
    if (unit.trim().isEmpty) {
      fieldErrors['unit'] = 'Unit is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Stock item registration failed validation.',
        fieldErrors: fieldErrors,
        code: 'stock_item_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'item_code': itemCode.trim(),
      'name': name.trim(),
      'category': category.trim(),
      'unit': unit.trim(),
      'description': _clean(description),
      'reorder_level': reorderLevel,
      'standard_cost_minor': standardCostMinor,
      'requires_batch': requiresBatch,
      'requires_expiry': requiresExpiry,
      'status': StockItemStatus.active.wireValue,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
  }

  static Map<String, Object?> statusChanges({
    required StockItemStatus status,
  }) => <String, Object?>{
    'status': status.wireValue,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  factory StockItem.fromRow(Map<String, Object?> row) => StockItem(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    itemCode: row['item_code']! as String,
    name: row['name']! as String,
    category: row['category']! as String,
    unit: row['unit']! as String,
    status: StockItemStatus.fromWire(row['status']! as String),
    createdAt: DateTime.parse(row['created_at']! as String),
    description: row['description'] as String?,
    reorderLevel: (row['reorder_level'] as num?)?.toDouble(),
    standardCostMinor: (row['standard_cost_minor'] as num?)?.toInt(),
    requiresBatch: row['requires_batch'] as bool?,
    requiresExpiry: row['requires_expiry'] as bool?,
  );

  final String id;
  final String tenantId;
  final String itemCode;
  final String name;
  final String category;
  final String unit;
  final StockItemStatus status;
  final DateTime createdAt;
  final String? description;
  final double? reorderLevel;
  final int? standardCostMinor;
  final bool? requiresBatch;
  final bool? requiresExpiry;

  static String? _clean(String? value) {
    final String? trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

/// Storage location.
@immutable
final class StockLocation {
  const StockLocation({
    required this.id,
    required this.tenantId,
    required this.locationCode,
    required this.name,
    required this.locationType,
    required this.status,
    this.facilityId,
    this.wardId,
  });

  static Map<String, Object?> registerRow({
    required String tenantId,
    required String locationCode,
    required String name,
    required String locationType,
    String? facilityId,
    String? wardId,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (locationCode.trim().isEmpty) {
      fieldErrors['location_code'] = 'Location code is required.';
    }
    if (name.trim().isEmpty) {
      fieldErrors['name'] = 'Name is required.';
    }
    if (locationType.trim().isEmpty) {
      fieldErrors['location_type'] = 'Location type is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Stock location registration failed validation.',
        fieldErrors: fieldErrors,
        code: 'stock_location_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'facility_id': facilityId,
      'ward_id': wardId,
      'location_code': locationCode.trim(),
      'name': name.trim(),
      'location_type': locationType.trim(),
      'status': 'active',
      'created_at': now,
      'updated_at': now,
    };
  }

  factory StockLocation.fromRow(Map<String, Object?> row) => StockLocation(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    locationCode: row['location_code']! as String,
    name: row['name']! as String,
    locationType: row['location_type']! as String,
    status: row['status']! as String,
    facilityId: row['facility_id'] as String?,
    wardId: row['ward_id'] as String?,
  );

  final String id;
  final String tenantId;
  final String? facilityId;
  final String? wardId;
  final String locationCode;
  final String name;
  final String locationType;
  final String status;
}

/// Batch of a stock item.
@immutable
final class StockBatch {
  const StockBatch({
    required this.id,
    required this.tenantId,
    required this.itemId,
    required this.batchNumber,
    required this.status,
    required this.quantityMinor,
    required this.receivedAt,
    this.expiryDate,
    this.manufacturedDate,
    this.costPerUnitMinor,
  });

  static Map<String, Object?> eventRow({
    required String tenantId,
    required String itemId,
    required String batchNumber,
    required int quantityMinor,
    String? expiryDate,
    String? manufacturedDate,
    int? costPerUnitMinor,
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (itemId.isEmpty) {
      fieldErrors['item_id'] = 'Item is required.';
    }
    if (batchNumber.trim().isEmpty) {
      fieldErrors['batch_number'] = 'Batch number is required.';
    }
    if (quantityMinor < 0) {
      fieldErrors['quantity_minor'] = 'Quantity cannot be negative.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Stock batch registration failed validation.',
        fieldErrors: fieldErrors,
        code: 'stock_batch_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'item_id': itemId,
      'batch_number': batchNumber.trim(),
      'expiry_date': expiryDate,
      'manufactured_date': manufacturedDate,
      'quantity_minor': quantityMinor,
      'cost_per_unit_minor': null,
      'status': BatchStatus.available.wireValue,
      'received_at': now,
      'created_at': now,
      'updated_at': now,
    };
  }

  factory StockBatch.fromRow(Map<String, Object?> row) => StockBatch(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    itemId: row['item_id']! as String,
    batchNumber: row['batch_number']! as String,
    status: BatchStatus.fromWire(row['status']! as String),
    quantityMinor: (row['quantity_minor'] as num).toInt(),
    receivedAt: DateTime.parse(row['received_at']! as String),
    expiryDate: row['expiry_date'] == null
        ? null
        : DateTime.parse(row['expiry_date']! as String),
    manufacturedDate: row['manufactured_date'] == null
        ? null
        : DateTime.parse(row['manufactured_date']! as String),
    costPerUnitMinor: (row['cost_per_unit_minor'] as num?)?.toInt(),
  );

  final String id;
  final String tenantId;
  final String itemId;
  final String batchNumber;
  final BatchStatus status;
  final int quantityMinor;
  final DateTime receivedAt;
  final DateTime? expiryDate;
  final DateTime? manufacturedDate;
  final int? costPerUnitMinor;
}

/// Inventory movement event.
@immutable
final class StockMovement {
  const StockMovement({
    required this.id,
    required this.tenantId,
    required this.itemId,
    required this.movementType,
    required this.quantityMinor,
    required this.recordedBy,
    required this.recordedAt,
    this.batchId,
    this.fromLocationId,
    this.toLocationId,
    this.unitCostMinor,
    this.referenceType,
    this.referenceId,
    this.reason,
  });

  static Map<String, Object?> eventRow({
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
  }) {
    final Map<String, String> fieldErrors = <String, String>{};
    if (tenantId.isEmpty) {
      fieldErrors['tenant_id'] = 'Tenant is required.';
    }
    if (itemId.isEmpty) {
      fieldErrors['item_id'] = 'Item is required.';
    }
    if (quantityMinor == 0) {
      fieldErrors['quantity_minor'] = 'Quantity cannot be zero.';
    }
    if (recordedBy.isEmpty) {
      fieldErrors['recorded_by'] = 'Recording user is required.';
    }
    if (fieldErrors.isNotEmpty) {
      throw ValidationError(
        message: 'Stock movement recording failed validation.',
        fieldErrors: fieldErrors,
        code: 'stock_movement_invalid',
      );
    }

    final String now = DateTime.now().toUtc().toIso8601String();
    return <String, Object?>{
      'tenant_id': tenantId,
      'item_id': itemId,
      'batch_id': batchId,
      'from_location_id': fromLocationId,
      'to_location_id': toLocationId,
      'movement_type': movementType.wireValue,
      'quantity_minor': quantityMinor,
      'unit_cost_minor': unitCostMinor,
      'reference_type': referenceType?.trim(),
      'reference_id': referenceId,
      'reason': reason?.trim(),
      'recorded_by': recordedBy,
      'recorded_at': now,
      'created_at': now,
    };
  }

  factory StockMovement.fromRow(Map<String, Object?> row) => StockMovement(
    id: row['id']! as String,
    tenantId: row['tenant_id']! as String,
    itemId: row['item_id']! as String,
    movementType: MovementType.fromWire(row['movement_type']! as String),
    quantityMinor: (row['quantity_minor'] as num).toInt(),
    recordedBy: row['recorded_by']! as String,
    recordedAt: DateTime.parse(row['recorded_at']! as String),
    batchId: row['batch_id'] as String?,
    fromLocationId: row['from_location_id'] as String?,
    toLocationId: row['to_location_id'] as String?,
    unitCostMinor: (row['unit_cost_minor'] as num?)?.toInt(),
    referenceType: row['reference_type'] as String?,
    referenceId: row['reference_id'] as String?,
    reason: row['reason'] as String?,
  );

  final String id;
  final String tenantId;
  final String itemId;
  final MovementType movementType;
  final int quantityMinor;
  final String recordedBy;
  final DateTime recordedAt;
  final String? batchId;
  final String? fromLocationId;
  final String? toLocationId;
  final int? unitCostMinor;
  final String? referenceType;
  final String? referenceId;
  final String? reason;
}
