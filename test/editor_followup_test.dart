import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/domain/colored_text.dart';
import 'package:markbit/domain/languages.dart';
import 'package:markbit/domain/execution/execution.dart';
import 'package:markbit/domain/execution/local_executor.dart';
import 'package:markbit/features/editor/markdown_commands.dart';
import 'package:markbit/features/editor/syntax_controller.dart';
import 'package:markbit/features/editor/code_text_editor.dart';
import 'package:markbit/features/editor/format_toolbar.dart';
import 'package:markbit/features/editor/preview/markdown_preview.dart';
import 'package:markbit/data/pdf_export_service.dart';
import 'package:markbit/data/models/note.dart';

import 'support/toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'selected color persists, can change and reset; collapsed color accepts typing',
    () {
      final c = TextEditingController(text: 'Hello world')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      MarkdownCommands.textColor(c, 'DC2626');
      expect(c.text, '<span style="color: #DC2626;">Hello</span> world');
      MarkdownCommands.textColor(c, '2563EB');
      expect(c.text, '<span style="color: #2563EB;">Hello</span> world');
      MarkdownCommands.textColor(c, null);
      expect(c.text, 'Hello world');
      c.selection = const TextSelection.collapsed(offset: 11);
      MarkdownCommands.textColor(c, '16A34A');
      final offset = c.selection.extentOffset;
      c.value = TextEditingValue(
        text: c.text.replaceRange(offset, offset, ' typed'),
        selection: TextSelection.collapsed(offset: offset + 6),
      );
      expect(coloredTextPattern.firstMatch(c.text)![2], ' typed');
      c.dispose();
    },
  );
  test('colored Markdown retains inline formatting and color in PDF', () async {
    const text = '<span style="color: #DC2626;">**Red** text</span>';
    final nodes = md.Document(
      inlineSyntaxes: [ColoredTextSyntax()],
    ).parseInline(text);
    final color = nodes.whereType<md.Element>().single;
    expect(color.attributes['color'], 'DC2626');
    expect(color.children!.whereType<md.Element>().first.tag, 'strong');
    final bytes = await PdfExportService.generate(
      Note(
        id: 'color',
        title: 'Colored text',
        body: text,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    await Directory('build/verification').create(recursive: true);
    await File('build/verification/colored-text.pdf').writeAsBytes(bytes);
  });
  testWidgets('color chooser applies selection even when body loses focus', (
    tester,
  ) async {
    final c = TextEditingController(text: 'Red text');
    final focus = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: Scaffold(
          body: Column(
            children: [
              TextField(controller: c, focusNode: focus),
              FormatToolbar(controller: c, focusNode: focus, onChanged: (_) {}),
            ],
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await tapToolbarAction(tester, 'Text color');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('color-hex')), 'DC2626');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(c.text, '<span style="color: #DC2626;">Red</span> text');
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    focus.dispose();
  });
  testWidgets('preview displays chosen color without HTML source', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: Scaffold(
          body: MarkdownPreview(
            body: '<span style="color: #DC2626;">Red text</span>',
            resolveNoteId: (_) => null,
            onOpenNote: (_) {},
            onCreateNote: (_) {},
            onRun: (_, _) {},
          ),
        ),
      ),
    );
    final colored = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.textSpan?.toPlainText() == 'Red text' &&
          w.textSpan?.style?.color == const Color(0xFFDC2626),
    );
    expect(colored, findsOneWidget);
    expect(find.textContaining('<span'), findsNothing);
  });
  testWidgets('real monospace multiline alignment stays visible after scroll', (
    tester,
  ) async {
    final font = File(r'C:/Windows/Fonts/consola.ttf');
    if (font.existsSync()) {
      final data = font.readAsBytesSync();
      await (FontLoader(
        'Cascadia Code',
      )..addFont(Future.value(ByteData.sublistView(data)))).load();
    }
    final c = SyntaxController(
      text: List.generate(
        28,
        (i) => i == 24
            ? "Search understands operators: `tag:work`, `status:active`, `lang:python`, `has:code`."
            : 'Line ${i + 1}',
      ).join('\n'),
      palette: Palettes.light,
    );
    final focus = FocusNode();
    final scroll = ScrollController();
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 760,
              height: 240,
              child: RepaintBoundary(
                key: key,
                child: CodeTextEditor(
                  controller: c,
                  focusNode: focus,
                  scrollController: scroll,
                  metrics: EditorMetrics(),
                  fontSize: 14,
                  showLineNumbers: true,
                  isCode: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    scroll.jumpTo(480);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      await Directory('build/verification').create(recursive: true);
      await File(
        'build/verification/editor-alignment.png',
      ).writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    focus.dispose();
    scroll.dispose();
  });
  test(
    'installed Kotlin compiles a class and executes main locally',
    skip: 'Kotlin verification excluded by user',
    () async {
      final local = LocalExecutor();
      final language = Languages.find('kotlin')!;
      if (await local.detect(language) == null) {
        fail('Installed Kotlin compiler was not discovered');
      }
      final classEvents = await local
          .execute(
            ExecutionRequest(
              language: language,
              code: 'class Example(val value: Int)',
              timeout: const Duration(seconds: 45),
            ),
          )
          .toList();
      final classResult = classEvents.whereType<RunFinished>().single;
      expect(
        classResult.success,
        isTrue,
        reason: classEvents.whereType<RunOutput>().map((e) => e.text).join(),
      );
      expect(classResult.compiledOnly, isTrue);
      final mainEvents = await local
          .execute(
            ExecutionRequest(
              language: language,
              code: 'fun main() { println("Local Kotlin OK") }',
              timeout: const Duration(seconds: 45),
            ),
          )
          .toList();
      expect(
        mainEvents.whereType<RunFinished>().single.success,
        isTrue,
        reason: mainEvents.whereType<RunOutput>().map((e) => e.text).join(),
      );
      expect(
        mainEvents.whereType<RunOutput>().map((e) => e.text).join(),
        contains('Local Kotlin OK'),
      );
      expect(mainEvents.whereType<RunFinished>().single.compiledOnly, isFalse);
    },
    timeout: const Timeout(Duration(seconds: 110)),
  );
}
