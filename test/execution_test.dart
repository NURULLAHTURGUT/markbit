import 'package:markbit/domain/execution/execution.dart';
import 'package:markbit/domain/execution/local_executor.dart';
import 'package:markbit/domain/languages.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs against whatever toolchain exists on the machine running the tests;
/// a language is skipped when none is installed.
void main() {
  final local = LocalExecutor();

  Future<({String out, String err, RunFinished done})> run(
    CodeLanguage lang,
    String code, {
    String stdin = '',
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final out = StringBuffer();
    final err = StringBuffer();
    RunFinished? done;
    await for (final e in local.execute(
      ExecutionRequest(
        language: lang,
        code: code,
        stdin: stdin,
        timeout: timeout,
      ),
    )) {
      switch (e) {
        case RunOutput(:final text, :final isError):
          (isError ? err : out).write(text);
        case RunFinished():
          done = e;
        case RunPhase():
          break;
      }
    }
    return (out: out.toString(), err: err.toString(), done: done!);
  }

  const cases = <(String, String, String)>[
    ('python', 'print("hello " + input())', 'hello markbit'),
    (
      'javascript',
      'console.log("hello " + require("fs").readFileSync(0, "utf8").trim())',
      'hello markbit',
    ),
    (
      'dart',
      'import "dart:io";\nvoid main() { print("hello " + stdin.readLineSync()!); }',
      'hello markbit',
    ),
  ];

  for (final (id, code, expected) in cases) {
    test(
      'local $id runs code with stdin',
      () async {
        final lang = Languages.find(id)!;
        if (await local.detect(lang) == null) {
          markTestSkipped('$id toolchain not installed');
          return;
        }
        final r = await run(lang, code, stdin: 'markbit');
        expect(r.done.success, isTrue, reason: r.err);
        expect(r.out.trim(), expected);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  test('non-zero exit code and stderr are reported', () async {
    final lang = Languages.find('python')!;
    if (await local.detect(lang) == null) {
      markTestSkipped('python not installed');
      return;
    }
    final r = await run(
      lang,
      'import sys\nsys.stderr.write("boom")\nsys.exit(3)',
    );
    expect(r.done.exitCode, 3);
    expect(r.done.success, isFalse);
    expect(r.err, contains('boom'));
  });

  test('timeout kills the process', () async {
    final lang = Languages.find('python')!;
    if (await local.detect(lang) == null) {
      markTestSkipped('python not installed');
      return;
    }
    final sw = Stopwatch()..start();
    final r = await run(
      lang,
      'import time\ntime.sleep(30)',
      timeout: const Duration(seconds: 2),
    );
    expect(r.done.timedOut, isTrue);
    expect(sw.elapsed, lessThan(const Duration(seconds: 15)));
  });

  test('cancelling the stream stops the run', () async {
    final lang = Languages.find('python')!;
    if (await local.detect(lang) == null) {
      markTestSkipped('python not installed');
      return;
    }
    final sub = local
        .execute(
          ExecutionRequest(language: lang, code: 'import time\ntime.sleep(30)'),
        )
        .listen((_) {});
    await Future<void>.delayed(const Duration(seconds: 1));
    final sw = Stopwatch()..start();
    await sub.cancel();
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });
}
