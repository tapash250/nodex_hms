/// Inventory management screen (Module 13).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/inventory/inventory.dart';
import 'package:nodex_hms/domain/session/session_state.dart' show SessionState;
import 'package:nodex_hms/features/inventory/inventory_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart'
    show sessionProvider;

/// Inventory management screen.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<StockItem>> items = ref.watch(
      inventoryItemsProvider(null),
    );
    final SessionState session = ref.watch(sessionProvider);
    final bool canManage = session.authorization.can(
      NodexPermissions.inventoryMovement,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(inventoryItemsProvider(null)),
          ),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
              onPressed: () => _showItemSheet(context, ref),
            )
          : null,
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Text(
            error is NodexError ? error.message : 'Inventory unavailable.',
          ),
        ),
        data: (List<StockItem> values) => values.isEmpty
            ? const Center(child: Text('No stock items registered.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: values.length,
                itemBuilder: (BuildContext context, int index) {
                  final StockItem item = values[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        item.status == StockItemStatus.discontinued
                            ? Icons.block
                            : Icons.inventory_2_outlined,
                      ),
                      title: Text(item.name),
                      subtitle: Text(
                        '${item.itemCode} · ${item.category} · ${item.status.wireValue}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/inventory/${item.id}'),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showItemSheet(BuildContext context, WidgetRef ref) async {
    final _ItemDraft? draft = await showModalBottomSheet<_ItemDraft>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const _ItemSheet(),
    );
    if (draft == null) return;
    final SessionState session = ref.read(sessionProvider);
    final String? tenantId = session.tenantId;
    if (tenantId == null) return;
    try {
      final String id = await ref
          .read(registerStockItemUseCaseProvider)
          .call(
            policy: session.authorization,
            tenantId: tenantId,
            itemCode: draft.itemCode,
            name: draft.name,
            category: draft.category,
            unit: draft.unit,
            createdBy: session.user!.userId,
            description: draft.description,
            reorderLevel: draft.reorderLevel,
            standardCostMinor: draft.standardCostMinor,
            requiresBatch: draft.requiresBatch,
            requiresExpiry: draft.requiresExpiry,
          );
      ref.invalidate(inventoryItemsProvider(null));
      if (context.mounted) context.go('/inventory/$id');
    } on NodexError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _ItemDraft {
  const _ItemDraft({
    required this.itemCode,
    required this.name,
    required this.category,
    required this.unit,
    this.description,
    this.reorderLevel,
    this.standardCostMinor,
    this.requiresBatch = false,
    this.requiresExpiry = false,
  });
  final String itemCode;
  final String name;
  final String category;
  final String unit;
  final String? description;
  final double? reorderLevel;
  final int? standardCostMinor;
  final bool requiresBatch;
  final bool requiresExpiry;
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet();
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final TextEditingController _itemCode = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _category = TextEditingController();
  final TextEditingController _unit = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _reorderLevel = TextEditingController();
  final TextEditingController _standardCost = TextEditingController();
  bool _requiresBatch = false;
  bool _requiresExpiry = false;
  @override
  void dispose() {
    _itemCode.dispose();
    _name.dispose();
    _category.dispose();
    _unit.dispose();
    _description.dispose();
    _reorderLevel.dispose();
    _standardCost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Register stock item',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _itemCode,
            decoration: const InputDecoration(labelText: 'Item code *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name *'),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _category,
                  decoration: const InputDecoration(labelText: 'Category *'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'Unit *'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(labelText: 'Description'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _reorderLevel,
                  decoration: const InputDecoration(labelText: 'Reorder level'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _standardCost,
                  decoration: const InputDecoration(
                    labelText: 'Std cost (minor)',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Checkbox(
                value: _requiresBatch,
                onChanged: (bool? value) =>
                    setState(() => _requiresBatch = value ?? false),
              ),
              const Text('Requires batch tracking'),
              const SizedBox(width: 12),
              Checkbox(
                value: _requiresExpiry,
                onChanged: (bool? value) =>
                    setState(() => _requiresExpiry = value ?? false),
              ),
              const Text('Requires expiry'),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () {
              if (_itemCode.text.trim().isEmpty ||
                  _name.text.trim().isEmpty ||
                  _category.text.trim().isEmpty ||
                  _unit.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(
                context,
                _ItemDraft(
                  itemCode: _itemCode.text.trim(),
                  name: _name.text.trim(),
                  category: _category.text.trim(),
                  unit: _unit.text.trim(),
                  description: _description.text.trim().isEmpty
                      ? null
                      : _description.text.trim(),
                  reorderLevel: _reorderLevel.text.trim().isEmpty
                      ? null
                      : double.tryParse(_reorderLevel.text.trim()),
                  standardCostMinor: _standardCost.text.trim().isEmpty
                      ? null
                      : int.tryParse(_standardCost.text.trim()),
                  requiresBatch: _requiresBatch,
                  requiresExpiry: _requiresExpiry,
                ),
              );
            },
            child: const Text('Register item'),
          ),
        ],
      ),
    );
  }
}
