import 'package:flutter/services.dart';

import '../../domain/colored_text.dart';
import '../../domain/languages.dart';

/// A proposal stays separate from the document until the user accepts it.
class MarkdownCompletion {
  const MarkdownCompletion({
    required this.label,
    required this.range,
    required this.insertText,
    required this.suffix,
    required this.stops,
  });
  final String label, insertText, suffix;
  final TextRange range;
  final List<TextRange> stops;
}

/// Small local templates plus note/image references. No model or network.
class MarkdownCompletionEngine {
  final _context = _FenceIndex();
  static final _openingFence = RegExp(r'^( {0,3})(`{3,}|~{3,})([\w+-]*)$');
  static final _fields = RegExp('«([^»]*)»');

  List<MarkdownCompletion> suggest(
    TextEditingValue value, {
    Iterable<String> Function()? noteTitles,
    Iterable<String> Function()? imageUris,
    String Function(String)? translate,
  }) {
    final sel = value.selection;
    if (!sel.isValid ||
        !sel.isCollapsed ||
        sel.end > value.text.length ||
        (value.composing.isValid && !value.composing.isCollapsed)) {
      return [];
    }
    final text = value.text, at = sel.end;
    if (at < text.length && text[at] != '\n' && text[at] != '\r') return [];
    final start = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
    if (at - start > 4096) return [];
    final line = text.substring(start, at);
    if (line.isEmpty || line.startsWith('    ') || line.startsWith('\t')) {
      return [];
    }
    final tr = translate ?? (String s) => s;
    final proposals = <MarkdownCompletion>[];
    void add(
      String typed,
      String template,
      String label, {
      bool ignoreCase = false,
      bool literal = false,
    }) {
      final stops = <TextRange>[];
      final out = StringBuffer();
      var last = 0;
      for (final field
          in literal ? const <RegExpMatch>[] : _fields.allMatches(template)) {
        out.write(template.substring(last, field.start));
        final offset = out.length;
        out.write(field[1]);
        stops.add(TextRange(start: offset, end: out.length));
        last = field.end;
      }
      out.write(template.substring(last));
      final insertion = out.toString();
      if (typed.isEmpty ||
          typed.length >= insertion.length ||
          !(ignoreCase
              ? insertion.toLowerCase().startsWith(typed.toLowerCase())
              : insertion.startsWith(typed))) {
        return;
      }
      final replacementStart = at - typed.length;
      if (replacementStart > 0 && text[replacementStart - 1] == '\\') return;
      proposals.add(
        MarkdownCompletion(
          label: label,
          range: TextRange(start: replacementStart, end: at),
          insertText: insertion,
          suffix: insertion.substring(typed.length),
          stops: stops,
        ),
      );
    }

    // This also recognizes the opening line, without suggesting inside code.
    final fence = _openingFence.firstMatch(line);
    final tokenStart = line.lastIndexOf('<') >= 0
        ? line.lastIndexOf('<')
        : line.lastIndexOf('[[') >= 0
        ? line.lastIndexOf('[[')
        : line.lastIndexOf('![') >= 0
        ? line.lastIndexOf('![')
        : line.lastIndexOf('[');
    final structural =
        fence != null ||
        tokenStart >= 0 ||
        line.trimLeft().startsWith('|') ||
        RegExp(r'^\s*[-*+] \[').hasMatch(line) ||
        line.endsWith('**') ||
        line.endsWith('~~') ||
        line.trim() == '>';
    if (!structural || _context.before(text, start) != null) return [];
    if (fence != null) {
      final marker = fence[2]!, typed = '${fence[2]}${fence[3]}';
      final tail = text.substring(at, (at + 4096).clamp(at, text.length));
      for (final language in Languages.all) {
        add(
          typed,
          tail.trim().isEmpty
              ? '$marker${language.id}\n«»\n$marker'
              : '$marker${language.id}',
          language.name,
        );
        if (proposals.length >= 10) break;
      }
      return proposals;
    }
    if (tokenStart >= 0 && _insideInlineCode(line.substring(0, tokenStart))) {
      return [];
    }

    final task = RegExp(r'^\s*([-*+]) \[$').firstMatch(line);
    if (task != null) {
      add(
        '${task[1]} [',
        '${task[1]} [ ] «${tr('Task')}»',
        tr('Task list (toggle)'),
      );
      return proposals;
    }

    final htmlStart = line.lastIndexOf('<');
    if (htmlStart >= 0) {
      final typed = line.substring(htmlStart);
      if (typed.startsWith('</')) {
        add(typed, '</span>', 'span');
      } else {
        for (final color in ['2563EB', 'DC2626', '16A34A']) {
          add(
            typed,
            '<span style="color: #«$color»;">«${tr('Text')}»</span>',
            '${tr('Text color')} · #$color',
          );
        }
        for (final size in [18, 24, 14]) {
          add(
            typed,
            '<span style="font-size: «$size»pt;">«${tr('Text')}»</span>',
            '${tr('Font size')} · $size pt',
          );
        }
        for (final family in textFontFamilies) {
          add(
            typed,
            '<span style="font-family: «$family»;">«${tr('Text')}»</span>',
            '${tr('Font family')} · $family',
          );
        }
        // Retain a valid value the user already typed, rather than replacing it.
        final custom = RegExp(
          r'^<span style="(color:\s*#[\da-fA-F]{6};?|font-size:\s*(?:[89]|[1-3]\d|4[0-8])pt;?)$',
        ).firstMatch(typed);
        if (custom != null) {
          add(
            typed,
            '$typed${typed.endsWith(';') ? '' : ';'}">«${tr('Text')}»</span>',
            tr('Text'),
          );
        }
      }
      if (proposals.isNotEmpty) return proposals.take(10).toList();
    }

    final wiki = line.lastIndexOf('[[');
    if (wiki >= 0 && !line.substring(wiki).contains(']]')) {
      final typed = line.substring(wiki);
      final seen = <String>{};
      for (final title in noteTitles?.call() ?? const <String>[]) {
        if (title.contains(RegExp(r'[\[\]\r\n]')) || !seen.add(title)) continue;
        add(typed, '[[$title]]', title, ignoreCase: true, literal: true);
        if (proposals.length >= 10) break;
      }
      return proposals;
    }
    final image = line.lastIndexOf('![');
    final link = line.lastIndexOf('[');
    if (image >= 0) {
      final typed = line.substring(image);
      add(
        typed,
        '![«${tr('Image')}»](«https://example.com/image.png»)',
        tr('Insert image'),
      );
      final path = RegExp(r'^!\[([^\]]*)\]\(([^)]*)$').firstMatch(typed);
      if (path != null) {
        for (final uri in imageUris?.call() ?? const <String>[]) {
          add(typed, '![${path[1]}]($uri)', uri);
          if (proposals.length >= 10) break;
        }
        add(
          typed,
          '![${path[1]}](«https://example.com/image.png»)',
          tr('Insert image'),
        );
      }
    } else if (link >= 0) {
      final typed = line.substring(link);
      add(typed, '[«${tr('Text')}»](«https://example.com»)', tr('Link'));
      final path = RegExp(r'^\[([^\]]*)\]\(([^)]*)$').firstMatch(typed);
      if (path != null) {
        add(typed, '[${path[1]}](«https://example.com»)', tr('Link'));
      }
    }
    if (line.trim() == '|') {
      add(
        '|',
        '| «${tr('Column 1')}» | «${tr('Column 2')}» |\n| --- | --- |\n| «${tr('Value')}» | «${tr('Value')}» |',
        tr('Table'),
      );
    }
    if (line.endsWith('**') &&
        !_insideInlineCode(line.substring(0, line.length - 2))) {
      add('**', '**«${tr('Text')}»**', tr('Bold'));
    }
    if (line.endsWith('~~') &&
        !_insideInlineCode(line.substring(0, line.length - 2))) {
      add('~~', '~~«${tr('Text')}»~~', tr('Strikethrough'));
    }
    if (line.trim() == '>') add('>', '> «${tr('Quote')}»', tr('Quote'));
    return proposals.take(10).toList();
  }

  bool _insideInlineCode(String prefix) {
    var open = 0;
    for (final run in RegExp(r'`+').allMatches(prefix)) {
      if (run.start > 0 && prefix[run.start - 1] == '\\') continue;
      if (open == 0) {
        open = run.end - run.start;
      } else if (open == run.end - run.start) {
        open = 0;
      }
    }
    return open != 0;
  }
}

/// Cache fence context at line boundaries; edit only invalidates its suffix.
class _FenceIndex {
  String _source = '';
  final _points = <(int, String?)>[(0, null)];
  static final _marker = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$');
  String? before(String text, int target) {
    if (text != _source) {
      var changed = 0;
      final end = [
        text.length,
        _source.length,
        _points.last.$1,
      ].reduce((a, b) => a < b ? a : b);
      while (changed < end &&
          text.codeUnitAt(changed) == _source.codeUnitAt(changed)) {
        changed++;
      }
      final line = changed == 0 ? 0 : text.lastIndexOf('\n', changed - 1) + 1;
      while (_points.length > 1 && _points.last.$1 > line) {
        _points.removeLast();
      }
      _source = text;
    }
    var index = _points.length - 1;
    while (index > 0 && _points[index].$1 > target) {
      index--;
    }
    var offset = _points[index].$1, state = _points[index].$2;
    while (offset < target) {
      final end = text.indexOf('\n', offset);
      if (end < 0) break;
      final marker = _marker.firstMatch(text.substring(offset, end));
      if (marker != null) {
        final run = marker[1]!, rest = marker[2]!.trim();
        if (state == null && !(run[0] == '`' && rest.contains('`'))) {
          state = run;
        } else if (state != null &&
            run[0] == state[0] &&
            run.length >= state.length &&
            rest.isEmpty) {
          state = null;
        }
      }
      offset = end + 1;
      index++;
      if (index >= _points.length) _points.add((offset, state));
    }
    return state;
  }
}

/// Placeholder navigation survives typing inside the active field.
class MarkdownSnippetSession {
  MarkdownSnippetSession(this.ranges, this.end);
  List<TextRange> ranges;
  int end, index = 0;
  TextSelection get selection => TextSelection(
    baseOffset: ranges[index].start,
    extentOffset: ranges[index].end,
  );
  bool update(TextEditingValue previous, TextEditingValue next) {
    final range = ranges[index];
    if (previous.text != next.text) {
      final delta = next.text.length - previous.text.length;
      final newEnd = range.end + delta;
      if (newEnd < range.start ||
          newEnd > next.text.length ||
          !previous.selection.isValid ||
          previous.selection.start < range.start ||
          previous.selection.end > range.end ||
          previous.text.substring(0, range.start) !=
              next.text.substring(0, range.start) ||
          previous.text.substring(range.end) != next.text.substring(newEnd)) {
        return false;
      }
      ranges = [
        for (var i = 0; i < ranges.length; i++)
          i < index
              ? ranges[i]
              : i == index
              ? TextRange(start: range.start, end: newEnd)
              : TextRange(
                  start: ranges[i].start + delta,
                  end: ranges[i].end + delta,
                ),
      ];
      end += delta;
    }
    return next.selection.isValid &&
        next.selection.start >= ranges[index].start &&
        next.selection.end <= ranges[index].end;
  }
}
