import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/features/editor/preview/markdown_preview.dart';
import 'package:markbit/features/editor/preview/preview_contents.dart';
import 'package:markbit/domain/markdown_utils.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final name in ['Regular', 'SemiBold', 'Bold']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            await File('assets/fonts/Inter-$name.ttf').readAsBytes(),
          ),
        ),
      );
    }
    await loader.load();
  });
  Future<void> show(
    WidgetTester tester,
    String body, {
    double width = 1400,
    AutoScrollController? scroll,
    bool reduced = false,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.build(Palettes.dark),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              disableAnimations: reduced,
            ),
            child: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('preview-capture'),
                child: ColoredBox(
                  color: Palettes.dark.editorBg,
                  child: MarkdownPreview(
                    body: body,
                    scrollController: scroll,
                    resolveNoteId: (_) => null,
                    onOpenNote: (_) {},
                    onCreateNote: (_) {},
                    onRun: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });
  test('contents include setext headings and exclude nested fenced examples', () {
    final headings = extractHeadings(
      'Title\n=====\n\n````markdown\n```\n# Example\n```\n````\n\nSubtitle\n--------\n\n- item\n---',
    );
    expect(headings.map((h) => h.text), ['Title', 'Subtitle']);
    expect(headings.map((h) => h.line), [0, 9]);
  });
  testWidgets('equal resting marks fan out around hover and reset on exit', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final body = List.generate(
      7,
      (i) =>
          '## Section $i\n\n${List.filled(5, 'Sample paragraph text.').join(' ')}',
    ).join('\n\n');
    await show(tester, body);
    final marks = tester
        .widgetList<AnimatedContainer>(
          find.byWidgetPredicate(
            (w) =>
                w is AnimatedContainer &&
                w.key.toString().contains('preview-toc-mark'),
          ),
        )
        .toList();
    expect(marks.length, 7);
    expect(marks.map((m) => m.constraints!.maxWidth).toSet(), {12.0});
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1000, 10));
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('preview-toc-12'))),
    );
    await tester.pumpAndSettle();
    final hoverMarks = tester
        .widgetList<AnimatedContainer>(
          find.byWidgetPredicate(
            (w) =>
                w is AnimatedContainer &&
                w.key.toString().contains('preview-toc-mark'),
          ),
        )
        .toList();
    expect(hoverMarks[3].constraints!.maxWidth, 36);
    expect(hoverMarks[2].constraints!.maxWidth, 30);
    expect(hoverMarks[1].constraints!.maxWidth, 24);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        'build/preview-contents-hover.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await mouse.moveTo(const Offset(1000, 10));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<AnimatedContainer>(
            find.byWidgetPredicate(
              (w) =>
                  w is AnimatedContainer &&
                  w.key.toString().contains('preview-toc-mark'),
            ),
          )
          .map((m) => m.constraints!.maxWidth)
          .toSet(),
      {12.0},
    );
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'heading click reaches a distant section and tracks document scroll',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final scroll = AutoScrollController();
      final body = List.generate(
        25,
        (i) =>
            '## Chapter $i\n\n${List.filled(50 + i, 'Content for this section.').join(' ')}',
      ).join('\n\n');
      await show(tester, body, scroll: scroll);
      final extent = scroll.position.maxScrollExtent;
      for (final fraction in [.2, .8, .4]) {
        scroll.jumpTo(extent * fraction);
        await tester.pumpAndSettle();
        expect(scroll.position.maxScrollExtent, closeTo(extent, .01));
        expect(scroll.offset, closeTo(extent * fraction, .01));
      }
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      final renderedTitle = find.descendant(
        of: find.byType(SelectionArea),
        matching: find.text('Chapter 20'),
      );
      expect(
        tester.getTopLeft(renderedTitle.first).dy,
        greaterThan(tester.getSize(find.byType(MarkdownPreview)).height),
      );
      await tester.tap(find.byKey(const ValueKey('preview-toc-80')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(renderedTitle, findsWidgets);
      expect(
        tester.widget<PreviewContents>(find.byType(PreviewContents)).active,
        20,
      );
      expect(scroll.offset, greaterThan(1000));
      scroll.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PreviewContents>(find.byType(PreviewContents)).active,
        0,
      );
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'fenced headings excluded, edits refresh contents, narrow layouts stay clear',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await show(
        tester,
        '# Real\n\n```markdown\n# Example only\n```\n\n## Next',
      );
      expect(
        tester
            .widget<PreviewContents>(find.byType(PreviewContents))
            .headings
            .map((h) => h.text),
        ['Real', 'Next'],
      );
      await show(tester, '# Changed');
      expect(
        tester
            .widget<PreviewContents>(find.byType(PreviewContents))
            .headings
            .single
            .text,
        'Changed',
      );
      await show(tester, '# Changed', width: 650);
      expect(find.byType(PreviewContents), findsNothing);
      await show(tester, 'Plain text');
      expect(find.byType(PreviewContents), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reduced motion disables hover transitions', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await show(tester, '# Title', reduced: true);
    final mark = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('preview-toc-mark-0')),
    );
    expect(mark.duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });
}
