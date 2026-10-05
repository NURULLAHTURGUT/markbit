import '../../domain/colored_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Text transformations used by the formatting toolbar and shortcuts. All of
/// them work on a plain [TextEditingController] so they're trivially testable.
abstract final class MarkdownCommands {
  static TextRange _range(TextEditingController c) {
    final s = c.selection;
    if (!s.isValid) {
      return TextRange.collapsed(c.text.length);
    }
    return TextRange(start: s.start, end: s.end);
  }

  static void _set(TextEditingController c, String text, TextSelection sel) {
    c.value = TextEditingValue(text: text, selection: sel);
  }

  /// Wraps the selection with [before]/[after]; unwraps if already wrapped.
  static void wrap(
    TextEditingController c,
    String before,
    String after, {
    String placeholder = '',
  }) {
    final text = c.text;
    final r = _range(c);
    final selected = text.substring(r.start, r.end);
    final hasBefore =
        r.start >= before.length &&
        text.substring(r.start - before.length, r.start) == before;
    final hasAfter =
        text.length >= r.end + after.length &&
        text.substring(r.end, r.end + after.length) == after;

    if (hasBefore && hasAfter && selected.isNotEmpty) {
      _set(
        c,
        text.replaceRange(
          r.start - before.length,
          r.end + after.length,
          selected,
        ),
        TextSelection(
          baseOffset: r.start - before.length,
          extentOffset: r.end - before.length,
        ),
      );
      return;
    }
    final inner = selected.isEmpty ? placeholder : selected;
    final start = r.start + before.length;
    _set(
      c,
      text.replaceRange(r.start, r.end, '$before$inner$after'),
      TextSelection(baseOffset: start, extentOffset: start + inner.length),
    );
  }

  static void textColor(TextEditingController c, String? hex) =>
      _textStyle(c, 'color', hex == null ? null : '#$hex');
  static void fontSize(TextEditingController c, double? points) {
    if (points != null && (points < 8 || points > 48)) return;
    _textStyle(
      c,
      'font-size',
      points == null ? null : '${points.toStringAsFixed(0)}pt',
    );
  }

  static void fontFamily(TextEditingController c, String? family) {
    if (family != null && !textFontFamilies.contains(family)) return;
    _textStyle(c, 'font-family', family);
  }

  static void _textStyle(
    TextEditingController c,
    String property,
    String? value,
  ) {
    final range = _range(c);
    for (final match in styledTextPattern.allMatches(c.text)) {
      final styles = parseTextStyle(match[1]!);
      if (styles == null) continue;
      final contentStart = match.start + match[0]!.indexOf('>') + 1;
      final contentEnd = match.end - '</span>'.length;
      if (range.start < contentStart || range.end > contentEnd) continue;
      final changed = Map<String, String>.from(styles);
      if (value == null) {
        changed.remove(property);
      } else {
        changed[property] = value;
      }
      final content = match[2]!;
      final start = range.start - contentStart, end = range.end - contentStart;
      final prefix = start == 0
          ? ''
          : styledText(content.substring(0, start), styles);
      final suffix = end == content.length
          ? ''
          : styledText(content.substring(end), styles);
      final selected = styledText(content.substring(start, end), changed);
      final openingLength = changed.isEmpty ? 0 : selected.indexOf('>') + 1;
      final offset = match.start + prefix.length + openingLength;
      _set(
        c,
        c.text.replaceRange(match.start, match.end, '$prefix$selected$suffix'),
        TextSelection(baseOffset: offset, extentOffset: offset + end - start),
      );
      return;
    }
    if (value == null) return;
    final selected = c.text.substring(range.start, range.end);
    final replacement = styledText(selected, {property: value});
    final offset = range.start + replacement.indexOf('>') + 1;
    _set(
      c,
      c.text.replaceRange(range.start, range.end, replacement),
      TextSelection(baseOffset: offset, extentOffset: offset + selected.length),
    );
  }

  static void bold(TextEditingController c) =>
      wrap(c, '**', '**', placeholder: 'bold');
  static void italic(TextEditingController c) =>
      wrap(c, '*', '*', placeholder: 'italic');
  static void strike(TextEditingController c) =>
      wrap(c, '~~', '~~', placeholder: 'text');
  static void highlight(TextEditingController c) =>
      wrap(c, '==', '==', placeholder: 'text');
  static void inlineCode(TextEditingController c) =>
      wrap(c, '`', '`', placeholder: 'code');

  static void link(TextEditingController c) {
    final text = c.text;
    final r = _range(c);
    final selected = text.substring(r.start, r.end);
    if (selected.isEmpty) {
      _set(
        c,
        text.replaceRange(r.start, r.end, '[text](https://)'),
        TextSelection(baseOffset: r.start + 1, extentOffset: r.start + 5),
      );
    } else {
      final urlStart = r.start + selected.length + 3;
      _set(
        c,
        text.replaceRange(r.start, r.end, '[$selected](https://)'),
        TextSelection(baseOffset: urlStart, extentOffset: urlStart + 8),
      );
    }
  }

  /// Applies [transform] to every line touched by the selection.
  static void _mapLines(
    TextEditingController c,
    List<String> Function(List<String> lines) transform,
  ) {
    final text = c.text;
    final r = _range(c);
    final lineStart = r.start == 0
        ? 0
        : text.lastIndexOf('\n', r.start - 1) + 1;
    var lineEnd = text.indexOf('\n', r.end);
    if (lineEnd == -1) lineEnd = text.length;
    final lines = text.substring(lineStart, lineEnd).split('\n');
    final mapped = transform(lines).join('\n');
    _set(
      c,
      text.replaceRange(lineStart, lineEnd, mapped),
      TextSelection(
        baseOffset: lineStart,
        extentOffset: lineStart + mapped.length,
      ),
    );
  }

  static final RegExp _headingPrefix = RegExp(r'^#{1,6}\s+');

  static void heading(TextEditingController c, int level) {
    final prefix = '${'#' * level} ';
    _mapLines(c, (lines) {
      final allSame = lines.every((l) => l.startsWith(prefix));
      return [
        for (final l in lines)
          allSame
              ? l.substring(prefix.length)
              : '$prefix${l.replaceFirst(_headingPrefix, '')}',
      ];
    });
  }

  /// Cycles the current line through H1 -> H2 -> H3 -> plain.
  static void cycleHeading(TextEditingController c) {
    final text = c.text;
    final r = _range(c);
    final lineStart = r.start == 0
        ? 0
        : text.lastIndexOf('\n', r.start - 1) + 1;
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd == -1) lineEnd = text.length;
    final m = RegExp(
      r'^(#{1,6})\s',
    ).firstMatch(text.substring(lineStart, lineEnd));
    final current = m?.group(1)!.length ?? 0;
    final next = current >= 3 ? 0 : current + 1;
    final stripped = text
        .substring(lineStart, lineEnd)
        .replaceFirst(_headingPrefix, '');
    final line = next == 0 ? stripped : '${'#' * next} $stripped';
    _set(
      c,
      text.replaceRange(lineStart, lineEnd, line),
      TextSelection.collapsed(offset: lineStart + line.length),
    );
  }

  static void quote(TextEditingController c) => _mapLines(c, (lines) {
    final all = lines.every((l) => l.startsWith('> '));
    return [for (final l in lines) all ? l.substring(2) : '> $l'];
  });

  static final RegExp _bullet = RegExp(r'^(\s*)[-*+]\s+');
  static final RegExp _ordered = RegExp(r'^(\s*)\d+[.)]\s+');
  static final RegExp _taskLine = RegExp(r'^(\s*)([-*+])\s+\[([ xX])\]\s');

  static void bulletList(TextEditingController c) => _mapLines(c, (lines) {
    final all = lines.every(_bullet.hasMatch);
    return [
      for (final l in lines)
        all
            ? l.replaceFirst(_bullet, r'')
            : '- ${l.replaceFirst(_ordered, '')}',
    ];
  });

  static void orderedList(TextEditingController c) => _mapLines(c, (lines) {
    final all = lines.every(_ordered.hasMatch);
    return [
      for (var i = 0; i < lines.length; i++)
        all
            ? lines[i].replaceFirst(_ordered, '')
            : '${i + 1}. ${lines[i].replaceFirst(_bullet, '')}',
    ];
  });

  /// Cycles: plain/bullet -> `- [ ]` -> `- [x]` -> `- [ ]`.
  static void toggleTask(TextEditingController c) => _mapLines(c, (lines) {
    return [
      for (final l in lines)
        if (_taskLine.hasMatch(l))
          l.replaceFirstMapped(
            _taskLine,
            (m) => '${m[1]}${m[2]} [${m[3] == ' ' ? 'x' : ' '}] ',
          )
        else if (_bullet.hasMatch(l))
          l.replaceFirstMapped(_bullet, (m) => '${m[1]}- [ ] ')
        else
          '- [ ] ${l.replaceFirst(_ordered, '')}',
    ];
  });

  static void codeBlock(TextEditingController c, {String language = ''}) {
    final text = c.text;
    final r = _range(c);
    final selected = text.substring(r.start, r.end);
    final needsLead = r.start > 0 && text[r.start - 1] != '\n';
    final lead = needsLead ? '\n' : '';
    final block = '$lead```$language\n$selected\n```\n';
    final caret = r.start + lead.length + 3 + language.length;
    _set(
      c,
      text.replaceRange(r.start, r.end, block),
      TextSelection.collapsed(offset: caret),
    );
  }

  static void horizontalRule(TextEditingController c) =>
      insert(c, '\n\n---\n\n');

  static void table(TextEditingController c) => insert(
    c,
    '\n| Column A | Column B |\n| --- | --- |\n| value | value |\n',
  );

  static void image(
    TextEditingController c,
    String uri,
    String name, {
    int width = 100,
  }) {
    final r = _range(c);
    final label = (r.isCollapsed ? name : c.text.substring(r.start, r.end))
        .replaceAll('\\', '\\\\')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll(RegExp(r'[\r\n]+'), ' ');
    final before = r.start > 0 && c.text[r.start - 1] != '\n' ? '\n\n' : '';
    final after = r.end < c.text.length && c.text[r.end] != '\n'
        ? '\n\n'
        : '\n';
    insert(
      c,
      '$before![$label]($uri${width == 100 ? '' : ' "width=$width%"'})$after',
    );
  }

  static void insert(TextEditingController c, String snippet) {
    final text = c.text;
    final r = _range(c);
    _set(
      c,
      text.replaceRange(r.start, r.end, snippet),
      TextSelection.collapsed(offset: r.start + snippet.length),
    );
  }

  /// Indents (or outdents) the selected lines; with a caret only, inserts
  /// [unit] (or removes one unit before the caret when outdenting).
  static void indent(
    TextEditingController c, {
    bool outdent = false,
    String unit = '  ',
  }) {
    final r = _range(c);
    if (r.isCollapsed && !outdent) {
      insert(c, unit);
      return;
    }
    _mapLines(
      c,
      (lines) => [
        for (final l in lines)
          if (outdent)
            l.startsWith(unit)
                ? l.substring(unit.length)
                : l.replaceFirst(RegExp(r'^[ \t]{1,4}'), '')
          else
            '$unit$l',
      ],
    );
  }

  /// Zero-based line index of the caret.
  static int caretLine(TextEditingController c) {
    final s = c.selection;
    if (!s.isValid) return 0;
    final before = c.text.substring(0, s.baseOffset.clamp(0, c.text.length));
    return '\n'.allMatches(before).length;
  }

  /// (line, column), both one-based.
  static (int, int) caretPosition(TextEditingController c) {
    final s = c.selection;
    final off = s.isValid ? s.extentOffset.clamp(0, c.text.length) : 0;
    final before = c.text.substring(0, off);
    final line = '\n'.allMatches(before).length + 1;
    final col = off - (before.lastIndexOf('\n') + 1) + 1;
    return (line, col);
  }
}

/// Continues lists, quotes and indentation when the user presses Enter.
/// Works through an input formatter so it behaves identically with hardware
/// keyboards and soft keyboards.
class SmartEnterFormatter extends TextInputFormatter {
  SmartEnterFormatter({required this.isCode, this.indentUnit = '  '});

  final bool isCode;
  final String indentUnit;

  static final RegExp _listLine = RegExp(
    r'^(\s*)([-*+]|\d+[.)])(\s+)(\[[ xX]\]\s+)?(.*)$',
  );
  static final RegExp _quoteLine = RegExp(r'^(\s*(?:>\s?)+)(.*)$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final sel = newValue.selection;
    if (!sel.isValid || !sel.isCollapsed) return newValue;
    final caret = sel.baseOffset;
    if (caret < 1 ||
        newValue.text.length != oldValue.text.length + 1 ||
        newValue.text[caret - 1] != '\n') {
      return newValue;
    }
    if (newValue.text.replaceRange(caret - 1, caret, '') != oldValue.text) {
      return newValue;
    }

    final text = newValue.text;
    final prevStart = caret - 1 == 0
        ? 0
        : text.lastIndexOf('\n', caret - 2) + 1;
    final prevLine = text.substring(prevStart, caret - 1);
    final indentMatch = RegExp(r'^[ \t]*').firstMatch(prevLine)!;
    final indent = indentMatch.group(0)!;

    if (isCode) return _codeEnter(text, caret, prevLine, indent);

    final list = _listLine.firstMatch(prevLine);
    if (list != null) {
      final content = list.group(5)!;
      final marker = list.group(2)!;
      final box = list.group(4);
      if (content.trim().isEmpty) {
        // Empty item: end the list by removing the marker.
        final replaced = text.replaceRange(prevStart, caret, '');
        return TextEditingValue(
          text: replaced,
          selection: TextSelection.collapsed(offset: prevStart),
        );
      }
      var nextMarker = marker;
      final numbered = RegExp(r'^(\d+)([.)])$').firstMatch(marker);
      if (numbered != null) {
        nextMarker = '${int.parse(numbered.group(1)!) + 1}${numbered.group(2)}';
      }
      final insert =
          '${list.group(1)}$nextMarker${list.group(3)}${box != null ? '[ ] ' : ''}';
      return TextEditingValue(
        text: text.replaceRange(caret, caret, insert),
        selection: TextSelection.collapsed(offset: caret + insert.length),
      );
    }

    final quote = _quoteLine.firstMatch(prevLine);
    if (quote != null && quote.group(1)!.contains('>')) {
      if (quote.group(2)!.trim().isEmpty) {
        final replaced = text.replaceRange(prevStart, caret, '');
        return TextEditingValue(
          text: replaced,
          selection: TextSelection.collapsed(offset: prevStart),
        );
      }
      final insert = quote.group(1)!;
      return TextEditingValue(
        text: text.replaceRange(caret, caret, insert),
        selection: TextSelection.collapsed(offset: caret + insert.length),
      );
    }

    if (indent.isEmpty) return newValue;
    return TextEditingValue(
      text: text.replaceRange(caret, caret, indent),
      selection: TextSelection.collapsed(offset: caret + indent.length),
    );
  }

  TextEditingValue _codeEnter(
    String text,
    int caret,
    String prevLine,
    String indent,
  ) {
    final trimmed = prevLine.trimRight();
    final opens =
        trimmed.endsWith('{') ||
        trimmed.endsWith('(') ||
        trimmed.endsWith('[') ||
        trimmed.endsWith(':');
    final nextChar = caret < text.length ? text[caret] : '';
    final closes = nextChar == '}' || nextChar == ')' || nextChar == ']';

    final inner = opens ? '$indent$indentUnit' : indent;
    if (opens && closes && !trimmed.endsWith(':')) {
      final insert = '$inner\n$indent';
      return TextEditingValue(
        text: text.replaceRange(caret, caret, insert),
        selection: TextSelection.collapsed(offset: caret + inner.length),
      );
    }
    if (inner.isEmpty) {
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret),
      );
    }
    return TextEditingValue(
      text: text.replaceRange(caret, caret, inner),
      selection: TextSelection.collapsed(offset: caret + inner.length),
    );
  }
}
