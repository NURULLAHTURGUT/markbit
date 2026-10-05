import '../core/l10n/app_strings.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/execution/execution.dart';
import '../domain/languages.dart';
import 'providers.dart';
import 'persistence_coordinator.dart';

enum RunStatus { idle, compiling, running, finished }

class OutputChunk {
  const OutputChunk(this.text, this.isError);
  final String text;
  final bool isError;
}

class RunState {
  const RunState({
    this.status = RunStatus.idle,
    this.panelVisible = false,
    this.languageName = '',
    this.sourceLabel = '',
    this.executorName = '',
    this.chunks = const [],
    this.stdin = '',
    this.result,
  });

  final RunStatus status;
  final bool panelVisible;
  final String languageName;

  /// What is being run, e.g. the note title.
  final String sourceLabel;
  final String executorName;
  final List<OutputChunk> chunks;
  final String stdin;
  final RunFinished? result;

  bool get isBusy =>
      status == RunStatus.compiling || status == RunStatus.running;

  RunState copyWith({
    RunStatus? status,
    bool? panelVisible,
    String? languageName,
    String? sourceLabel,
    String? executorName,
    List<OutputChunk>? chunks,
    String? stdin,
    Object? result = _keep,
  }) => RunState(
    status: status ?? this.status,
    panelVisible: panelVisible ?? this.panelVisible,
    languageName: languageName ?? this.languageName,
    sourceLabel: sourceLabel ?? this.sourceLabel,
    executorName: executorName ?? this.executorName,
    chunks: chunks ?? this.chunks,
    stdin: stdin ?? this.stdin,
    result: identical(result, _keep) ? this.result : result as RunFinished?,
  );
}

const Object _keep = Object();

class RunnerNotifier extends Notifier<RunState> {
  RunnerNotifier({this.noteId});
  final String? noteId;
  StreamSubscription<RunEvent>? _sub;
  final List<OutputChunk> _pending = [];
  Timer? _flushTimer;
  ({String? languageName, String code, String sourceLabel})? _last;

  bool get canRerun => _last != null && !state.isBusy;

  Future<void> rerun() {
    final last = _last;
    if (last == null) return Future.value();
    return run(
      languageName: last.languageName,
      code: last.code,
      sourceLabel: last.sourceLabel,
    );
  }

  @override
  RunState build() {
    final persistence = ref.read(persistenceProvider);
    persistence.registerCloser(this, cancel);
    ref.onDispose(() {
      persistence.unregisterCloser(this);
      _sub?.cancel();
      _flushTimer?.cancel();
    });
    return const RunState();
  }

  void setStdin(String v) => state = state.copyWith(stdin: v);
  void showPanel() => state = state.copyWith(panelVisible: true);
  void hidePanel() => state = state.copyWith(panelVisible: false);

  void clearOutput() {
    if (state.isBusy) return;
    state = state.copyWith(
      chunks: const [],
      result: null,
      status: RunStatus.idle,
    );
  }

  /// Plain text of everything printed so far.
  String get outputText => state.chunks.map((c) => c.text).join();

  Future<void> run({
    required String? languageName,
    required String code,
    required String sourceLabel,
  }) async {
    if (state.isBusy) return;
    _last = (languageName: languageName, code: code, sourceLabel: sourceLabel);
    final settings = ref.read(settingsProvider);
    final lang = Languages.find(languageName);

    state = state.copyWith(
      panelVisible: true,
      chunks: const [],
      result: null,
      sourceLabel: sourceLabel,
      languageName: lang?.name ?? (languageName ?? trs('unknown')),
      executorName: '',
      status: RunStatus.running,
    );

    if (lang == null || !lang.runnable) {
      _finishWithMessage(
        trs(
          'Language {name} cannot be run. Add a language tag to the code fence, e.g. ```python.',
          {'name': languageName ?? ''},
        ),
      );
      return;
    }

    final picked = lang.id == 'sql'
        ? (
            executor: ref.read(sqlExecutorProvider(noteId ?? 'standalone')),
            reason: null,
          )
        : await ref
              .read(executionServiceProvider)
              .pick(
                language: lang,
                settings: settings,
                remoteKey: ref.read(settingsStoreProvider).remoteExecKey,
              );
    final executor = picked.executor;
    if (!ref.mounted || !state.isBusy) return;
    if (executor == null) {
      _finishWithMessage(
        '${picked.reason}\n\n${trs('Install the toolchain, or configure a remote execution API in Settings → Code execution.')}',
      );
      return;
    }

    state = state.copyWith(executorName: executor.name);
    final request = ExecutionRequest(
      language: lang,
      code: code,
      stdin: state.stdin,
      timeout: Duration(seconds: settings.runTimeoutSeconds),
    );

    _sub = executor
        .execute(request)
        .listen(
          (event) {
            switch (event) {
              case RunPhase(:final label):
                state = state.copyWith(
                  status: label.startsWith('Compiling')
                      ? RunStatus.compiling
                      : RunStatus.running,
                );
              case RunOutput(:final text, :final isError):
                _pending.add(OutputChunk(text, isError));
                _flushTimer ??= Timer(
                  const Duration(milliseconds: 40),
                  _flushPending,
                );
              case RunFinished():
                _flushPending();
                final summary = executionSummary(event, outputText);
                if (summary != null) {
                  state = state.copyWith(
                    chunks: [
                      ...state.chunks,
                      OutputChunk('\n$summary\n', !event.success),
                    ],
                  );
                }
                state = state.copyWith(
                  status: RunStatus.finished,
                  result: event,
                );
            }
          },
          onError: (Object e) => _finishWithMessage('$e'),
          onDone: () {
            _flushPending();
            if (state.isBusy) {
              state = state.copyWith(status: RunStatus.finished);
            }
          },
        );
  }

  Future<void> cancel() async {
    if (!state.isBusy) return;
    final sub = _sub;
    _sub = null;
    await sub?.cancel();
    _flushPending();
    state = state.copyWith(
      status: RunStatus.finished,
      result: const RunFinished(elapsed: Duration.zero, cancelled: true),
    );
  }

  void _flushPending() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return;
    final merged = [...state.chunks];
    for (final c in _pending) {
      if (merged.isNotEmpty && merged.last.isError == c.isError) {
        final last = merged.removeLast();
        merged.add(OutputChunk(last.text + c.text, c.isError));
      } else {
        merged.add(c);
      }
    }
    _pending.clear();
    state = state.copyWith(chunks: merged);
  }

  void _finishWithMessage(String message) {
    state = state.copyWith(
      status: RunStatus.finished,
      chunks: [OutputChunk(message, true)],
      result: RunFinished(
        elapsed: Duration.zero,
        failure: message.split('\n').first,
      ),
    );
  }
}

final runnerProvider = NotifierProvider<RunnerNotifier, RunState>(
  RunnerNotifier.new,
);

String? executionSummary(RunFinished result, String output) {
  if (result.cancelled || result.timedOut || result.failure != null) {
    return null;
  }
  if (result.compiledOnly) {
    return trs(
      'Compilation succeeded, but this file has no main entry point. The class/library was not executed and has no console output. Add fun main() to run it.',
    );
  }
  if (result.success) {
    return output.trim().isEmpty
        ? trs(
            'The program completed successfully without console output. A class or function definition alone does not print anything; call it and use print/log to display a result.',
          )
        : null;
  }
  final lower = output.toLowerCase();
  if (lower.contains('main method not found') ||
      lower.contains('main function') ||
      lower.contains('entry point') ||
      lower.contains('undefined reference to `main') ||
      lower.contains('undefined reference to \'main') ||
      lower.contains('cs5001') ||
      lower.contains('winmain')) {
    return trs(
      'No runnable entry point was found. Add the main function required by this language; a class definition alone may not be executable.',
    );
  }
  return trs(
    'The program ended with an error (exit code {code}). Review the compiler or runtime details above.',
    {'code': result.exitCode ?? -1},
  );
}

/// Execution, stdin and output belong to the note that initiated the run.
final noteRunnerProvider =
    NotifierProvider.family<RunnerNotifier, RunState, String>(
      (id) => RunnerNotifier(noteId: id),
    );
