import '../../core/l10n/app_strings.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:archive/archive.dart';

import '../../core/util/platform_info.dart';
import '../languages.dart';
import 'execution.dart';

/// Runs code with toolchains installed on the host (desktop only).
class LocalExecutor implements CodeExecutor {
  static const int _maxOutputChars = 1000000;

  final Map<String, ToolChain?> _detected = {};

  @override
  String get name => 'Local';

  /// Forget detection results (e.g. after the user installed a toolchain).
  void clearCache() => _detected.clear();

  Future<ToolChain?> detect(CodeLanguage language) async {
    if (!PlatformInfo.canRunLocalProcesses) return null;
    if (_detected.containsKey(language.id)) return _detected[language.id];
    ToolChain? found;
    for (final chain in language.toolchains) {
      if (await _probe(chain)) {
        found = chain;
        break;
      }
    }
    if (found == null && language.id == 'kotlin' && Platform.isWindows) {
      final programs =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final kotlinHome = Platform.environment['KOTLIN_HOME'];
      final roots = [
        ?kotlinHome,
        p.join(
          programs,
          'Android',
          'Android Studio',
          'plugins',
          'Kotlin',
          'kotlinc',
        ),
        r'C:\kotlin\kotlinc',
      ];
      final javaCandidates = [
        if (Platform.environment['JAVA_HOME'] case final home?)
          p.join(home, 'bin', 'java.exe'),
        p.join(programs, 'Android', 'Android Studio', 'jbr', 'bin', 'java.exe'),
      ];
      for (final root in roots) {
        if (!await File(p.join(root, 'lib', 'kotlin-compiler.jar')).exists()) {
          continue;
        }
        for (final java in javaCandidates) {
          if (!await File(java).exists()) continue;
          final compiler = [
            '-cp',
            p.join(root, 'lib', '*'),
            'org.jetbrains.kotlin.cli.jvm.K2JVMCompiler',
            '-kotlin-home',
            root,
          ];
          final candidate = ToolChain(
            label: 'Kotlin (installed compiler)',
            probe: [java, ...compiler, '-version'],
            steps: [
              ExecStep(java, [
                ...compiler,
                '{src}',
                '-include-runtime',
                '-d',
                'out.jar',
              ]),
              ExecStep(java, ['-jar', 'out.jar']),
            ],
          );
          if (await _probe(candidate)) {
            found = candidate;
            break;
          }
        }
        if (found != null) break;
      }
    }
    // Failed discovery is retried, so installing a compiler does not require restart.
    if (found != null) _detected[language.id] = found;
    return found;
  }

  Future<bool> _probe(ToolChain chain) async {
    try {
      final r = await Process.run(
        chain.probe.first,
        chain.probe.skip(1).toList(),
        runInShell: chain.shell,
      ).timeout(const Duration(seconds: 8));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> supports(CodeLanguage language) async =>
      (await detect(language)) != null;

  @override
  Stream<RunEvent> execute(ExecutionRequest request) {
    final controller = StreamController<RunEvent>();
    final job = _LocalJob(this, request, controller);
    controller.onListen = job.start;
    controller.onCancel = job.cancel;
    return controller.stream;
  }
}

class _LocalJob {
  _LocalJob(this.executor, this.request, this.controller);

  final LocalExecutor executor;
  final ExecutionRequest request;
  final StreamController<RunEvent> controller;

  Process? _process;
  bool _cancelled = false;
  bool _timedOut = false;
  bool _compiledOnly = false;
  int _outputChars = 0;

  void _emit(RunEvent e) {
    if (!controller.isClosed) controller.add(e);
  }

  Future<void> cancel() async {
    _cancelled = true;
    await _kill();
  }

  Future<void> _kill() async {
    final proc = _process;
    if (proc == null) return;
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${proc.pid}', '/T', '/F']);
      } else {
        proc.kill(ProcessSignal.sigkill);
      }
    } catch (e) {
      debugPrint('kill failed: $e');
    }
  }

  Future<void> start() async {
    final sw = Stopwatch()..start();
    final lang = request.language;
    Directory? dir;
    Timer? timer;
    int? exitCode;
    String? failure;

    try {
      final chain = await executor.detect(lang);
      if (chain == null) {
        failure = trs('No local toolchain for {name} was found.', {
          'name': lang.name,
        });
        _emit(
          RunOutput(
            '$failure ${trs('Install {name} and make sure it is on your PATH, or enable the remote API in Settings.', {'name': lang.name})}\n',
            isError: true,
          ),
        );
        return;
      }

      dir = await Directory.systemTemp.createTemp('markbit_run_');
      await File(
        p.join(dir.path, lang.sourceFileName),
      ).writeAsString(request.code);
      final out = p.join(dir.path, Platform.isWindows ? 'main.exe' : 'main');

      timer = Timer(request.timeout, () {
        _timedOut = true;
        _kill();
      });

      String sub(String s) => s
          .replaceAll('{src}', lang.sourceFileName)
          .replaceAll('{dir}', dir!.path)
          .replaceAll('{out}', out);

      for (var i = 0; i < chain.steps.length; i++) {
        if (_cancelled || _timedOut) break;
        final step = chain.steps[i];
        final isLast = i == chain.steps.length - 1;
        _emit(RunPhase(isLast ? 'Running' : 'Compiling'));
        exitCode = await _runStep(
          sub(step.exe),
          step.args.map(sub).toList(),
          dir.path,
          chain.shell,
          feedStdin: isLast,
        );
        if (exitCode != 0) break;
        if (lang.id == 'kotlin' && !isLast) {
          final archive = ZipDecoder().decodeBytes(
            await File(p.join(dir.path, 'out.jar')).readAsBytes(),
          );
          final manifest = archive.findFile('META-INF/MANIFEST.MF');
          if (manifest != null &&
              !RegExp(
                r'^Main-Class:',
                multiLine: true,
              ).hasMatch(utf8.decode(manifest.content as List<int>))) {
            _compiledOnly = true;
            break;
          }
        }
      }
    } catch (e) {
      failure = '$e';
      _emit(RunOutput('$e\n', isError: true));
    } finally {
      timer?.cancel();
      sw.stop();
      _emit(
        RunFinished(
          elapsed: sw.elapsed,
          exitCode: exitCode,
          timedOut: _timedOut,
          cancelled: _cancelled,
          failure: failure,
          compiledOnly: _compiledOnly,
        ),
      );
      if (!controller.isClosed) await controller.close();
      if (dir != null) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<int> _runStep(
    String exe,
    List<String> args,
    String workingDir,
    bool shell, {
    required bool feedStdin,
  }) async {
    final proc = await Process.start(
      exe,
      args,
      workingDirectory: workingDir,
      runInShell: shell,
      environment: const {
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
        'NO_COLOR': '1',
        'DOTNET_CLI_UI_LANGUAGE': 'en',
      },
    );
    _process = proc;

    final outDone = Completer<void>();
    final errDone = Completer<void>();
    proc.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) => _onChunk(chunk, false),
          onDone: outDone.complete,
          onError: (_) => outDone.complete(),
        );
    proc.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (chunk) => _onChunk(chunk, true),
          onDone: errDone.complete,
          onError: (_) => errDone.complete(),
        );

    try {
      if (feedStdin && request.stdin.isNotEmpty) {
        proc.stdin.write(request.stdin);
        if (!request.stdin.endsWith('\n')) proc.stdin.write('\n');
      }
      await proc.stdin.close();
    } catch (_) {
      // The process may exit before reading stdin; that is fine.
    }

    final code = await proc.exitCode;
    await Future.wait([
      outDone.future,
      errDone.future,
    ]).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    _process = null;
    return code;
  }

  void _onChunk(String chunk, bool isError) {
    _outputChars += chunk.length;
    if (_outputChars > LocalExecutor._maxOutputChars) {
      if (_outputChars - chunk.length <= LocalExecutor._maxOutputChars) {
        _emit(
          RunOutput(
            '\n${trs('[output truncated: limit reached]')}\n',
            isError: true,
          ),
        );
        _kill();
      }
      return;
    }
    _emit(RunOutput(chunk, isError: isError));
  }
}
