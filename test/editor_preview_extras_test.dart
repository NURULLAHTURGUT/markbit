import 'package:markbit/application/shortcuts.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/domain/markdown_extras.dart';
import 'package:markbit/domain/mermaid.dart';
import 'package:markbit/domain/template_variables.dart';
import 'package:markbit/domain/text_diff.dart';
import 'package:markbit/features/editor/preview/markdown_extras_view.dart';
import 'package:markbit/features/editor/preview/markdown_preview.dart';
import 'package:markbit/features/editor/preview/mermaid_view.dart';
import 'package:markbit/features/editor/code_text_editor.dart';
import 'package:markbit/features/editor/syntax_controller.dart';
import 'package:markbit/features/editor/table_commands.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingController _at(String text, int offset) =>
    TextEditingController(text: text)
      ..selection = TextSelection.collapsed(offset: offset);

void main() {
  group('math and footnotes', () {
    test(r'$$ blocks become math fences; line numbers are kept', () {
      const body = 'Intro\n\$\$\nE = mc^2\n\$\$\nAfter';
      final prepared = prepareMarkdown(body);
      expect(prepared.body.split('\n'), hasLength(5));
      expect(prepared.body, contains('```math\nE = mc^2\n```'));
    });

    test('footnotes are numbered by first reference and removed', () {
      const body =
          'One[^b] and two[^a].\n\n[^a]: First def\n[^b]: Second def\n  continued';
      final prepared = prepareMarkdown(body);
      expect(prepared.body.split('\n'), hasLength(5));
      expect(prepared.body, isNot(contains('First def')));
      expect(prepared.footnotes.map((f) => f.label), ['b', 'a']);
      expect(prepared.footnotes.first.text, 'Second def\ncontinued');
      expect(prepared.footnotes.first.refLine, 0);
    });

    test('code fences are left alone', () {
      const body = '```\n\$\$\n[^x]: not a note\n```';
      final prepared = prepareMarkdown(body);
      expect(prepared.body, body);
      expect(prepared.footnotes, isEmpty);
    });

    test('inline math does not catch prices', () {
      String? tex(String s) {
        final m = inlineMath.firstMatch(s);
        return m == null ? null : (m[1] ?? m[2]);
      }

      expect(tex(r'area is $\pi r^2$ here'), r'\pi r^2');
      expect(tex(r'$$x+1$$'), 'x+1');
      expect(tex(r'costs $5 and $10'), isNull);
      expect(tex(r'escaped \$x$'), isNull);
    });
  });

  group('mermaid', () {
    test('flowchart nodes, shapes and edges', () {
      final d =
          MermaidDiagram.parse('''
flowchart LR
  A[Start] --> B{Ready?}
  B -->|yes| C((Done))
  B -- no --> D[Wait]
  D -.-> B
  C & D --- E[(Store)]
''')
              as Flowchart;
      expect(d.horizontal, isTrue);
      expect(d.nodes.map((n) => n.id), ['A', 'B', 'C', 'D', 'E']);
      expect(d.nodes[1].shape, FlowShape.diamond);
      expect(d.nodes[2].shape, FlowShape.circle);
      expect(d.nodes[4].shape, FlowShape.database);
      expect(d.edges, hasLength(6));
      expect(d.edges[1].label, 'yes');
      expect(d.edges[2].label, 'no');
      expect(d.edges[3].line, FlowLine.dotted);
      expect(d.edges[4].arrow, isFalse);
    });

    test('sequence diagram', () {
      final d =
          MermaidDiagram.parse('''
sequenceDiagram
  autonumber
  participant A as Alice
  actor B as Bob
  A->>B: Hello
  B-->>A: Hi
  Note over A,B: Greeting
  loop Every minute
    A-)B: Ping
  end
''')
              as SequenceDiagram;
      expect(d.participants.map((p) => p.label), ['Alice', 'Bob']);
      expect(d.participants[1].actor, isTrue);
      final messages = d.items.whereType<SeqMessage>().toList();
      expect(messages, hasLength(3));
      expect(messages[1].dashed, isTrue);
      expect(messages[2].arrow, SeqArrow.async);
      expect(messages[2].number, 3);
      expect(d.items.whereType<SeqNote>().single.participants, ['A', 'B']);
      expect(d.items.whereType<SeqBlockStart>().single.label, 'Every minute');
    });

    test('unsupported diagrams stay source', () {
      expect(MermaidDiagram.parse('gantt\n  title X'), isNull);
    });
  });

  group('tables', () {
    const table = '| A | B |\n| --- | :-: |\n| 1 | 2 |';

    test('finds the cell at the caret and formats', () {
      final t = MarkdownTable.at(table, table.indexOf('2'))!;
      expect((t.row, t.column), (1, 1));
      expect(t.aligns, [TableAlign.none, TableAlign.center]);
      expect(t.format(), '| A   |  B  |\n| --- | :-: |\n| 1   |  2  |');
      expect(MarkdownTable.at('just text', 2), isNull);
    });

    test('rows and columns', () {
      final c = _at(table, table.indexOf('1'));
      TableCommands.apply(c, TableOp.rowBelow);
      expect(c.text.split('\n'), hasLength(4));
      TableCommands.apply(c, TableOp.columnRight);
      expect(MarkdownTable.at(c.text, c.selection.baseOffset)!.columns, 3);
      TableCommands.apply(c, TableOp.alignRight);
      expect(c.text, contains('--:'));
      TableCommands.apply(c, TableOp.deleteColumn);
      TableCommands.apply(c, TableOp.deleteRow);
      expect(MarkdownTable.at(c.text, 0)!.rows, hasLength(2));
    });

    test('Tab moves between cells and adds a row at the end', () {
      final c = _at(table, table.indexOf('1'));
      expect(TableCommands.moveCell(c), isTrue);
      var t = MarkdownTable.at(c.text, c.selection.baseOffset)!;
      expect((t.row, t.column), (1, 1));
      TableCommands.moveCell(c);
      t = MarkdownTable.at(c.text, c.selection.baseOffset)!;
      expect((t.row, t.column), (2, 0));
      expect(t.rows, hasLength(3));
      TableCommands.moveCell(c, backwards: true);
      t = MarkdownTable.at(c.text, c.selection.baseOffset)!;
      expect((t.row, t.column), (1, 1));
      expect(TableCommands.moveCell(_at('no table', 0)), isFalse);
    });

    test('new table', () {
      final created = TableCommands.create(2, 3);
      expect(created.split('\n'), hasLength(4));
      expect(created, startsWith('| Column 1 |'));
    });
  });

  group('templates', () {
    test('variables and cursor', () {
      final ctx = TemplateContext(
        now: DateTime(2026, 10, 5, 9, 7),
        title: 'Standup',
        notebook: 'Work',
        language: 'tr',
      );
      final out = expandTemplate(
        '# {{title}} {{date}}\n{{weekday}}, {{day}} {{month}} {{year}} '
        '(W{{week}}) {{notebook}} {{time}} {{unknown}}\n- {{cursor}}',
        ctx,
      );
      expect(
        out.text,
        '# Standup 2026-10-05\nPazartesi, 5 Ekim 2026 (W41) Work 09:07 '
        '{{unknown}}\n- ',
      );
      expect(out.cursor, out.text.length);
      expect(expandTemplate('{{yesterday}}', ctx).text, '2026-10-04');
      expect(expandTemplate('{{date:dd.MM.yyyy}}', ctx).text, '05.10.2026');
      expect(isoWeek(DateTime(2027, 1, 1)), 53);
    });
  });

  group('diff', () {
    test('line changes', () {
      final d = TextDiff.of('a\nb\nc\nd', 'a\nB\nc\nd\ne');
      expect(d.added, 2);
      expect(d.removed, 1);
      expect(d.lines.map((l) => '${l.kind.name[0]}${l.text}'), [
        'sa',
        'rb',
        'aB',
        'sc',
        'sd',
        'ae',
      ]);
      expect(TextDiff.of('same', 'same').isEmpty, isTrue);
      expect(changedSpan('hello world', 'hello there'), (6, 11));
    });
  });

  group('shortcuts', () {
    test('combos round-trip and read nicely', () {
      const combo = KeyCombo(
        LogicalKeyboardKey.keyK,
        control: true,
        shift: true,
      );
      expect(KeyCombo.parse(combo.serialize()), combo);
      expect(combo.label, 'Ctrl+Shift+K');
      expect(KeyCombo.parse('nonsense'), isNull);
      expect(AppShortcut.bold.editorOnly, isTrue);
      expect(AppShortcut.newNote.editorOnly, isFalse);
    });
  });

  testWidgets('rebound editor shortcut and Tab in tables', (tester) async {
    final c = SyntaxController(text: 'make bold', palette: Palettes.light);
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(() {
      c.dispose();
      focus.dispose();
      scroll.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: Scaffold(
          body: CodeTextEditor(
            controller: c,
            focusNode: focus,
            scrollController: scroll,
            metrics: EditorMetrics(),
            fontSize: 14,
            showLineNumbers: false,
            isCode: false,
            markdownSuggestions: false,
            shortcuts: {
              AppShortcut.bold: const KeyCombo(
                LogicalKeyboardKey.keyB,
                control: true,
                shift: true,
              ),
            },
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    c.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
    // The old Ctrl+B no longer formats.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.text, 'make bold');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(c.text, 'make **bold**');

    c.value = const TextEditingValue(
      text: '| A | B |\n| - | - |\n| 1 | 2 |',
      selection: TextSelection.collapsed(offset: 23),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    final t = MarkdownTable.at(c.text, c.selection.baseOffset)!;
    expect((t.row, t.column), (1, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview renders math, footnotes and Mermaid', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const body = '''
# Notes

Energy is \$E = mc^2\$ and a sum[^1].

\$\$
\\sum_{i=1}^n i = \\frac{n(n+1)}{2}
\$\$

```mermaid
flowchart TD
  A[Start] --> B{Check}
  B -->|ok| C[End]
```

```mermaid
sequenceDiagram
  Alice->>Bob: Hello
```

[^1]: Gauss knew it.
''';
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: Scaffold(
          body: MarkdownPreview(
            body: body,
            resolveNoteId: (_) => null,
            onOpenNote: (_) {},
            onCreateNote: (_) {},
            onRun: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsNWidgets(2));
    expect(find.byType(MathBlockView), findsOneWidget);
    expect(find.byType(MermaidView), findsNWidgets(2));
    expect(find.byType(FootnotesSection), findsOneWidget);
    expect(find.text('Gauss knew it.'), findsOneWidget);
    expect(find.textContaining('[^1]'), findsNothing);
  });
}
