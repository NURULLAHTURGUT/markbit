import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:markbit/application/runner_notifier.dart';
import 'package:markbit/core/l10n/app_strings.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/data/pdf_export_service.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/models/app_settings.dart';
import 'package:markbit/domain/visual_block.dart';
import 'package:markbit/domain/languages.dart';
import 'package:markbit/domain/execution/execution.dart';
import 'package:markbit/domain/execution/remote_executor.dart';
import 'package:markbit/features/editor/code_text_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppStrings.current = AppStrings(const Locale('en')));
  test('no remote execution service is configured by default', () async {
    expect(const AppSettings().remoteEndpoint, isEmpty);
    // An empty endpoint never offers to run code remotely.
    final remote = RemoteExecutor(endpoint: const AppSettings().remoteEndpoint);
    expect(await remote.supports(Languages.find('python')!), isFalse);
  });
  Future<List<RunEvent>> remote(
    int status,
    Object payload, {
    bool raw = false,
  }) =>
      RemoteExecutor(
            endpoint: 'https://example.test/piston',
            client: MockClient(
              (_) async => http.Response(
                raw ? payload.toString() : jsonEncode(payload),
                status,
              ),
            ),
          )
          .execute(
            ExecutionRequest(
              language: Languages.find('java')!,
              code: 'class Main {}',
            ),
          )
          .toList();

  test('service rejection never claims the class ran without output', () async {
    final events = await remote(403, {
      'message': 'Public Piston API is now whitelist only',
    });
    expect(
      events.whereType<RunOutput>().single.text,
      contains('Your code was not executed'),
    );
    final result = events.whereType<RunFinished>().single;
    expect(result.success, isFalse);
    expect(executionSummary(result, ''), isNull);
  });
  test('plain HTTP failures get actionable distinct messages', () async {
    for (final entry in [
      (401, 'API key'),
      (429, 'request limit'),
      (503, 'temporarily unavailable'),
      (404, 'address was not found'),
    ]) {
      final events = await remote(entry.$1, 'Not JSON', raw: true);
      expect(events.whereType<RunOutput>().single.text, contains(entry.$2));
      expect(events.whereType<RunFinished>().single.success, isFalse);
    }
  });
  test('compiled program errors and empty success remain different', () async {
    final failed = await remote(200, {
      'compile': {'code': 1, 'stderr': 'Main method not found'},
    });
    expect(failed.whereType<RunFinished>().single.exitCode, 1);
    expect(
      executionSummary(
        failed.whereType<RunFinished>().single,
        'Main method not found',
      ),
      contains('entry point'),
    );
    final syntax = await remote(200, {
      'compile': {'code': 1, 'stderr': 'syntax error'},
    });
    final compilerOutput = syntax
        .whereType<RunOutput>()
        .map((e) => e.text)
        .join();
    expect(
      executionSummary(syntax.whereType<RunFinished>().single, compilerOutput),
      contains('exit code 1'),
    );
    final success = await remote(200, {
      'run': {'code': 0, 'stdout': '', 'stderr': ''},
    });
    expect(success.whereType<RunFinished>().single.success, isTrue);
    expect(
      executionSummary(success.whereType<RunFinished>().single, ''),
      contains('without console output'),
    );
    final missing = await remote(200, {
      'compile': {'code': 0},
    });
    expect(missing.whereType<RunFinished>().single.success, isFalse);
    final signal = await remote(200, {
      'run': {'code': null, 'signal': 'SIGSEGV'},
    });
    expect(signal.whereType<RunFinished>().single.success, isFalse);
    expect(
      executionSummary(
        const RunFinished(elapsed: Duration.zero, exitCode: 3),
        'boom',
      ),
      contains('exit code 3'),
    );
  });
  for (final style in ChartStyle.values) {
    test('${style.name} round-trips and exports visibly in PDF', () async {
      final block = VisualBlock.fromInput(
        kind: VisualKind.chart,
        title: 'Chart',
        input: 'A; 20\nB; 40\nC; 10',
        style: style,
      );
      expect(VisualBlock.parse(block.json)!.style, style);
      final note = Note(
        id: 'chart',
        title: style.name,
        body: block.markdown,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      final bytes = await PdfExportService.generate(note);
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      await Directory('build/verification').create(recursive: true);
      await File(
        'build/verification/chart-${style.name}.pdf',
      ).writeAsBytes(bytes);
    });
  }
  test(
    'pie rejects non-positive values while signed bar and area remain valid',
    () {
      expect(
        () => VisualBlock.fromInput(
          kind: VisualKind.chart,
          title: 'Pie',
          input: 'A; -1',
          style: ChartStyle.pie,
        ),
        throwsFormatException,
      );
      for (final style in [ChartStyle.horizontalBar, ChartStyle.area]) {
        expect(
          VisualBlock.fromInput(
            kind: VisualKind.chart,
            title: 'Signed',
            input: 'A; -20\nB; 10',
            style: style,
          ).items.first.value,
          -20,
        );
      }
    },
  );
  testWidgets('single-line gutter and editor share the exact text baseline', (
    tester,
  ) async {
    final controller = TextEditingController(text: '1');
    final focus = FocusNode();
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: Scaffold(
          body: CodeTextEditor(
            controller: controller,
            focusNode: focus,
            scrollController: scroll,
            metrics: EditorMetrics(),
            fontSize: 14,
            showLineNumbers: true,
            isCode: false,
          ),
        ),
      ),
    );
    final editable = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final gutter = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_GutterPainter',
    );
    final dynamic painter = tester.widget<CustomPaint>(gutter).painter;
    final tp = TextPainter(
      text: TextSpan(text: '1', style: painter.style as TextStyle),
      strutStyle: painter.strut as StrutStyle,
      textDirection: TextDirection.ltr,
    )..layout();
    final gutterY =
        tester.getTopLeft(gutter).dy +
        tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    final textY =
        editable.localToGlobal(Offset.zero).dy +
        editable.getDryBaseline(
          BoxConstraints.tight(editable.size),
          TextBaseline.alphabetic,
        )!;
    expect(gutterY, closeTo(textY, .1));
    tp.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
    scroll.dispose();
  });
}
