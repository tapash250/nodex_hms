/// Inventory management screen (Module 13).
///
/// The item register is dense and long, so it is rendered with the Module 48
/// table engine: the item code stays pinned while the facts scroll, the list
/// builds only the rows on screen, and a department can export the register it
/// is looking at as CSV or PDF.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nodex_hms/app/providers.dart';
import 'package:nodex_hms/app/tables/nodex_data_table.dart';
import 'package:nodex_hms/app/tables/table_export.dart';
import 'package:nodex_hms/core/authorization/permission_catalog.dart';
import 'package:nodex_hms/core/errors/nodex_error.dart';
import 'package:nodex_hms/domain/inventory/inventory.dart';
import 'package:nodex_hms/domain/session/session_state.dart' show SessionState;
import 'package:nodex_hms/features/inventory/inventory_controller.dart';
import 'package:nodex_hms/features/session/session_controller.dart'
    show sessionProvider;
import 'package:path_provider/path_provider.dart';

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
          PopupMenuButton<TableExportFormat>(
            icon: const Icon(Icons.ios_share_outlined),
            tooltip: 'Export the register',
            onSelected: (TableExportFormat format) => _export(
              context,
              ref,
              items.value ?? const <StockItem>[],
              format,
            ),
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<TableExportFormat>>[
                  for (final TableExportFormat format
                      in TableExportFormat.values)
                    PopupMenuItem<TableExportFormat>(
                      value: format,
                      child: Text('Export ${format.label}'),
                    ),
                ],
          ),
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
            : NodexDataTable<StockItem>(
                columns: _stockColumns,
                rows: values,
                emptyMessage: 'No stock items registered.',
                initialSort: const <TableSortSpec>[TableSortSpec('name')],
                onRowTap: (StockItem item) =>
                    context.go('/inventory/${item.id}'),
              ),
      ),
    );
  }

  /// The register's columns, in reading order.
  ///
  /// The item code is pinned: a reader who scrolls to the reorder level must
  /// not lose which item they are looking at.
  static const List<NodexTableColumn<StockItem>> _stockColumns =
      <NodexTableColumn<StockItem>>[
        NodexTableColumn<StockItem>(
          key: 'item_code',
          label: 'Code',
          width: 130,
          pinned: true,
          value: _itemCode,
        ),
        NodexTableColumn<StockItem>(
          key: 'name',
          label: 'Item',
          width: 220,
          value: _itemName,
        ),
        NodexTableColumn<StockItem>(
          key: 'category',
          label: 'Category',
          width: 160,
          value: _itemCategory,
        ),
        NodexTableColumn<StockItem>(
          key: 'unit',
          label: 'Unit',
          width: 100,
          value: _itemUnit,
        ),
        NodexTableColumn<StockItem>(
          key: 'reorder_level',
          label: 'Reorder at',
          width: 110,
          numeric: true,
          value: _itemReorderLevel,
          compare: _compareReorderLevel,
        ),
        NodexTableColumn<StockItem>(
          key: 'status',
          label: 'Status',
          width: 140,
          value: _itemStatus,
        ),
      ];

  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    List<StockItem> items,
    TableExportFormat format,
  ) async {
    final List<StockItem> ordered = NodexDataTable.sortRows<StockItem>(
      rows: items,
      columns: _stockColumns,
      sorts: const <TableSortSpec>[TableSortSpec('name')],
    );
    final String name =
        'inventory_register_${DateTime.now().toUtc().toIso8601String().split('.').first.replaceAll(':', '')}'
        '.${format.extension}';
    try {
      final Directory directory = await getApplicationDocumentsDirectory();
      final File file = File('${directory.path}/$name');
      switch (format) {
        case TableExportFormat.csv:
          await file.writeAsString(
            tableToCsv<StockItem>(columns: _stockColumns, rows: ordered),
          );
        case TableExportFormat.pdf:
          await file.writeAsBytes(
            tableToPdf<StockItem>(
              title: 'Stock register',
              columns: _stockColumns,
              rows: ordered,
            ),
          );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${ordered.length} items to $name')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $error')));
      }
    }
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

String _itemCode(StockItem item) => item.itemCode;
String _itemName(StockItem item) => item.name;
String _itemCategory(StockItem item) => item.category;
String _itemUnit(StockItem item) => item.unit;
String _itemStatus(StockItem item) => item.status.wireValue;

/// Reorder level as text, with an explicit dash when none is set.
String _itemReorderLevel(StockItem item) =>
    item.reorderLevel == null ? '—' : '${item.reorderLevel}';

/// Sorts reorder levels numerically, with "not set" first.
///
/// The rendered text would order 90 above 100; the comparison exists so the
/// column sorts like a quantity rather than like a string.
int _compareReorderLevel(StockItem a, StockItem b) {
  final double? left = a.reorderLevel;
  final double? right = b.reorderLevel;
  if (left == null && right == null) return 0;
  if (left == null) return -1;
  if (right == null) return 1;
  return left.compareTo(right);
}
