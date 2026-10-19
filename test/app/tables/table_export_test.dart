/// Tests for table export (Module 48).
///
/// Export is where a register leaves the app, so the tests are about what the
/// reader will find on the other side: a spreadsheet whose columns did not
/// shift, and a document that opens in any reader with its headings on every
/// page.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nodex_hms/app/tables/nodex_data_table.dart';
import 'package:nodex_hms/app/tables/table_export.dart';

/// A row of the test register.
final class _Row {
  const _Row(this.code, this.name, this.note);

  final String code;
  final String name;
  final String? note;
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
  NodexTableColumn<_Row>(key: 'note', label: 'Note', width: 160, value: _note),
];

String _code(_Row row) => row.code;
String _name(_Row row) => row.name;
String _note(_Row row) => row.note ?? '';

List<String> _lines(String csv) =>
    csv.split('\r\n').where((String line) => line.isNotEmpty).toList();

void main() {
  group('CSV', () {
    test('writes the header followed by one line per row', () {
      final String csv = tableToCsv<_Row>(
        columns: _columns,
        rows: const <_Row>[
          _Row('C1', 'Gloves', null),
          _Row('C2', 'Saline', '500ml bags'),
        ],
      );
      expect(_lines(csv), <String>[
        'Code,Name,Note',
        'C1,Gloves,',
        'C2,Saline,500ml bags',
      ]);
    });

    test('terminates every line with CRLF', () {
      final String csv = tableToCsv<_Row>(
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Gloves', null)],
      );
      expect(csv.endsWith('\r\n'), isTrue);
      expect(csv.contains('\n\r'), isFalse);
    });

    test('quotes a field that contains a comma', () {
      final String csv = tableToCsv<_Row>(
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Gloves, sterile', null)],
      );
      expect(_lines(csv).last, 'C1,"Gloves, sterile",');
    });

    test('doubles a quote inside a quoted field', () {
      final String csv = tableToCsv<_Row>(
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Glove 6" size', null)],
      );
      expect(_lines(csv).last, 'C1,"Glove 6"" size",');
    });

    test('quotes a field that contains a line break', () {
      final String csv = tableToCsv<_Row>(
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Gloves', 'first\nsecond')],
      );
      expect(csv.contains('"first\nsecond"'), isTrue);
    });

    test('leaves an ordinary field untouched', () {
      final String csv = tableToCsv<_Row>(
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Saline', 'plain')],
      );
      expect(_lines(csv).last, 'C1,Saline,plain');
    });

    test('writes the header even when there are no rows', () {
      final String csv = tableToCsv<_Row>(
        columns: _columns,
        rows: const <_Row>[],
      );
      expect(_lines(csv), <String>['Code,Name,Note']);
    });
  });

  group('PDF', () {
    String asText(List<int> bytes) => latin1.decode(bytes);

    test('is a PDF a reader will accept', () {
      final List<int> pdf = tableToPdf<_Row>(
        title: 'Stock register',
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Gloves', null)],
      );
      final String text = asText(pdf);
      expect(text.startsWith('%PDF-1.4'), isTrue);
      expect(text.trimRight().endsWith('%%EOF'), isTrue);
      expect(text, contains('/Type /Catalog'));
      expect(text, contains('startxref'));
      expect(text, contains('/BaseFont /Helvetica'));
    });

    test('carries the title, the stamp and the column headings', () {
      final List<int> pdf = tableToPdf<_Row>(
        title: 'Stock register',
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Gloves', null)],
        generatedAt: DateTime.utc(2026, 9, 12, 9, 30),
      );
      final String text = asText(pdf);
      expect(text, contains('(Stock register) Tj'));
      expect(text, contains('2026-09-12T09:30:00.000Z'));
      expect(text, contains('(Code) Tj'));
      expect(text, contains('(Name) Tj'));
      expect(text, contains('(Note) Tj'));
      expect(text, contains('(Gloves) Tj'));
    });

    test('spreads a long register over pages and repeats the headings', () {
      final List<_Row> rows = <_Row>[
        for (int i = 0; i < 40; i++) _Row('C$i', 'Item $i', null),
      ];
      final List<int> pdf = tableToPdf<_Row>(
        title: 'Stock register',
        columns: _columns,
        rows: rows,
        generatedAt: DateTime.utc(2026, 9, 12),
        rowsPerPage: 15,
      );
      final String text = asText(pdf);
      expect(text, contains('/Count 3'));
      expect(RegExp(RegExp.escape('(Code) Tj')).allMatches(text).length, 3);
      expect(text, contains('page 1 of 3'));
      expect(text, contains('page 3 of 3'));
    });

    test('is a single page with headings when there are no rows', () {
      final List<int> pdf = tableToPdf<_Row>(
        title: 'Stock register',
        columns: _columns,
        rows: const <_Row>[],
        generatedAt: DateTime.utc(2026, 9, 12),
      );
      final String text = asText(pdf);
      expect(text, contains('/Count 1'));
      expect(text, contains('(Stock register) Tj'));
      expect(text, isNot(contains('page 1 of 1')));
    });

    test('escapes the characters that would end a PDF string early', () {
      final List<int> pdf = tableToPdf<_Row>(
        title: 'Register (draft)',
        columns: _columns,
        rows: const <_Row>[_Row('C1', r'Back\slash', 'Braces (both)')],
      );
      final String text = asText(pdf);
      expect(text, contains(r'(Register \(draft\)) Tj'));
      expect(text, contains(r'(Back\\slash) Tj'));
      expect(text, contains(r'(Braces \(both\)) Tj'));
    });

    test('replaces characters outside Latin-1 rather than corrupting them', () {
      const String title = 'স্টক রেজিস্টার';
      final List<int> pdf = tableToPdf<_Row>(
        title: title,
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Gloves', null)],
      );
      final String text = asText(pdf);
      // Bengali is not in the WinAnsi set, so the writer emits the substitution
      // character (0x3F) instead of mojibake bytes: one per code unit, and the
      // characters that do map — a space — survive.
      final String expected = title.codeUnits
          .map((int unit) => unit <= 0xFF ? String.fromCharCode(unit) : '?')
          .join();
      expect(expected.contains(' '), isTrue);
      expect(text, contains('($expected) Tj'));
      expect(text, isNot(contains('\u09b8')));
    });

    test('writes an xref entry for every object it declares', () {
      final List<int> pdf = tableToPdf<_Row>(
        title: 'Stock register',
        columns: _columns,
        rows: const <_Row>[_Row('C1', 'Gloves', null)],
      );
      final String text = asText(pdf);
      final RegExpMatch? size = RegExp(r'/Size (\d+)').firstMatch(text);
      expect(size, isNotNull);
      final int objects = int.parse(size!.group(1)!) - 1;
      final int declared = RegExp(
        r'^\d+ 0 obj$',
        multiLine: true,
      ).allMatches(text).length;
      expect(declared, objects);
      final String xref = text.substring(text.indexOf('xref\n'));
      final int entries = RegExp(
        r'^\d{10} \d{5} n $',
        multiLine: true,
      ).allMatches(xref).length;
      expect(entries, objects);
    });

    test('exposes the format list a screen offers', () {
      expect(
        TableExportFormat.values.map((TableExportFormat f) => f.extension),
        <String>['csv', 'pdf'],
      );
      expect(TableExportFormat.pdf.label, 'PDF');
    });
  });
}
