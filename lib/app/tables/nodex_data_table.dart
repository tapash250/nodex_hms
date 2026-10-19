/// Master data table engine (Module 48).
///
/// Dense clinical registers — stock, patients, orders — are long and wide at
/// the same time: the identifier that names a row must stay on screen while the
/// reader scrolls across its facts, and the list must not build a thousand rows
/// to show twelve. This engine does both: the first column can be pinned, only
/// the rows near the viewport are built, and sorting is multi-column so a
/// register can be read "by ward, then by name".
///
/// The engine carries no domain knowledge. A caller supplies the columns and
/// how one row compares to another, and nothing here guesses a type.
library;

import 'package:flutter/material.dart';

/// One column of a master data table.
@immutable
final class NodexTableColumn<T> {
  /// Declares a column.
  const NodexTableColumn({
    required this.key,
    required this.label,
    required this.value,
    this.width = 140,
    this.pinned = false,
    this.numeric = false,
    this.compare,
  });

  /// Stable identifier, used by the sort state and by exports.
  final String key;

  /// Header text.
  final String label;

  /// Renders one cell as text.
  final String Function(T row) value;

  /// Column width in logical pixels.
  final double width;

  /// Whether the column stays on screen while the rest scrolls.
  final bool pinned;

  /// Whether the column holds numbers, which are right-aligned.
  final bool numeric;

  /// Comparison used when sorting by this column.
  ///
  /// Defaults to comparing the rendered text, which is right for codes and
  /// wrong for anything else — a caller that stores numbers or instants passes
  /// the comparison it means.
  final int Function(T a, T b)? compare;

  /// Compares two rows by this column.
  int compareRows(T a, T b) =>
      (compare ?? (T x, T y) => value(x).compareTo(value(y)))(a, b);
}

/// The direction a column is sorted in.
enum TableSortDirection {
  /// Smallest first.
  ascending,

  /// Largest first.
  descending;

  /// The direction a tap toggles to.
  TableSortDirection get flipped => this == TableSortDirection.ascending
      ? TableSortDirection.descending
      : TableSortDirection.ascending;

  /// Applied to a comparison result.
  int apply(int comparison) =>
      this == TableSortDirection.ascending ? comparison : -comparison;
}

/// One level of a multi-column sort.
@immutable
final class TableSortSpec {
  /// Declares a sort level.
  const TableSortSpec(
    this.columnKey, [
    this.direction = TableSortDirection.ascending,
  ]);

  /// Column being sorted.
  final String columnKey;

  /// Direction of this level.
  final TableSortDirection direction;

  /// The same level in the other direction.
  TableSortSpec get flipped => TableSortSpec(columnKey, direction.flipped);
}

/// A data table that scrolls both ways and stays readable while it does.
///
/// The first column may be pinned, and rows are built lazily. The pinned column
/// and the scrollable body are two lists with one scroll position between them:
/// whichever the reader drags moves the other, so a row never shows the
/// identifier of one record beside the facts of another.
class NodexDataTable<T> extends StatefulWidget {
  /// Creates a table.
  const NodexDataTable({
    required this.columns,
    required this.rows,
    this.initialSort = const <TableSortSpec>[],
    this.onRowTap,
    this.emptyMessage = 'Nothing to show.',
    this.rowHeight = 44,
    this.headerHeight = 40,
    this.buildRowTrailing,
    super.key,
  });

  /// Column definitions, in display order.
  final List<NodexTableColumn<T>> columns;

  /// Rows to display.
  final List<T> rows;

  /// Sort applied before the reader changes it.
  final List<TableSortSpec> initialSort;

  /// Called when a row is tapped.
  final void Function(T row)? onRowTap;

  /// Shown when [rows] is empty.
  final String emptyMessage;

  /// Height of one row.
  final double rowHeight;

  /// Height of the header.
  final double headerHeight;

  /// Optional trailing widget per row, for a row action.
  final Widget Function(T row)? buildRowTrailing;

  /// The sort a table applies, in level order.
  ///
  /// Exposed so a caller can sort an export the same way the reader sees the
  /// screen: an exported register that disagrees with the visible one is a
  /// support ticket.
  static List<T> sortRows<T>({
    required List<T> rows,
    required List<NodexTableColumn<T>> columns,
    required List<TableSortSpec> sorts,
  }) {
    if (sorts.isEmpty) return List<T>.unmodifiable(rows);
    final Map<String, NodexTableColumn<T>> byKey =
        <String, NodexTableColumn<T>>{
          for (final NodexTableColumn<T> column in columns) column.key: column,
        };
    final List<T> sorted = List<T>.of(rows);
    sorted.sort((T a, T b) {
      for (final TableSortSpec spec in sorts) {
        final NodexTableColumn<T>? column = byKey[spec.columnKey];
        if (column == null) continue;
        final int comparison = column.compareRows(a, b);
        if (comparison != 0) return spec.direction.apply(comparison);
      }
      return 0;
    });
    return sorted;
  }

  @override
  State<NodexDataTable<T>> createState() => _NodexDataTableState<T>();
}

class _NodexDataTableState<T> extends State<NodexDataTable<T>> {
  late List<TableSortSpec> _sorts = List<TableSortSpec>.of(widget.initialSort);
  final ScrollController _pinned = ScrollController();
  final ScrollController _body = ScrollController();

  @override
  void dispose() {
    _pinned.dispose();
    _body.dispose();
    super.dispose();
  }

  List<NodexTableColumn<T>> get _pinnedColumns =>
      widget.columns.where((NodexTableColumn<T> c) => c.pinned).toList();

  List<NodexTableColumn<T>> get _scrollingColumns =>
      widget.columns.where((NodexTableColumn<T> c) => !c.pinned).toList();

  double _widthOf(List<NodexTableColumn<T>> columns) => columns.fold<double>(
    0,
    (double total, NodexTableColumn<T> c) => total + c.width,
  );

  List<T> get _sortedRows => NodexDataTable.sortRows<T>(
    rows: widget.rows,
    columns: widget.columns,
    sorts: _sorts,
  );

  void _onHeaderTap(NodexTableColumn<T> column) {
    setState(() {
      final int index = _sorts.indexWhere(
        (TableSortSpec spec) => spec.columnKey == column.key,
      );
      if (index < 0) {
        _sorts = <TableSortSpec>[TableSortSpec(column.key)];
        return;
      }
      // Tapping the only sort level walks ascending → descending → unsorted;
      // tapping a lower level flips that level and keeps the levels above it.
      if (_sorts.length == 1 &&
          _sorts.first.direction == TableSortDirection.descending) {
        _sorts = <TableSortSpec>[];
        return;
      }
      _sorts = <TableSortSpec>[
        for (int i = 0; i < _sorts.length; i++)
          if (i == index) _sorts[i].flipped else _sorts[i],
      ];
    });
  }

  void _onHeaderLongPress(NodexTableColumn<T> column) {
    setState(() {
      final bool present = _sorts.any(
        (TableSortSpec spec) => spec.columnKey == column.key,
      );
      if (present) {
        _sorts = _sorts
            .where((TableSortSpec spec) => spec.columnKey != column.key)
            .toList(growable: false);
        return;
      }
      _sorts = <TableSortSpec>[..._sorts, TableSortSpec(column.key)];
    });
  }

  void _sync(ScrollNotification notification, ScrollController other) {
    if (notification is! ScrollUpdateNotification) return;
    if (!other.hasClients) return;
    final double offset = notification.metrics.pixels;
    if ((other.offset - offset).abs() < 0.5) return;
    other.jumpTo(offset.clamp(0, other.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<T> rows = _sortedRows;
    final List<NodexTableColumn<T>> pinned = _pinnedColumns;
    final List<NodexTableColumn<T>> scrolling = _scrollingColumns;
    final double pinnedWidth = _widthOf(pinned);
    final double scrollingWidth = _widthOf(scrolling);
    final double bodyWidth =
        scrollingWidth + (widget.buildRowTrailing == null ? 0 : 56);

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(widget.emptyMessage)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: widget.headerHeight,
          child: Row(
            children: <Widget>[
              if (pinnedWidth > 0)
                SizedBox(
                  width: pinnedWidth,
                  child: Row(
                    children: <Widget>[
                      for (final NodexTableColumn<T> column in pinned)
                        _HeaderCell(
                          column: column,
                          sort: _sortFor(column),
                          sortPosition: _positionOf(column),
                          height: widget.headerHeight,
                          onTap: () => _onHeaderTap(column),
                          onLongPress: () => _onHeaderLongPress(column),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: bodyWidth,
                    child: Row(
                      children: <Widget>[
                        for (final NodexTableColumn<T> column in scrolling)
                          _HeaderCell(
                            column: column,
                            sort: _sortFor(column),
                            sortPosition: _positionOf(column),
                            height: widget.headerHeight,
                            onTap: () => _onHeaderTap(column),
                            onLongPress: () => _onHeaderLongPress(column),
                          ),
                        if (widget.buildRowTrailing != null)
                          const SizedBox(width: 56),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.dividerColor),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (pinnedWidth > 0)
                SizedBox(
                  width: pinnedWidth,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification notification) {
                      _sync(notification, _body);
                      return false;
                    },
                    child: ListView.builder(
                      controller: _pinned,
                      itemExtent: widget.rowHeight,
                      itemCount: rows.length,
                      itemBuilder: (BuildContext context, int index) =>
                          _pinnedRow(rows[index], pinned, index),
                    ),
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: bodyWidth,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (ScrollNotification notification) {
                        _sync(notification, _pinned);
                        return false;
                      },
                      child: ListView.builder(
                        controller: _body,
                        itemExtent: widget.rowHeight,
                        itemCount: rows.length,
                        itemBuilder: (BuildContext context, int index) =>
                            _bodyRow(rows[index], scrolling, index),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  TableSortSpec? _sortFor(NodexTableColumn<T> column) => _sorts
      .where((TableSortSpec spec) => spec.columnKey == column.key)
      .firstOrNull;

  int _positionOf(NodexTableColumn<T> column) =>
      _sorts.indexWhere((TableSortSpec spec) => spec.columnKey == column.key);

  Widget _pinnedRow(T row, List<NodexTableColumn<T>> columns, int index) {
    final bool tappable = widget.onRowTap != null;
    return InkWell(
      onTap: tappable ? () => widget.onRowTap!(row) : null,
      child: Row(
        children: <Widget>[
          for (final NodexTableColumn<T> column in columns)
            SizedBox(
              width: column.width,
              child: _Cell(
                text: column.value(row),
                numeric: column.numeric,
                pinned: true,
                index: index,
              ),
            ),
        ],
      ),
    );
  }

  Widget _bodyRow(T row, List<NodexTableColumn<T>> columns, int index) {
    final bool tappable = widget.onRowTap != null;
    return InkWell(
      onTap: tappable ? () => widget.onRowTap!(row) : null,
      child: Row(
        children: <Widget>[
          for (final NodexTableColumn<T> column in columns)
            SizedBox(
              width: column.width,
              child: _Cell(
                text: column.value(row),
                numeric: column.numeric,
                pinned: false,
                index: index,
              ),
            ),
          if (widget.buildRowTrailing != null)
            SizedBox(width: 56, child: widget.buildRowTrailing!(row)),
        ],
      ),
    );
  }
}

class _HeaderCell<T> extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.sort,
    required this.sortPosition,
    required this.height,
    required this.onTap,
    required this.onLongPress,
  });

  final NodexTableColumn<T> column;
  final TableSortSpec? sort;
  final int sortPosition;
  final double height;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: column.width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: column.numeric
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: column.numeric
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: <Widget>[
            Flexible(
              child: Text(
                column.label,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge,
              ),
            ),
            if (sort != null) ...<Widget>[
              Icon(
                sort!.direction == TableSortDirection.ascending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 14,
              ),
              if (sortPosition > 0)
                Text('${sortPosition + 1}', style: theme.textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.numeric,
    required this.pinned,
    required this.index,
  });

  final String text;
  final bool numeric;
  final bool pinned;
  final int index;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
      color: pinned
          ? theme.colorScheme.surfaceContainerLow
          : (index.isEven ? theme.colorScheme.surface : null),
      child: Text(text, overflow: TextOverflow.ellipsis),
    );
  }
}
