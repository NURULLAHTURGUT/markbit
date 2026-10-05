import 'dart:isolate';

import 'package:markbit/domain/colored_text.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;

void _parseStyledText((SendPort, List<String>) request) {
  final document = md.Document(
    inlineSyntaxes: [ColoredTextSyntax()],
    blockSyntaxes: [ColoredTextBlockSyntax()],
  );
  request.$1.send([
    for (final source in request.$2)
      document.parseLines(source.split('\n')).single.textContent,
  ]);
}

void main() {
  test(
    'incomplete span values parse as literal text without stalling',
    () async {
      const sources = [
        '<span style="color: #;">Text</span>',
        '<span style="color: #2;">Text</span>',
        '<span style="color: #2563E;">Text</span>',
        '<span style="color: #invalid;">Text</span>',
        '<span style="font-size: pt;">Text</span>',
        '<span style="font-size: 2pt;">Text</span>',
        '<span style="font-family: ;">Text</span>',
        '<span style="font-family: Geo;">Text</span>',
        '<span style="background: red;">Text</span>',
        '<span style="color: #2563EB; font-size: pt;">Text</span>',
      ];
      // A stalled parser must fail this test without blocking the test runner.
      final output = ReceivePort();
      final isolate = await Isolate.spawn(_parseStyledText, (
        output.sendPort,
        sources,
      ));
      try {
        expect(await output.first.timeout(const Duration(seconds: 3)), sources);
      } finally {
        isolate.kill(priority: Isolate.immediate);
        output.close();
      }
    },
  );
}
