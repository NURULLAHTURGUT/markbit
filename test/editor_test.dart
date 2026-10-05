import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/features/editor/highlight/highlighter.dart';
import 'package:markbit/features/editor/markdown_commands.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

TextEditingController _c(String text, int start, [int? end]) =>
    TextEditingController.fromValue(
      TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
      ),
    );

void main() {
  group('highlighter', () {
    test('python tokens', () {
      const code = 'def f(x):\n    return "s" # c\n';
      final tokens = tokenizeCode(code, 'python');
      String of(Tok t) => tokens
          .where((k) => k.tok == t)
          .map((k) => code.substring(k.start, k.end))
          .join('|');
      expect(of(Tok.keyword), 'def|return');
      expect(of(Tok.string), '"s"');
      expect(of(Tok.comment), '# c');
      expect(of(Tok.function), 'f');
    });

    test('span text equals source for every language', () {
      const code = 'const a = `x`; // hi\nfn main() { "s" 12 }\n/* c */';
      for (final lang in [
        'python',
        'javascript',
        'rust',
        'c',
        'go',
        'sql',
        'json',
        'html',
        'css',
        'bash',
        'unknown',
      ]) {
        final tokens = tokenizeCode(code, lang);
        final span = buildHighlightedSpan(
          code,
          tokens,
          const TextStyle(),
          Palettes.dark,
        );
        expect(span.toPlainText(), code, reason: lang);
      }
    });

    test('markdown highlights headings and fenced code', () {
      const md = '# H\n\n```python\nprint(1)\n```\n';
      final tokens = tokenizeMarkdown(md);
      expect(tokens.any((t) => t.tok == Tok.heading), isTrue);
      expect(
        tokens.any(
          (t) =>
              t.tok == Tok.function && md.substring(t.start, t.end) == 'print',
        ),
        isTrue,
      );
      final span = buildHighlightedSpan(
        md,
        tokens,
        const TextStyle(),
        Palettes.light,
      );
      expect(span.toPlainText(), md);
    });
  });

  group('markdown commands', () {
    test('bold wraps and unwraps', () {
      final c = _c('hello world', 0, 5);
      MarkdownCommands.bold(c);
      expect(c.text, '**hello** world');
      MarkdownCommands.bold(c);
      expect(c.text, 'hello world');
    });

    test('empty selection inserts placeholder', () {
      final c = _c('', 0);
      MarkdownCommands.inlineCode(c);
      expect(c.text, '`code`');
    });

    test('toggle task cycles', () {
      final c = _c('item', 0);
      MarkdownCommands.toggleTask(c);
      expect(c.text, '- [ ] item');
      MarkdownCommands.toggleTask(c);
      expect(c.text, '- [x] item');
    });

    test('heading cycles H1-H3-none', () {
      final c = _c('Title', 2);
      MarkdownCommands.cycleHeading(c);
      expect(c.text, '# Title');
      MarkdownCommands.cycleHeading(c);
      expect(c.text, '## Title');
      MarkdownCommands.cycleHeading(c);
      expect(c.text, '### Title');
      MarkdownCommands.cycleHeading(c);
      expect(c.text, 'Title');
    });

    test('indent and outdent multiple lines', () {
      final c = _c('a\nb', 0, 3);
      MarkdownCommands.indent(c);
      expect(c.text, '  a\n  b');
      MarkdownCommands.indent(c, outdent: true);
      expect(c.text, 'a\nb');
    });
  });

  group('smart enter', () {
    TextEditingValue enter(SmartEnterFormatter f, String before, String after) {
      final old = TextEditingValue(
        text: '$before$after',
        selection: TextSelection.collapsed(offset: before.length),
      );
      final next = TextEditingValue(
        text: '$before\n$after',
        selection: TextSelection.collapsed(offset: before.length + 1),
      );
      return f.formatEditUpdate(old, next);
    }

    test('continues bullet and numbered lists', () {
      final f = SmartEnterFormatter(isCode: false);
      expect(enter(f, '- one', '').text, '- one\n- ');
      expect(enter(f, '3. three', '').text, '3. three\n4. ');
      expect(enter(f, '- [x] done', '').text, '- [x] done\n- [ ] ');
    });

    test('empty list item ends the list', () {
      final f = SmartEnterFormatter(isCode: false);
      expect(enter(f, 'a\n- ', '').text, 'a\n');
    });

    test('code keeps and extends indentation', () {
      final f = SmartEnterFormatter(isCode: true, indentUnit: '    ');
      expect(enter(f, '    x = 1', '').text, '    x = 1\n    ');
      expect(enter(f, 'if (a) {', '').text, 'if (a) {\n    ');
      final r = enter(f, 'f() {', '}');
      expect(r.text, 'f() {\n    \n}');
      expect(r.selection.baseOffset, 'f() {\n    '.length);
    });
  });
}
