/// Tests for the inventory use-case gates (Module 13).
///
/// Every inventory write rides on `inventory.movement`; this file also
/// pins the item-status guard — a discontinued item is frozen and cannot
/// be moved back into service from the client.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/core/authorization/authorization_policy.dart';
import 'package:nodex_hms/core/authorization/authorization_snapshot.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/inventory/inventory.dart';
import 'package:nodex_hms/domain/inventory/inventory_repository.dart';
import 'package:nodex_hms/domain/inventory/inventory_use_cases.dart';

/// Records what the inventory commands were asked to write.
final class RecordingInventoryRepository implements InventoryRepository {
  final List<Map<String, Object?>> itemWrites = <Map<String, Object?>>[];
  final List<Map<String, Object?>> itemUpdates = <Map<String, Object?>>[];
  final List<Map<String, Object?>> locationWrites = <Map<String, Object?>>[];
  final List<Map<String, Object?>> batchWrites = <Map<String, Object?>>[];
  final List<Map<String, Object?>> batchUpdates = <Map<String, Object?>>[];
  final List<Map<String, Object?>> movementWrites = <Map<String, Object?>>[];

  @override
  Future<List<StockItem>> listItems({String? status}) async => <StockItem>[];

  @override
  Future<StockItem?> getItem(String id) async => null;

  @override
  Future<List<StockBatch>> listBatches(String itemId) async => <StockBatch>[];

  @override
  Future<List<StockBatch>> listActiveBatches(String itemId) async =>
      <StockBatch>[];

  @override
  Future<List<StockMovement>> listMovements(String itemId) async =>
      <StockMovement>[];

  @override
  Future<List<StockBatch>> listBatchesAtLocation(String locationId) async =>
      <StockBatch>[];

  @override
  Future<String> registerItem(Map<String, Object?> row) async {
    itemWrites.add(row);
    return 'item-new';
  }

  @override
  Future<void> updateItem(String id, Map<String, Object?> changes) async {
    itemUpdates.add(<String, Object?>{'id': id, ...changes});
  }

  @override
  Future<String> registerLocation(Map<String, Object?> row) async {
    locationWrites.add(row);
    return 'location-new';
  }

  @override
  Future<String> registerBatch(Map<String, Object?> row) async {
    batchWrites.add(row);
    return 'batch-new';
  }

  @override
  Future<void> updateBatch(String id, Map<String, Object?> changes) async {
    batchUpdates.add(<String, Object?>{'id': id, ...changes});
  }

  @override
  Future<String> recordMovement(Map<String, Object?> row) async {
    movementWrites.add(row);
    return 'movement-new';
  }
}

/// Builds a policy holding exactly [permissions].
AuthorizationPolicy policyWith(Set<String> permissions) {
  final DateTime issuedAt = DateTime.now().toUtc();
  return AuthorizationPolicy(
    snapshot: AuthorizationSnapshot(
      snapshotId: 'snapshot-1',
      tenantId: 'tenant-1',
      userId: 'storekeeper-1',
      deviceId: 'device-1',
      revision: 1,
      issuedAt: issuedAt,
      expiresAt: issuedAt.add(const Duration(days: 30)),
      payloadDigest: 'digest',
      roles: const <String>{NodexRoles.nursingStaff},
      permissions: permissions,
      offlinePermissions: permissions,
      facilityIds: const <String>{},
      departmentIds: const <String>{},
      wardIds: const <String>{},
    ),
    connectivity: ConnectivityState.online,
  );
}

StockItem itemWith({StockItemStatus status = StockItemStatus.active}) =>
    StockItem(
      id: 'item-1',
      tenantId: 'tenant-1',
      itemCode: 'SKU-001',
      name: 'Paracetamol 500mg',
      category: 'analgesic',
      unit: 'tablet',
      status: status,
      createdAt: DateTime.utc(2026, 9, 1, 8),
    );

StockBatch batchWith() => StockBatch(
  id: 'batch-1',
  tenantId: 'tenant-1',
  itemId: 'item-1',
  batchNumber: 'B-001',
  quantityMinor: 100,
  status: BatchStatus.available,
  receivedAt: DateTime.utc(2026, 9, 1, 8),
);

void main() {
  late RecordingInventoryRepository repository;
  late RegisterStockItemUseCase registerItem;
  late SetItemStatusUseCase setItemStatus;
  late RegisterLocationUseCase registerLocation;
  late RegisterBatchUseCase registerBatch;
  late UpdateBatchStatusUseCase updateBatchStatus;
  late RecordMovementUseCase recordMovement;

  const Set<String> mover = <String>{NodexPermissions.inventoryMovement};
  const Set<String> reader = <String>{};

  setUp(() {
    repository = RecordingInventoryRepository();
    registerItem = RegisterStockItemUseCase(repository: repository);
    setItemStatus = SetItemStatusUseCase(repository: repository);
    registerLocation = RegisterLocationUseCase(repository: repository);
    registerBatch = RegisterBatchUseCase(repository: repository);
    updateBatchStatus = UpdateBatchStatusUseCase(repository: repository);
    recordMovement = RecordMovementUseCase(repository: repository);
  });

  group('authorization gates', () {
    test('registering an item requires inventory.movement', () {
      expect(
        registerItem.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          itemCode: 'SKU-001',
          name: 'Paracetamol 500mg',
          category: 'analgesic',
          unit: 'tablet',
          createdBy: 'storekeeper-1',
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.requiredPermission,
            'requiredPermission',
            NodexPermissions.inventoryMovement,
          ),
        ),
      );
    });

    test('setting item status requires inventory.movement', () {
      expect(
        setItemStatus.call(
          policy: policyWith(reader),
          item: itemWith(),
          status: StockItemStatus.inactive,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('registering a location requires inventory.movement', () {
      expect(
        registerLocation.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          locationCode: 'LOC-001',
          name: 'Main Store',
          locationType: 'store',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('registering a batch requires inventory.movement', () {
      expect(
        registerBatch.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          itemId: 'item-1',
          batchNumber: 'B-001',
          quantityMinor: 100,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('updating a batch status requires inventory.movement', () {
      expect(
        updateBatchStatus.call(
          policy: policyWith(reader),
          batch: batchWith(),
          status: BatchStatus.recalled,
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });

    test('recording a movement requires inventory.movement', () {
      expect(
        recordMovement.call(
          policy: policyWith(reader),
          tenantId: 'tenant-1',
          itemId: 'item-1',
          movementType: MovementType.receipt,
          quantityMinor: 100,
          recordedBy: 'storekeeper-1',
        ),
        throwsA(isA<AuthorizationError>()),
      );
    });
  });

  group('stock items', () {
    test(
      'a registered item starts active and carries its master data',
      () async {
        final String id = await registerItem.call(
          policy: policyWith(mover),
          tenantId: 'tenant-1',
          itemCode: ' SKU-001 ',
          name: 'Paracetamol 500mg',
          category: 'analgesic',
          unit: 'tablet',
          createdBy: 'storekeeper-1',
          requiresBatch: true,
        );

        expect(id, 'item-new');
        expect(repository.itemWrites, hasLength(1));
        final Map<String, Object?> row = repository.itemWrites.single;
        expect(row['status'], 'active');
        expect(row['item_code'], 'SKU-001');
        expect(row['name'], 'Paracetamol 500mg');
        expect(row['requires_batch'], isTrue);
        expect(row['created_by'], 'storekeeper-1');
      },
    );

    test('item status can be changed while editable', () async {
      await setItemStatus.call(
        policy: policyWith(mover),
        item: itemWith(),
        status: StockItemStatus.inactive,
      );

      expect(repository.itemUpdates, hasLength(1));
      expect(repository.itemUpdates.single['id'], 'item-1');
      expect(repository.itemUpdates.single['status'], 'inactive');
    });

    test('a discontinued item is frozen', () {
      expect(
        setItemStatus.call(
          policy: policyWith(mover),
          item: itemWith(status: StockItemStatus.discontinued),
          status: StockItemStatus.active,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.code,
            'code',
            'stock_item_not_editable',
          ),
        ),
      );
      expect(repository.itemUpdates, isEmpty);
    });

    test('the permission gate runs before the freeze check', () {
      // An unauthorized caller on a discontinued item must fail as an
      // authorization error, never as a state error.
      expect(
        setItemStatus.call(
          policy: policyWith(reader),
          item: itemWith(status: StockItemStatus.discontinued),
          status: StockItemStatus.active,
        ),
        throwsA(
          isA<AuthorizationError>().having(
            (AuthorizationError error) => error.requiredPermission,
            'requiredPermission',
            NodexPermissions.inventoryMovement,
          ),
        ),
      );
    });
  });

  group('locations, batches and movements', () {
    test('a location is registered with its code and type', () async {
      await registerLocation.call(
        policy: policyWith(mover),
        tenantId: 'tenant-1',
        locationCode: 'LOC-001',
        name: 'Main Store',
        locationType: 'store',
        wardId: 'ward-1',
      );

      expect(repository.locationWrites, hasLength(1));
      final Map<String, Object?> row = repository.locationWrites.single;
      expect(row['location_code'], 'LOC-001');
      expect(row['location_type'], 'store');
      expect(row['ward_id'], 'ward-1');
    });

    test('a batch is registered against its item', () async {
      await registerBatch.call(
        policy: policyWith(mover),
        tenantId: 'tenant-1',
        itemId: 'item-1',
        batchNumber: 'B-001',
        quantityMinor: 100,
        expiryDate: '2027-01-01',
      );

      expect(repository.batchWrites, hasLength(1));
      final Map<String, Object?> row = repository.batchWrites.single;
      expect(row['item_id'], 'item-1');
      expect(row['batch_number'], 'B-001');
      expect(row['quantity_minor'], 100);
    });

    test('a batch status change records the transition', () async {
      await updateBatchStatus.call(
        policy: policyWith(mover),
        batch: batchWith(),
        status: BatchStatus.recalled,
      );

      expect(repository.batchUpdates, hasLength(1));
      expect(repository.batchUpdates.single['id'], 'batch-1');
      expect(repository.batchUpdates.single['status'], 'recalled');
    });

    test('a movement records its type, quantity and reference', () async {
      await recordMovement.call(
        policy: policyWith(mover),
        tenantId: 'tenant-1',
        itemId: 'item-1',
        movementType: MovementType.issue,
        quantityMinor: 20,
        recordedBy: 'storekeeper-1',
        referenceType: 'encounter',
        referenceId: 'enc-1',
        reason: 'Ward order',
      );

      expect(repository.movementWrites, hasLength(1));
      final Map<String, Object?> row = repository.movementWrites.single;
      expect(row['item_id'], 'item-1');
      expect(row['movement_type'], 'issue');
      expect(row['quantity_minor'], 20);
      expect(row['recorded_by'], 'storekeeper-1');
      expect(row['reason'], 'Ward order');
    });
  });
}
