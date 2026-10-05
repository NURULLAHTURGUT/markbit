import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/widgets/app_notification.dart';
import 'package:markbit/features/dialogs/dialogs.dart';
import 'package:markbit/features/editor/format_toolbar.dart';
import 'package:markbit/features/editor/markdown_commands.dart';
import 'package:markbit/features/editor/preview/markdown_preview.dart';
import 'package:markbit/domain/colored_text.dart';
import 'package:markbit/data/pdf_export_service.dart';
import 'package:markbit/data/models/note.dart';

import 'support/toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('font size family and color compose and reset independently', () async {
    final c = TextEditingController(text: 'Hello world')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    MarkdownCommands.textColor(c, 'DC2626');
    MarkdownCommands.fontSize(c, 24);
    MarkdownCommands.fontFamily(c, 'Georgia');
    final match = styledTextPattern.firstMatch(c.text)!;
    expect(parseTextStyle(match[1]!), {
      'color': '#DC2626',
      'font-size': '24pt',
      'font-family': 'Georgia',
    });
    expect(match[2], 'Hello');
    MarkdownCommands.fontSize(c, null);
    expect(c.text, contains('font-family: Georgia'));
    expect(c.text, isNot(contains('font-size')));
    MarkdownCommands.fontFamily(c, null);
    MarkdownCommands.textColor(c, null);
    expect(c.text, 'Hello world');
    c.selection = const TextSelection.collapsed(offset: 11);
    MarkdownCommands.fontSize(c, 18);
    final offset = c.selection.start;
    c.text = c.text.replaceRange(offset, offset, ' New text');
    expect(styledTextPattern.firstMatch(c.text)![2], ' New text');
    c.dispose();
  });
  test('partial typography change retains neighboring text style', () {
    final c = TextEditingController(
      text: '<span style="color: #DC2626;">Hello world</span>',
    );
    final start = c.text.indexOf('world');
    c.selection = TextSelection(baseOffset: start, extentOffset: start + 5);
    MarkdownCommands.fontSize(c, 20);
    final spans = styledTextPattern.allMatches(c.text).toList();
    expect(spans.map((s) => s[2]), ['Hello ', 'world']);
    expect(parseTextStyle(spans.first[1]!), {'color': '#DC2626'});
    expect(parseTextStyle(spans.last[1]!), {
      'color': '#DC2626',
      'font-size': '20pt',
    });
    expect(parseTextStyle('font-family: Unknown;'), isNull);
    expect(parseTextStyle('font-size: 999pt;'), isNull);
    expect(parseTextStyle('background: url(script);'), isNull);
    c.dispose();
  });
  testWidgets(
    'font selections survive dialog focus loss and preview honors them',
    (tester) async {
      final c = TextEditingController(text: 'Hello world');
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Palettes.light),
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: c, focusNode: focus),
                FormatToolbar(
                  controller: c,
                  focusNode: focus,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tapToolbarAction(tester, 'Font size');
      await tester.pumpAndSettle();
      await tester.tap(find.text('24'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tapToolbarAction(tester, 'Font family');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Georgia'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        c.text,
        '<span style="font-size: 24pt; font-family: Georgia;">Hello</span> world',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Palettes.light),
          home: Scaffold(
            body: MarkdownPreview(
              body: c.text,
              resolveNoteId: (_) => null,
              onOpenNote: (_) {},
              onCreateNote: (_) {},
              onRun: (_, _) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rich = tester.widget<Text>(
        find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText() == 'Hello world',
        ),
      );
      final styles = <TextStyle>[];
      void collect(InlineSpan span, TextStyle inherited) {
        final style = inherited.merge(span.style);
        if (span is TextSpan) {
          if (span.text == 'Hello') styles.add(style);
          for (final child in span.children ?? <InlineSpan>[]) {
            collect(child, style);
          }
        }
      }

      collect(rich.textSpan!, const TextStyle());
      expect(styles.single.fontFamily, 'Georgia');
      expect(styles.single.fontSize, 32);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      focus.dispose();
    },
  );
  test('styled note remains exportable as PDF', () async {
    final bytes = await PdfExportService.generate(
      Note(
        id: 'type',
        title: 'Type',
        body: '<span style="font-size: 24pt; font-family: Inter;">Text</span>',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
  });
  testWidgets(
    'notifications animate at top queue auto dismiss and retain actions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      late BuildContext anchor;
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Palettes.light),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                anchor = context;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      showToast(anchor, 'Saved');
      showToast(
        anchor,
        'Retry save',
        actionLabel: 'Retry',
        onAction: () => retried = true,
      );
      await tester.pump();
      await tester.pumpAndSettle();
      final bounds = tester.getRect(
        find.byKey(const ValueKey('app-notification')),
      );
      expect(bounds.top, lessThan(50));
      expect(bounds.top, greaterThanOrEqualTo(14));
      expect(bounds.width, lessThanOrEqualTo(460));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Retry save'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      expect(find.text('Retry save'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retried, isTrue);
      expect(find.byKey(const ValueKey('app-notification')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('notification card fits a small glass window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late BuildContext anchor;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.glassDark),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              anchor = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    AppNotifications.show(
      anchor,
      'Long message about an operation that could not be completed. Retry this operation.',
      kind: NoticeKind.error,
      actionLabel: 'Retry',
      onAction: () {},
    );
    await tester.pump();
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('app-notification')));
    expect(rect.left, greaterThanOrEqualTo(16));
    expect(rect.right, lessThanOrEqualTo(284));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Dismiss notification'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-notification')), findsNothing);
  });
}
