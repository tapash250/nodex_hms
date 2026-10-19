/// Tests for the master data table engine (Module 48).
///
/// The engine's promises are narrow and testable: a sort applies in the order
/// the reader set it, the pinned column does not scroll away, only the rows near
/// the viewport are built, and the two vertical lists stay in step.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/tables/nodex_data_table.dart';

/// A row of the test register.
final class _Row {
  const _Row(this.code, this.name, this.quantity, this.ward);

  final String code;
  final String name;
  final int quantity;
  final String ward;
}

const List<NodexTableColumn<_Row>> _columns = <NodexTableColumn<_Row>>[
  NodexTableColumn<_Row>(
    key: 'code',
    label: 'Code',
    width: 100,
    pinned: true,
    value: _code,
  ),
  NodexTableColumn<_Row>(key: 'name', label: 'Name', width: 160, value: _name),
  NodexTableColumn<_Row>(
    key: 'quantity',
    label: 'Qty',
    width: 80,
    numeric: true,
    value: _quantity,
    compare: _compareQuantity,
  ),
  NodexTableColumn<_Row>(key: 'ward', label: 'Ward', width: 120, value: _ward),
];

String _code(_Row row) => row.code;
String _name(_Row row) => row.name;
String _quantity(_Row row) => '${row.quantity}';
String _ward(_Row row) => row.ward;

int _compareQuantity(_Row a, _Row b) => a.quantity.compareTo(b.quantity);

List<_Row> _rows(int count) => <_Row>[
  for (int i = 0; i < count; i++)
    _Row(
      'C${i.toString().padLeft(3, '0')}',
      'Item $i',
      1000 - i,
      'Ward ${i % 4}',
    ),
];

/// A table sized so a phone-sized viewport can be assumed in tests.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 400, height: 300, child: child)),
);

List<String> _visibleText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text text) => text.data ?? '')
    .where((String value) => value.isNotEmpty)
    .toList(growable: false);

/// The index of the topmost built row, read from the pinned codes or from the
/// scrolling item names.
///
/// This is how the vertical pairing is asserted: whatever the pinned column
/// shows at the top, the body must show the same record.
int _topIndex(WidgetTester tester, RegExp pattern) {
  final List<int> indices = <int>[
    for (final Text text in tester.widgetList<Text>(find.byType(Text)))
      if (text.data != null && pattern.hasMatch(text.data!))
        int.parse(RegExp(r'\d+').firstMatch(text.data!)!.group(0)!),
  ]..sort();
  expect(indices, isNotEmpty, reason: 'no rows matching $pattern were built');
  return indices.first;
}

void main() {
  group('sorting', () {
    test('sorts by one column', () {
      final List<_Row> sorted = NodexDataTable.sortRows<_Row>(
        rows: _rows(4),
        columns: _columns,
        sorts: const <TableSortSpec>[TableSortSpec('name')],
      );
      expect(sorted.map((_Row r) => r.name), <String>[
        'Item 0',
        'Item 1',
        'Item 2',
        'Item 3',
      ]);
    });

    test('honours a declared comparison rather than the rendered text', () {
      final List<_Row> sorted = NodexDataTable.sortRows<_Row>(
        rows: const <_Row>[
          _Row('A', 'Item 9', 9, 'Ward 1'),
          _Row('B', 'Item 10', 100, 'Ward 1'),
          _Row('C', 'Item 1', 5, 'Ward 1'),
        ],
        columns: _columns,
        sorts: const <TableSortSpec>[TableSortSpec('quantity')],
      );
      expect(sorted.map((_Row r) => r.quantity), <int>[5, 9, 100]);
    });

    test('applies sorts in the order they were declared', () {
      final List<_Row> sorted = NodexDataTable.sortRows<_Row>(
        rows: const <_Row>[
          _Row('A', 'Beta', 1, 'Ward 1'),
          _Row('B', 'Alpha', 2, 'Ward 2'),
          _Row('C', 'Beta', 3, 'Ward 2'),
          _Row('D', 'Alpha', 4, 'Ward 1'),
        ],
        columns: _columns,
        sorts: const <TableSortSpec>[
          TableSortSpec('ward'),
          TableSortSpec('name'),
        ],
      );
      expect(sorted.map((_Row r) => '${r.ward}/${r.name}'), <String>[
        'Ward 1/Alpha',
        'Ward 1/Beta',
        'Ward 2/Alpha',
        'Ward 2/Beta',
      ]);
    });

    test('a descending level reverses that level only', () {
      final List<_Row> sorted = NodexDataTable.sortRows<_Row>(
        rows: const <_Row>[
          _Row('A', 'Beta', 1, 'Ward 1'),
          _Row('B', 'Alpha', 2, 'Ward 2'),
          _Row('C', 'Beta', 3, 'Ward 2'),
          _Row('D', 'Alpha', 4, 'Ward 1'),
        ],
        columns: _columns,
        sorts: const <TableSortSpec>[
          TableSortSpec('ward'),
          TableSortSpec('name', TableSortDirection.descending),
        ],
      );
      expect(sorted.map((_Row r) => '${r.ward}/${r.name}'), <String>[
        'Ward 1/Beta',
        'Ward 1/Alpha',
        'Ward 2/Beta',
        'Ward 2/Alpha',
      ]);
    });

    test('no sort leaves the caller order untouched', () {
      final List<_Row> rows = _rows(3);
      final List<_Row> sorted = NodexDataTable.sortRows<_Row>(
        rows: rows,
        columns: _columns,
        sorts: const <TableSortSpec>[],
      );
      expect(sorted, rows);
    });

    test('an unknown column key is ignored rather than fatal', () {
      final List<_Row> sorted = NodexDataTable.sortRows<_Row>(
        rows: _rows(3),
        columns: _columns,
        sorts: const <TableSortSpec>[TableSortSpec('does_not_exist')],
      );
      expect(sorted, hasLength(3));
    });
  });

  group('rendering', () {
    testWidgets('shows the empty message when there is nothing to show', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const NodexDataTable<_Row>(
            columns: _columns,
            rows: <_Row>[],
            emptyMessage: 'No stock items registered.',
          ),
        ),
      );
      expect(find.text('No stock items registered.'), findsOneWidget);
    });

    testWidgets('builds only the rows near the viewport', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(NodexDataTable<_Row>(columns: _columns, rows: _rows(500))),
      );
      final List<String> visible = _visibleText(tester);
      // 300px of body at 44px a row is a handful of rows, not five hundred.
      expect(
        visible.where((String v) => v.startsWith('Item ')).length,
        lessThan(20),
      );
      expect(visible, contains('C000'));
    });

    testWidgets('keeps the pinned column on screen while the body scrolls', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(NodexDataTable<_Row>(columns: _columns, rows: _rows(20))),
      );
      // The body is the horizontal scroll view under the header; the pinned
      // code column is rendered outside it.
      final Finder body = find.byType(SingleChildScrollView).last;
      expect(
        find.descendant(of: body, matching: find.text('C000')),
        findsNothing,
      );
      expect(
        find.descendant(of: body, matching: find.text('Item 0')),
        findsOneWidget,
      );
    });

    testWidgets(
      'scrolls the body horizontally without moving the pinned code',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          _host(NodexDataTable<_Row>(columns: _columns, rows: _rows(5))),
        );
        final Finder body = find.byType(SingleChildScrollView).last;
        final Offset before = tester.getTopLeft(find.text('C000').first);
        await tester.drag(body, const Offset(-200, 0));
        await tester.pumpAndSettle();
        final Offset after = tester.getTopLeft(find.text('C000').first);
        expect(after, before);
      },
    );

    testWidgets('keeps the pinned and scrolling columns in vertical step', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(NodexDataTable<_Row>(columns: _columns, rows: _rows(200))),
      );
      expect(_topIndex(tester, RegExp(r'^C\d{3}$')), 0);
      expect(_topIndex(tester, RegExp(r'^Item \d+$')), 0);

      await tester.drag(find.text('C000'), const Offset(0, -310));
      await tester.pumpAndSettle();

      // The two columns must have moved together: the same record is on top in
      // each, and the reader is no longer at the first row.
      final int pinnedTop = _topIndex(tester, RegExp(r'^C\d{3}$'));
      final int bodyTop = _topIndex(tester, RegExp(r'^Item \d+$'));
      expect(bodyTop, pinnedTop);
      expect(pinnedTop, greaterThan(0));
    });

    testWidgets('a numeric column is right-aligned', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(NodexDataTable<_Row>(columns: _columns, rows: _rows(2))),
      );
      final Align align = tester.widget<Align>(
        find.ancestor(of: find.text('Qty'), matching: find.byType(Align)).first,
      );
      expect(align.alignment, Alignment.centerRight);
    });
  });

  group('sorting from the header', () {
    testWidgets('tapping a header sorts ascending, then descending, then not', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(NodexDataTable<_Row>(columns: _columns, rows: _rows(3))),
      );
      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

      await tester.tap(find.text('Name'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.arrow_upward), findsNothing);
      expect(find.byIcon(Icons.arrow_downward), findsNothing);
    });

    testWidgets('long-pressing a header adds a second sort level', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          NodexDataTable<_Row>(
            columns: _columns,
            rows: _rows(3),
            initialSort: const <TableSortSpec>[TableSortSpec('ward')],
          ),
        ),
      );
      await tester.longPress(find.text('Name'));
      await tester.pumpAndSettle();
      // Two levels are marked, and the second level is numbered.
      expect(find.byIcon(Icons.arrow_upward), findsNWidgets(2));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('long-pressing again removes that level', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          NodexDataTable<_Row>(
            columns: _columns,
            rows: _rows(3),
            initialSort: const <TableSortSpec>[TableSortSpec('ward')],
          ),
        ),
      );
      await tester.longPress(find.text('Name'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Name'));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsNothing);
    });
  });

  group('row interaction', () {
    testWidgets('a tapped row reports itself', (WidgetTester tester) async {
      _Row? tapped;
      await tester.pumpWidget(
        _host(
          NodexDataTable<_Row>(
            columns: _columns,
            rows: _rows(3),
            onRowTap: (_Row row) => tapped = row,
          ),
        ),
      );
      await tester.tap(find.text('C001'));
      await tester.pumpAndSettle();
      expect(tapped?.code, 'C001');
    });

    testWidgets('a table without a tap handler is inert', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(NodexDataTable<_Row>(columns: _columns, rows: _rows(2))),
      );
      await tester.tap(find.text('C001'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
