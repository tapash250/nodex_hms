/// Inventory presentation providers (Module 13).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/inventory/inventory.dart';

/// Items in the local scope.
final inventoryItemsProvider = FutureProvider.autoDispose
    .family<List<StockItem>, String?>((Ref ref, String? status) async {
      return ref.watch(inventoryRepositoryProvider).listItems(status: status);
    });

/// One item by id.
final inventoryItemProvider = FutureProvider.autoDispose
    .family<StockItem, String>((Ref ref, String itemId) async {
      final StockItem? item = await ref
          .watch(inventoryRepositoryProvider)
          .getItem(itemId);
      if (item == null) {
        throw const PersistenceError(
          message: 'This stock item is not available on this device.',
          code: 'stock_item_not_found_locally',
        );
      }
      return item;
    });

/// Batches for one item.
final itemBatchesProvider = FutureProvider.autoDispose
    .family<List<StockBatch>, String>((Ref ref, String itemId) async {
      return ref.watch(inventoryRepositoryProvider).listBatches(itemId);
    });

/// Active batches for one item.
final activeBatchesProvider = FutureProvider.autoDispose
    .family<List<StockBatch>, String>((Ref ref, String itemId) async {
      return ref.watch(inventoryRepositoryProvider).listActiveBatches(itemId);
    });

/// Movements for one item.
final itemMovementsProvider = FutureProvider.autoDispose
    .family<List<StockMovement>, String>((Ref ref, String itemId) async {
      return ref.watch(inventoryRepositoryProvider).listMovements(itemId);
    });

/// Locations in scope.
final inventoryLocationsProvider = FutureProvider.autoDispose.call((
  Ref ref,
) async {
  // For now, return empty - we'll add a location list query later
  return <String>[];
});
