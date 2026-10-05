import '../../core/l10n/app_strings.dart';
import '../../data/models/app_settings.dart';
import '../languages.dart';
import 'execution.dart';
import 'local_executor.dart';
import 'remote_executor.dart';

/// Chooses the right [CodeExecutor] for a language according to the user's
/// execution settings.
class ExecutionService {
  ExecutionService(this.local);

  final LocalExecutor local;

  /// Returns an executor, or `null` with [reason] explaining why none is
  /// available.
  Future<({CodeExecutor? executor, String? reason})> pick({
    required CodeLanguage language,
    required AppSettings settings,
    required String remoteKey,
  }) async {
    RemoteExecutor remote() =>
        RemoteExecutor(endpoint: settings.remoteEndpoint, apiKey: remoteKey);

    switch (settings.executionMode) {
      case ExecutionMode.local:
        if (await local.supports(language)) {
          return (executor: local, reason: null);
        }
        return (
          executor: null,
          reason: trs('No local toolchain for {name} was found.', {
            'name': language.name,
          }),
        );
      case ExecutionMode.remote:
        final r = remote();
        if (await r.supports(language)) return (executor: r, reason: null);
        return (
          executor: null,
          reason: trs('{name} is not supported by the remote API.', {
            'name': language.name,
          }),
        );
      case ExecutionMode.auto:
        if (await local.supports(language)) {
          return (executor: local, reason: null);
        }
        final r = remote();
        if (await r.supports(language)) return (executor: r, reason: null);
        return (
          executor: null,
          reason: trs(
            'Cannot run {name}: no local toolchain and no remote API configured.',
            {'name': language.name},
          ),
        );
    }
  }
}
