import '../languages.dart';

class ExecutionRequest {
  const ExecutionRequest({
    required this.language,
    required this.code,
    this.stdin = '',
    this.timeout = const Duration(seconds: 20),
  });

  final CodeLanguage language;
  final String code;
  final String stdin;
  final Duration timeout;
}

sealed class RunEvent {
  const RunEvent();
}

/// A phase change such as "Compiling" or "Running".
class RunPhase extends RunEvent {
  const RunPhase(this.label);
  final String label;
}

class RunOutput extends RunEvent {
  const RunOutput(this.text, {this.isError = false});
  final String text;
  final bool isError;
}

class RunFinished extends RunEvent {
  const RunFinished({
    required this.elapsed,
    this.exitCode,
    this.timedOut = false,
    this.cancelled = false,
    this.failure,
    this.compiledOnly = false,
  });

  final Duration elapsed;
  final int? exitCode;
  final bool timedOut;
  final bool cancelled;

  /// Set when the run could not be carried out at all (no toolchain, network
  /// error...), as opposed to the program exiting non-zero.
  final String? failure;

  /// Valid library code compiled without a runnable entry point.
  final bool compiledOnly;

  bool get success =>
      failure == null && !timedOut && !cancelled && (exitCode ?? 0) == 0;
}

/// Something that can run code and stream its output. Cancelling the stream
/// subscription must stop the underlying work.
abstract interface class CodeExecutor {
  String get name;
  Future<bool> supports(CodeLanguage language);
  Stream<RunEvent> execute(ExecutionRequest request);
}
