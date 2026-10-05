import '../../core/l10n/app_strings.dart';
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../languages.dart';
import 'execution.dart';

/// Runs code through a Piston-compatible HTTP API
/// (`POST {endpoint}/execute`). Works on every platform, including iOS and
/// Android where spawning compilers is not possible.
class RemoteExecutor implements CodeExecutor {
  RemoteExecutor({
    required this.endpoint,
    this.apiKey = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String endpoint;
  final String apiKey;
  final http.Client _client;

  @override
  String get name => 'Remote';

  @override
  Future<bool> supports(CodeLanguage language) async =>
      language.pistonId != null && endpoint.trim().isNotEmpty;

  @override
  Stream<RunEvent> execute(ExecutionRequest request) async* {
    final sw = Stopwatch()..start();
    yield const RunPhase('Running remotely');
    try {
      final base = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
      final response = await _client
          .post(
            Uri.parse('$base/execute'),
            headers: {
              'Content-Type': 'application/json',
              if (apiKey.isNotEmpty) 'Authorization': apiKey,
            },
            body: jsonEncode({
              'language': request.language.pistonId,
              'version': '*',
              'files': [
                {
                  'name': request.language.sourceFileName,
                  'content': request.code,
                },
              ],
              'stdin': request.stdin,
              'run_timeout': request.timeout.inMilliseconds,
              'compile_timeout': request.timeout.inMilliseconds,
            }),
          )
          .timeout(request.timeout + const Duration(seconds: 15));

      Map<String, dynamic>? json;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) json = decoded;
      } catch (_) {}
      if (response.statusCode >= 400 || json?['message'] != null) {
        final message = remoteExecutionError(
          response.statusCode,
          '${json?['message'] ?? response.body}',
        );
        yield RunOutput('$message\n', isError: true);
        yield RunFinished(elapsed: sw.elapsed, failure: message);
        return;
      }
      if (json == null || json['run'] is! Map && json['compile'] is! Map) {
        final message = trs(
          'The execution service returned an invalid result. Check the API address in Settings → Code execution.',
        );
        yield RunOutput('$message\n', isError: true);
        yield RunFinished(elapsed: sw.elapsed, failure: message);
        return;
      }

      final compile = json['compile'] as Map<String, dynamic>?;
      final run = json['run'] as Map<String, dynamic>?;

      if (compile != null) {
        final out = (compile['stdout'] as String?) ?? '';
        final err = (compile['stderr'] as String?) ?? '';
        if (out.isNotEmpty) yield RunOutput(out);
        if (err.isNotEmpty) yield RunOutput(err, isError: true);
        final code = (compile['code'] as num?)?.toInt();
        if (code != null && code != 0) {
          yield RunOutput(
            '${trs('Compilation failed. Review the compiler details above.')}\n',
            isError: true,
          );
          yield RunFinished(elapsed: sw.elapsed, exitCode: code);
          return;
        }
      }

      if (run == null) {
        final message = trs(
          'The execution service did not return a program result. The code was not confirmed as executed.',
        );
        yield RunOutput('$message\n', isError: true);
        yield RunFinished(elapsed: sw.elapsed, failure: message);
        return;
      }
      final out = (run['stdout'] as String?) ?? '';
      final err = (run['stderr'] as String?) ?? '';
      if (out.isNotEmpty) yield RunOutput(out);
      if (err.isNotEmpty) yield RunOutput(err, isError: true);
      final signal = run['signal'] as String?;
      yield RunFinished(
        elapsed: sw.elapsed,
        exitCode: (run['code'] as num?)?.toInt(),
        timedOut:
            run['status'] == 'TO' ||
            signal == 'SIGKILL' && sw.elapsed >= request.timeout,
        failure: signal != null
            ? trs('The program was terminated by signal {signal}.', {
                'signal': signal,
              })
            : run['code'] == null
            ? trs('The execution service did not report an exit code.')
            : null,
      );
    } on TimeoutException {
      yield RunOutput(
        '${trs('The remote request timed out.')}\n',
        isError: true,
      );
      yield RunFinished(
        elapsed: sw.elapsed,
        timedOut: true,
        failure: 'timeout',
      );
    } catch (e) {
      yield RunOutput(
        '${trs('Could not reach the execution API: {error}', {'error': '$e'})}\n',
        isError: true,
      );
      yield RunFinished(elapsed: sw.elapsed, failure: '$e');
    }
  }
}

/// Service failures are distinct from errors produced by the user's code.
String remoteExecutionError(int status, String detail) {
  final lower = detail.toLowerCase();
  if (lower.contains('whitelist')) {
    return trs(
      'The remote service requires access approval. Your code was not executed. Use a local toolchain or configure an authorized/self-hosted API in Settings → Code execution.',
    );
  }
  if (status == 401 || status == 403) {
    return trs(
      'The execution service denied access. Check your API key and permissions in Settings → Code execution. Your code was not executed.',
    );
  }
  if (status == 429) {
    return trs(
      'The execution service request limit was reached. Wait and try again.',
    );
  }
  if (status >= 500) {
    return trs(
      'The execution service is temporarily unavailable. Try again later or use local execution.',
    );
  }
  if (status == 404) {
    return trs(
      'The execution API address was not found. Check the endpoint in Settings → Code execution.',
    );
  }
  if (lower.contains('unknown language') ||
      lower.contains('not installed') ||
      lower.contains('runtime')) {
    return trs(
      'This language or runtime is unavailable on the remote service. Try local execution or a different API.',
    );
  }
  return trs(
    'The execution service rejected the request (HTTP {status}): {detail}',
    {
      'status': status,
      'detail': detail.length > 300 ? detail.substring(0, 300) : detail,
    },
  );
}
