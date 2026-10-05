import 'dart:math' as math;

import 'package:flutter/widgets.dart';

enum TableAlign { none, left, center, right }

/// A GitHub-flavored Markdown table found around the caret.
class MarkdownTable {
  MarkdownTable({
    required this.firstLine,
    required this.lastLine,
    required this.rows,
    required this.aligns,
    required this.row,
    required this.column,
  });

  /// Source line range (inclusive) of the table.
  final int firstLine;
  final int lastLine;

  /// Header first, then body rows; the delimiter row is not included.
  final List<List<String>> rows;
  final List<TableAlign> aligns;

  /// Caret cell: row index into [rows] and column index.
  int row;
  int column;

  int get columns => aligns.length;

  static final _delimiter = RegExp(
    r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$',
  );

  static bool _isRow(String line) => line.trim().contains('|');

  static List<String> _cells(String line) {
    var t = line.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|') && !t.endsWith(r'\|')) t = t.substring(0, t.length - 1);
    final cells = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      if (t[i] == '\\' && i + 1 < t.length && t[i + 1] == '|') {
        buf.write(r'\|');
        i++;
      } else if (t[i] == '|') {
        cells.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(t[i]);
      }
    }
    cells.add(buf.toString().trim());
    return cells;
  }

  /// The table containing [offset] in [text], or null.
  static MarkdownTable? at(String text, int offset) {
    final lines = text.split('\n');
    var line = 0, start = 0;
    for (; line < lines.length; line++) {
      final end = start + lines[line].length;
      if (offset <= end) break;
      start = end + 1;
    }
    if (line >= lines.length || !_isRow(lines[line])) return null;
    var first = line, last = line;
    while (first > 0 && _isRow(lines[first - 1])) {
      first--;
    }
    while (last < lines.length - 1 && _isRow(lines[last + 1])) {
      last++;
    }
    // A table needs a header followed by a delimiter row.
    if (last - first < 1 || !_delimiter.hasMatch(lines[first + 1])) {
      return null;
    }
    final aligns = [
      for (final cell in _cells(lines[first + 1]))
        cell.startsWith(':') && cell.endsWith(':')
            ? TableAlign.center
            : cell.endsWith(':')
            ? TableAlign.right
            : cell.startsWith(':')
            ? TableAlign.left
            : TableAlign.none,
    ];
    final rows = <List<String>>[
      for (var i = first; i <= last; i++)
        if (i != first + 1) _cells(lines[i]),
    ];
    final columns = rows.fold<int>(
      aligns.length,
      (m, r) => math.max(m, r.length),
    );
    while (aligns.length < columns) {
      aligns.add(TableAlign.none);
    }
    for (final r in rows) {
      while (r.length < columns) {
        r.add('');
      }
    }
    // Caret position: count unescaped pipes before the caret.
    final inLine = offset - start;
    final source = lines[line];
    final lead = source.length - source.trimLeft().length;
    var pipes = 0;
    for (var i = 0; i < inLine && i < source.length; i++) {
      if (source[i] == '|' && (i == 0 || source[i - 1] != '\\')) pipes++;
    }
    final leading = source.trimLeft().startsWith('|') && inLine > lead ? 1 : 0;
    final row = line <= first + 1 ? 0 : line - first - 1;
    return MarkdownTable(
      firstLine: first,
      lastLine: last,
      rows: rows,
      aligns: aligns,
      row: row,
      column: (pipes - leading).clamp(0, columns - 1),
    );
  }

  /// Aligned Markdown for the table.
  String format() {
    final widths = List<int>.filled(columns, 3);
    for (final r in rows) {
      for (var c = 0; c < columns; c++) {
        widths[c] = math.max(widths[c], r[c].characters.length);
      }
    }
    String pad(String cell, int c) {
      final gap = widths[c] - cell.characters.length;
      return switch (aligns[c]) {
        TableAlign.right => '${' ' * gap}$cell',
        TableAlign.center =>
          '${' ' * (gap ~/ 2)}$cell${' ' * (gap - gap ~/ 2)}',
        _ => '$cell${' ' * gap}',
      };
    }

    String line(List<String> cells) =>
        '| ${[for (var c = 0; c < columns; c++) pad(cells[c], c)].join(' | ')} |';
    final delimiter = [
      for (var c = 0; c < columns; c++)
        switch (aligns[c]) {
          TableAlign.left => ':${'-' * (widths[c] - 1)}',
          TableAlign.right => '${'-' * (widths[c] - 1)}:',
          TableAlign.center => ':${'-' * (widths[c] - 2)}:',
          TableAlign.none => '-' * widths[c],
        },
    ];
    return [
      line(rows.first),
      '| ${delimiter.join(' | ')} |',
      for (final r in rows.skip(1)) line(r),
    ].join('\n');
  }

  /// Offset of cell ([row], [column]) content within [format]'s output.
  int cellOffset(int row, int column) {
    final text = format();
    final lines = text.split('\n');
    final line = row == 0 ? 0 : row + 1;
    var offset = 0;
    for (var i = 0; i < line; i++) {
      offset += lines[i].length + 1;
    }
    var pipes = 0;
    final source = lines[line];
    for (var i = 0; i < source.length; i++) {
      if (source[i] == '|' && (i == 0 || source[i - 1] != '\\')) {
        if (pipes == column) {
          // Skip padding to the first character of the cell text.
          var j = i + 1;
          while (j < source.length && source[j] == ' ') {
            j++;
          }
          if (j >= source.length || source[j] == '|') j = i + 2;
          return offset + math.min(j, source.length);
        }
        pipes++;
      }
    }
    return offset + source.length;
  }
}

enum TableOp {
  rowAbove,
  rowBelow,
  deleteRow,
  columnLeft,
  columnRight,
  deleteColumn,
  alignLeft,
  alignCenter,
  alignRight,
  format,
}

abstract final class TableCommands {
  /// Applies [op] to the table at the caret. Returns false when the caret
  /// is not in a table.
  static bool apply(TextEditingController c, TableOp op) {
    final table = MarkdownTable.at(c.text, c.selection.baseOffset);
    if (table == null) return false;
    var row = table.row, column = table.column;
    switch (op) {
      case TableOp.rowAbove:
        // The header stays the header: a row "above" it goes below it.
        final at = math.max(1, row);
        table.rows.insert(at, List.filled(table.columns, '', growable: true));
        row = at;
      case TableOp.rowBelow:
        table.rows.insert(
          row + 1,
          List.filled(table.columns, '', growable: true),
        );
        row = row + 1;
      case TableOp.deleteRow:
        if (row == 0 || table.rows.length <= 2) {
          // Keep at least a header and one row; clear instead.
          for (var i = 0; i < table.columns; i++) {
            table.rows[row][i] = '';
          }
        } else {
          table.rows.removeAt(row);
          row = math.min(row, table.rows.length - 1);
        }
      case TableOp.columnLeft || TableOp.columnRight:
        final at = op == TableOp.columnLeft ? column : column + 1;
        for (final r in table.rows) {
          r.insert(at, '');
        }
        table.aligns.insert(at, TableAlign.none);
        column = at;
      case TableOp.deleteColumn:
        if (table.columns <= 1) return true;
        for (final r in table.rows) {
          r.removeAt(column);
        }
        table.aligns.removeAt(column);
        column = math.min(column, table.columns - 1);
      case TableOp.alignLeft:
        table.aligns[column] = TableAlign.left;
      case TableOp.alignCenter:
        table.aligns[column] = TableAlign.center;
      case TableOp.alignRight:
        table.aligns[column] = TableAlign.right;
      case TableOp.format:
        break;
    }
    _replace(c, table, row, column);
    return true;
  }

  /// Tab / Shift+Tab inside a table: formats it and moves to the next or
  /// previous cell, adding a row after the last cell. Returns false outside
  /// a table.
  static bool moveCell(TextEditingController c, {bool backwards = false}) {
    final table = MarkdownTable.at(c.text, c.selection.baseOffset);
    if (table == null) return false;
    var row = table.row, column = table.column;
    if (backwards) {
      if (column > 0) {
        column--;
      } else if (row > 0) {
        row--;
        column = table.columns - 1;
      }
    } else if (column < table.columns - 1) {
      column++;
    } else {
      row++;
      column = 0;
      if (row >= table.rows.length) {
        table.rows.add(List.filled(table.columns, '', growable: true));
      }
    }
    _replace(c, table, row, column);
    return true;
  }

  /// A new table with [rows] body rows and [columns] columns.
  static String create(int rows, int columns, {String header = 'Column'}) {
    final table = MarkdownTable(
      firstLine: 0,
      lastLine: 0,
      rows: [
        [for (var c = 0; c < columns; c++) '$header ${c + 1}'],
        for (var r = 0; r < rows; r++) List.filled(columns, '', growable: true),
      ],
      aligns: List.filled(columns, TableAlign.none, growable: true),
      row: 0,
      column: 0,
    );
    return table.format();
  }

  static void _replace(
    TextEditingController c,
    MarkdownTable table,
    int row,
    int column,
  ) {
    final lines = c.text.split('\n');
    var start = 0;
    for (var i = 0; i < table.firstLine; i++) {
      start += lines[i].length + 1;
    }
    var end = start;
    for (var i = table.firstLine; i <= table.lastLine; i++) {
      end += lines[i].length + (i < table.lastLine ? 1 : 0);
    }
    final formatted = table.format();
    final caret = start + table.cellOffset(row, column);
    c.value = TextEditingValue(
      text: c.text.replaceRange(start, end, formatted),
      selection: TextSelection.collapsed(offset: caret),
    );
  }
}
