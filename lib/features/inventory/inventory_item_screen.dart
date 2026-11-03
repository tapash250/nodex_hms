/// Stock item detail (Module 13).
///
/// The register navigates here when a row is tapped. It shows the item's master
/// data, its batches and its movement history, all from the encrypted local
/// projection, so a ward with no signal can still answer "how much is left and
/// where did it go".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/inventory/inventory.dart';
import 'package:nodex_hms/features/inventory/inventory_controller.dart';

/// One stock item, its batches and its movements.
class InventoryItemScreen extends ConsumerWidget {
  /// Creates the detail screen for [itemId].
  const InventoryItemScreen({required this.itemId, super.key});

  /// Stock item identifier from the route.
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StockItem> item = ref.watch(inventoryItemProvider(itemId));

    return Scaffold(
      appBar: AppBar(title: Text(item.value?.name ?? 'Stock item')),
      body: item.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError ? error.message : 'Stock item unavailable.',
          ),
        ),
        data: (StockItem value) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _ItemFacts(item: value),
            const SizedBox(height: 16),
            _BatchList(itemId: itemId),
            const SizedBox(height: 16),
            _MovementList(itemId: itemId),
          ],
        ),
      ),
    );
  }
}

class _ItemFacts extends StatelessWidget {
  const _ItemFacts({required this.item});

  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(item.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${item.itemCode} · ${item.category}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _Fact(label: 'Unit', value: item.unit),
            _Fact(label: 'Status', value: item.status.wireValue),
            if (item.reorderLevel != null)
              _Fact(
                label: 'Reorder level',
                value: item.reorderLevel!.toStringAsFixed(2),
              ),
            if (item.description != null)
              _Fact(label: 'Description', value: item.description!),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 130, child: Text(label)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _BatchList extends ConsumerWidget {
  const _BatchList({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<StockBatch>> batches = ref.watch(
      itemBatchesProvider(itemId),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Batches', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            batches.when(
              loading: () => const LinearProgressIndicator(),
              error: (Object error, StackTrace _) =>
                  const Text('Batches could not be read on this device.'),
              data: (List<StockBatch> values) => values.isEmpty
                  ? const Text('No batches recorded.')
                  : Column(
                      children: <Widget>[
                        for (final StockBatch batch in values)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(batch.batchNumber),
                            subtitle: Text(batch.status.wireValue),
                            trailing: Text(
                              (batch.quantityMinor / 100).toStringAsFixed(2),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementList extends ConsumerWidget {
  const _MovementList({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<StockMovement>> movements = ref.watch(
      itemMovementsProvider(itemId),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Movements', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            movements.when(
              loading: () => const LinearProgressIndicator(),
              error: (Object error, StackTrace _) => const Text(
                'Movement history could not be read on this device.',
              ),
              data: (List<StockMovement> values) => values.isEmpty
                  ? const Text('No movements recorded.')
                  : Column(
                      children: <Widget>[
                        for (final StockMovement movement in values)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(movement.movementType.wireValue),
                            subtitle: Text(
                              movement.recordedAt.toLocal().toString(),
                            ),
                            trailing: Text(
                              (movement.quantityMinor / 100).toStringAsFixed(2),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
