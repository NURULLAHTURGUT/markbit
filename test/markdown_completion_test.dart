import 'package:markbit/core/l10n/app_strings.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/data/models/app_settings.dart';
import 'package:markbit/domain/colored_text.dart';
import 'package:markbit/features/editor/code_text_editor.dart';
import 'package:markbit/features/editor/markdown_completion.dart';
import 'package:markbit/features/editor/preview/markdown_preview.dart';
import 'package:markbit/features/editor/syntax_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TextEditingValue value(String text, {int? offset}) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: offset ?? text.length),
);

Future<(TextEditingController, FocusNode, ScrollController)> editor(
  WidgetTester tester,
  String text, {
  bool enabled = true,
  bool code = false,
  bool readOnly = false,
  bool numbers = true,
  bool preview = false,
  AppPalette palette = Palettes.light,
}) async {
  final c = SyntaxController(palette: palette)..value = value(text);
  final focus = FocusNode(), scroll = ScrollController();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(palette).copyWith(platform: TargetPlatform.windows),
      home: Scaffold(
        body: SizedBox(
          width: preview ? 680 : 340,
          child: Row(
            children: [
              Expanded(
                child: CodeTextEditor(
                  controller: c,
                  focusNode: focus,
                  scrollController: scroll,
                  metrics: EditorMetrics(),
                  fontSize: 14,
                  showLineNumbers: numbers,
                  isCode: code,
                  readOnly: readOnly,
                  markdownSuggestions: enabled,
                  completionNoteTitles: () => ['Project plan', 'Project notes'],
                ),
              ),
              if (preview)
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: c,
                    builder: (context, value, _) => MarkdownPreview(
                      body: value.text,
                      resolveNoteId: (_) => null,
                      onOpenNote: (_) {},
                      onCreateNote: (_) {},
                      onRun: (_, _) {},
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  focus.requestFocus();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    focus.dispose();
    scroll.dispose();
  });
  return (c, focus, scroll);
}

void main() {
  setUp(() => AppStrings.current = AppStrings(const Locale('en')));

  test(
    'templates produce only supported spans and preserve the typed prefix',
    () {
      final engine = MarkdownCompletionEngine();
      for (final prefix in [
        '<spa',
        '<span style="font-si',
        '<span style="font-fa',
        '<span style="color: #123456;',
      ]) {
        final options = engine.suggest(value('Before $prefix'));
        expect(options, isNotEmpty);
        for (final option in options) {
          expect(option.range.start, 7);
          expect(option.insertText, '$prefix${option.suffix}');
          final match = styledTextPattern.firstMatch(option.insertText)!;
          expect(parseTextStyle(match[1]!), isNotNull);
          for (final stop in option.stops) {
            expect(stop.start, greaterThanOrEqualTo(0));
            expect(stop.end, lessThanOrEqualTo(option.insertText.length));
          }
        }
      }
      expect(engine.suggest(value('<span style="background:')), isEmpty);
      expect(engine.suggest(value('\\<spa')), isEmpty);
      expect(engine.suggest(value('- [')).single.insertText, '- [ ] Task');
      expect(
        engine.suggest(value('```py')).single.insertText,
        '```python\n\n```',
      );
      expect(
        engine
            .suggest(value('```py\nprint(1)\n```', offset: 5))
            .single
            .insertText,
        '```python',
      );
    },
  );

  test(
    'fence context survives edits above the caret and suppresses literal code and IME',
    () {
      final engine = MarkdownCompletionEngine();
      for (final source in [
        '```html\n<spa',
        '~~~html\n<spa',
        '    <spa',
        '`example <spa',
        '``example <spa',
      ]) {
        expect(engine.suggest(value(source)), isEmpty, reason: source);
      }
      expect(engine.suggest(value('```html\nX\n```\n<spa')), isNotEmpty);
      expect(engine.suggest(value('```html\nX\n\n<spa')), isEmpty);
      expect(engine.suggest(value('plain\nX\n\n<spa')), isNotEmpty);
      expect(engine.suggest(value('<spa tail', offset: 4)), isEmpty);
      expect(
        engine.suggest(
          value('<spa').copyWith(
            selection: const TextSelection(baseOffset: 0, extentOffset: 4),
          ),
        ),
        isEmpty,
      );
      expect(
        engine.suggest(
          value('<spa').copyWith(composing: const TextRange(start: 0, end: 4)),
        ),
        isEmpty,
      );
      final long =
          '${List.filled(6000, 'ordinary text').join('\n')}\n```html\n<spa';
      expect(engine.suggest(value(long)), isEmpty);
      expect(
        engine.suggest(value(long.replaceFirst('```html', 'ordinary'))),
        isNotEmpty,
      );
    },
  );

  test(
    'references use available notes and embedded images, and labels localize',
    () {
      final engine = MarkdownCompletionEngine();
      final notes = engine.suggest(
        value('Read [[pro'),
        noteTitles: () => [
          'Project plan',
          'Other',
          'Project plan',
          'Bad]title',
        ],
      );
      expect(notes.map((n) => n.insertText), ['[[Project plan]]']);
      expect(
        engine
            .suggest(value('[[«pro'), noteTitles: () => ['«project»'])
            .single
            .insertText,
        '[[«project»]]',
      );
      final images = engine.suggest(
        value('![Photo](attachment:'),
        imageUris: () => ['attachment:abc-123'],
      );
      expect(images.single.insertText, '![Photo](attachment:abc-123)');
      expect(
        engine
            .suggest(value('- ['), translate: (s) => s == 'Task' ? 'Görev' : s)
            .single
            .insertText,
        '- [ ] Görev',
      );
      expect(AppSettings.fromJson({}).markdownSuggestions, isTrue);
      expect(
        AppSettings.fromJson(
          const AppSettings().copyWith(markdownSuggestions: false).toJson(),
        ).markdownSuggestions,
        isFalse,
      );
    },
  );

  testWidgets(
    'ghost stays outside document, aligns with caret and Tab navigates editable placeholders',
    (tester) async {
      final (c, focus, _) = await editor(tester, 'Before <spa');
      final ghost = find.byKey(const ValueKey('markdown-ghost-text'));
      expect(ghost, findsOneWidget);
      expect(c.text, 'Before <spa');
      final render = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      expect(render.text!.toPlainText(), c.text);
      final caret = render.localToGlobal(
        render.getLocalRectForCaret(c.selection.extent).topLeft,
      );
      expect(tester.getTopLeft(ghost).dy, closeTo(caret.dy, 0.5));
      expect(tester.getTopLeft(ghost).dx, closeTo(caret.dx + 2, 0.5));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(c.text, 'Before <span style="color: #2563EB;">Text</span>');
      expect(c.selection.textInside(c.text), '2563EB');
      final sel = c.selection;
      c.value = TextEditingValue(
        text: c.text.replaceRange(sel.start, sel.end, 'ABCDEF'),
        selection: TextSelection.collapsed(offset: sel.start + 6),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(c.selection.textInside(c.text), 'Text');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(c.selection.textInside(c.text), 'ABCDEF');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      final field = c.selection;
      c.value = TextEditingValue(
        text: c.text.replaceRange(field.start, field.end, 'Hello world'),
        selection: TextSelection.collapsed(offset: field.start + 11),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(c.selection.end, c.text.length);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Esc hides a suggestion until typing changes; Ctrl+Space chooses an alternative',
    (tester) async {
      final (c, _, _) = await editor(
        tester,
        '<spa',
        palette: Palettes.glassDark,
        numbers: false,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('markdown-ghost-text')), findsNothing);
      expect(c.text, '<spa');
      c.value = value('<span');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('markdown-ghost-text')), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Font size · 24 pt'));
      await tester.pumpAndSettle();
      expect(c.text, '<span style="font-size: 24pt;">Text</span>');
      expect(c.selection.textInside(c.text), '24');
      expect(tester.takeException(), isNull);
    },
  );

  for (final (prefix, field, replacement) in [
    ('<spa', '2563EB', 'ABCDEF'),
    ('<span style="font-si', '18', '24'),
    ('<span style="font-fa', 'Inter', 'Georgia'),
  ]) {
    testWidgets(
      'completed $field can be deleted and retyped with a live preview',
      (tester) async {
        final (c, focus, _) = await editor(tester, prefix, preview: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(c.selection.textInside(c.text), field);
        final accepted = c.text;
        final start = c.selection.start;

        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pumpAndSettle();
        expect(c.text, accepted.replaceFirst(field, ''));
        expect(c.selection, TextSelection.collapsed(offset: start));
        expect(tester.takeException(), isNull);

        // Model platform typing, including every temporarily invalid value.
        for (var i = 0; i < replacement.length; i++) {
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: c.text.replaceRange(start + i, start + i, replacement[i]),
              selection: TextSelection.collapsed(offset: start + i + 1),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final render = tester
              .state<EditableTextState>(find.byType(EditableText))
              .renderEditable;
          expect(render.text!.toPlainText(), c.text);
        }
        expect(c.text, accepted.replaceFirst(field, replacement));
        expect(
          parseTextStyle(styledTextPattern.firstMatch(c.text)![1]!),
          isNotNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        expect(c.selection.textInside(c.text), 'Text');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(c.selection.textInside(c.text), replacement);
        expect(focus.hasFocus, isTrue);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'wrapped and scrolled ghost stays in its viewport and stale suggestions are ignored',
    (tester) async {
      final source =
          '${List.filled(35, 'Long wrapped paragraph with several words.').join('\n')}\nBefore <spa';
      final (c, _, scroll) = await editor(
        tester,
        source,
        palette: Palettes.zenGlass,
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final ghost = find.byKey(const ValueKey('markdown-ghost-text'));
      expect(ghost, findsOneWidget);
      final rect = tester.getRect(ghost);
      final viewport = tester.getRect(find.byType(CodeTextEditor));
      expect(rect.left, greaterThanOrEqualTo(viewport.left));
      expect(rect.right, lessThanOrEqualTo(viewport.right));
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(ghost, findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(c.text, isNot(contains('<span')));
      c.value = value('<spa');
      await tester.pump(const Duration(milliseconds: 80));
      c.value = value('Ordinary prose');
      await tester.pump(const Duration(milliseconds: 250));
      expect(ghost, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accepted template can be undone without ghost becoming document text',
    (tester) async {
      final (c, _, _) = await editor(tester, '<spa');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 600));
      expect(c.text, startsWith('<span'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(c.text, '<spa');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'suggestions never intercept code, disabled or read-only editor input',
    (tester) async {
      for (final config in [
        (false, false, false),
        (true, true, false),
        (true, false, true),
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final (c, _, _) = await editor(
          tester,
          '<spa',
          enabled: config.$1,
          code: config.$2,
          readOnly: config.$3,
        );
        expect(find.byKey(const ValueKey('markdown-ghost-text')), findsNothing);
        if (!config.$3) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          expect(c.text, '<spa${config.$2 ? '    ' : '  '}');
        } else {
          expect(c.text, '<spa');
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}
