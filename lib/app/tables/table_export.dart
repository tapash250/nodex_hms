/// Table export (Module 48).
///
/// Two formats, both produced locally: a CSV for the spreadsheet the department
/// already keeps, and a PDF for the register that has to be signed and filed.
/// Nothing here reaches the network, and nothing here is a printing service:
/// the bytes are returned and the caller decides where they go.
///
/// The PDF writer is deliberately small. It emits an uncompressed PDF 1.4 with
/// the base-14 Helvetica font, which every reader can open, rather than pulling
/// in a layout engine for a table with a header row and fixed-height cells.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:nodex_hms/app/tables/nodex_data_table.dart';

/// Formats a table can be exported in.
enum TableExportFormat {
  /// Comma-separated values, one row per line, CRLF terminated.
  csv('CSV', 'csv'),

  /// A printable document with a repeated header row.
  pdf('PDF', 'pdf');

  const TableExportFormat(this.label, this.extension);

  /// Human-readable label.
  final String label;

  /// File extension without the dot.
  final String extension;
}

/// Renders a table as RFC 4180 CSV.
///
/// Quoting is not cosmetic: a clinical note that contains a comma or a newline
/// silently shifts every later column if it is written raw.
String tableToCsv<T>({
  required List<NodexTableColumn<T>> columns,
  required List<T> rows,
}) {
  final StringBuffer buffer = StringBuffer();
  buffer.write(
    columns.map((NodexTableColumn<T> c) => _csvField(c.label)).join(','),
  );
  buffer.write('\r\n');
  for (final T row in rows) {
    buffer.write(
      columns.map((NodexTableColumn<T> c) => _csvField(c.value(row))).join(','),
    );
    buffer.write('\r\n');
  }
  return buffer.toString();
}

String _csvField(String value) {
  final bool needsQuoting =
      value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuoting) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// Renders a table as a PDF document.
///
/// Rows are chunked across pages with the header repeated at the top of each
/// one, because a register whose second page has no column headings cannot be
/// read without the first page beside it.
Uint8List tableToPdf<T>({
  required String title,
  required List<NodexTableColumn<T>> columns,
  required List<T> rows,
  DateTime? generatedAt,
  int rowsPerPage = 32,
}) {
  assert(rowsPerPage > 0, 'A page must hold at least one row.');
  final _PdfDocument document = _PdfDocument();
  final DateTime stamp = (generatedAt ?? DateTime.now()).toUtc();

  // Landscape A4 in points.
  const double pageWidth = 842;
  const double pageHeight = 595;
  const double margin = 36;
  const double titleHeight = 34;
  const double lineHeight = 16;
  const double usableWidth = pageWidth - margin * 2;
  final double totalWeight = columns.fold<double>(
    0,
    (double sum, NodexTableColumn<T> c) => sum + c.width,
  );
  final List<double> widths = columns
      .map((NodexTableColumn<T> c) => c.width / totalWeight * usableWidth)
      .toList(growable: false);

  final int rowsPerChunk = rowsPerPage;
  final List<List<T>> chunks = <List<T>>[];
  if (rows.isEmpty) {
    chunks.add(<T>[]);
  } else {
    for (int start = 0; start < rows.length; start += rowsPerChunk) {
      chunks.add(
        rows.sublist(
          start,
          start + rowsPerChunk > rows.length
              ? rows.length
              : start + rowsPerChunk,
        ),
      );
    }
  }

  for (int page = 0; page < chunks.length; page++) {
    final List<String> commands = <String>[];
    double y = pageHeight - margin;
    commands.add(_text(title, margin, y, size: 14, font: _PdfFont.bold));
    y -= 16;
    commands.add(
      _text(
        'Generated ${stamp.toIso8601String()}'
        '${chunks.length > 1 ? ' · page ${page + 1} of ${chunks.length}' : ''}',
        margin,
        y,
        size: 9,
      ),
    );
    y -= titleHeight - 16;

    double x = margin;
    for (int i = 0; i < columns.length; i++) {
      commands.add(_text(columns[i].label, x, y, size: 9, font: _PdfFont.bold));
      x += widths[i];
    }
    y -= 4;
    commands.add(
      '${_num(margin)} ${_num(y)} m ${_num(pageWidth - margin)} ${_num(y)} l S',
    );
    y -= lineHeight - 4;

    for (final T row in chunks[page]) {
      x = margin;
      for (int i = 0; i < columns.length; i++) {
        final String value = _latin1(columns[i].value(row));
        final double cellWidth = widths[i] - 6;
        final String clipped = _clip(value, cellWidth, columns[i].numeric);
        if (columns[i].numeric) {
          // Right alignment: the value's own width decides where it starts.
          commands.add(
            _text(clipped, x + cellWidth - clipped.length * 4.4, y, size: 9),
          );
        } else {
          commands.add(_text(clipped, x, y, size: 9));
        }
        x += widths[i];
      }
      y -= lineHeight;
    }

    document.addPage(
      content: commands.join('\n'),
      width: pageWidth,
      height: pageHeight,
    );
  }

  return document.build();
}

/// Roughly how many characters of 9pt Helvetica fit in [width].
String _clip(String value, double width, bool numeric) {
  final int maxChars = (width / 4.6).floor();
  if (maxChars <= 0) return '';
  if (value.length <= maxChars) return value;
  if (maxChars <= 1) return value.substring(0, maxChars);
  return '${value.substring(0, maxChars - 1)}…';
}

String _latin1(String value) {
  final StringBuffer buffer = StringBuffer();
  for (final int unit in value.codeUnits) {
    buffer.writeCharCode(unit <= 0xFF ? unit : 0x3F);
  }
  return buffer.toString();
}

String _num(double value) => value.toStringAsFixed(2);

String _text(
  String value,
  double x,
  double y, {
  required double size,
  _PdfFont font = _PdfFont.regular,
}) {
  // The base-14 Helvetica with WinAnsi cannot render anything outside Latin-1.
  // Substituting is the honest failure: the reader sees one placeholder per
  // character instead of a paragraph of mojibake.
  final String escaped = _latin1(value)
      .replaceAll('\\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
  return 'BT /${font.resourceName} ${size.toStringAsFixed(1)} Tf '
      '${_num(x)} ${_num(y)} Td ($escaped) Tj ET';
}

enum _PdfFont {
  regular('F1', 'Helvetica'),
  bold('F2', 'Helvetica-Bold');

  const _PdfFont(this.resourceName, this.baseFont);

  final String resourceName;
  final String baseFont;
}

/// A minimal PDF writer: pages with one uncompressed content stream each.
class _PdfDocument {
  final List<_PdfPage> _pages = <_PdfPage>[];

  void addPage({
    required String content,
    required double width,
    required double height,
  }) => _pages.add(_PdfPage(content, width, height));

  Uint8List build() {
    final List<List<int>> objects = <List<int>>[];

    // 1: catalog, 2: pages, then per page: page object, content stream, and the
    // two fonts are appended after the pages.
    final int fontRegular = 3 + _pages.length * 2;
    final int fontBold = fontRegular + 1;

    objects.add(_object(1, '<< /Type /Catalog /Pages 2 0 R >>'));
    final StringBuffer kids = StringBuffer();
    for (int i = 0; i < _pages.length; i++) {
      kids.write('${3 + i * 2} 0 R ');
    }
    objects.add(
      _object(
        2,
        '<< /Type /Pages /Count ${_pages.length} /Kids [${kids.toString().trim()}] >>',
      ),
    );

    for (int i = 0; i < _pages.length; i++) {
      final _PdfPage page = _pages[i];
      final int pageObject = 3 + i * 2;
      final int contentObject = pageObject + 1;
      objects.add(
        _object(
          pageObject,
          '<< /Type /Page /Parent 2 0 R /MediaBox '
          '[0 0 ${_num(page.width)} ${_num(page.height)}] '
          '/Resources << /Font << /F1 $fontRegular 0 R /F2 $fontBold 0 R >> >> '
          '/Contents $contentObject 0 R >>',
        ),
      );
      final List<int> stream = latin1.encode(page.content);
      objects.add(
        _object(contentObject, '<< /Length ${stream.length} >>', stream),
      );
    }

    objects.add(
      _object(
        fontRegular,
        '<< /Type /Font /Subtype /Type1 /BaseFont /'
        '${_PdfFont.regular.baseFont} /Encoding /WinAnsiEncoding >>',
      ),
    );
    objects.add(
      _object(
        fontBold,
        '<< /Type /Font /Subtype /Type1 /BaseFont /${_PdfFont.bold.baseFont} '
        '/Encoding /WinAnsiEncoding >>',
      ),
    );

    objects.sort(
      (List<int> a, List<int> b) => _objectNumber(a) - _objectNumber(b),
    );

    final List<int> bytes = <int>[];
    bytes.addAll(utf8.encode('%PDF-1.4\n'));
    final List<int> offsets = <int>[0];
    for (final List<int> object in objects) {
      offsets.add(bytes.length);
      bytes.addAll(object);
      bytes.addAll(utf8.encode('\n'));
    }
    final int xrefStart = bytes.length;
    final StringBuffer xref = StringBuffer('xref\n0 ${objects.length + 1}\n');
    xref.write('0000000000 65535 f \n');
    for (int i = 1; i <= objects.length; i++) {
      xref.write('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
    }
    xref.write(
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xrefStart\n%%EOF\n',
    );
    bytes.addAll(utf8.encode(xref.toString()));
    return Uint8List.fromList(bytes);
  }

  static int _objectNumber(List<int> object) {
    final String head = utf8.decode(object.sublist(0, 24));
    return int.parse(head.split(' ').first);
  }

  static List<int> _object(int number, String body, [List<int>? stream]) {
    final StringBuffer buffer = StringBuffer('$number 0 obj\n$body\n');
    if (stream != null) {
      buffer.write('stream\n');
      final List<int> head = utf8.encode(buffer.toString());
      final List<int> tail = utf8.encode('\nendstream\nendobj\n');
      return <int>[...head, ...stream, ...tail];
    }
    buffer.write('endobj\n');
    return utf8.encode(buffer.toString());
  }
}

@immutable
class _PdfPage {
  const _PdfPage(this.content, this.width, this.height);

  final String content;
  final double width;
  final double height;
}
