import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/app_settings.dart';
import '../data/repository/library_repository.dart';
import '../data/repository/settings_store.dart';
import '../domain/execution/execution_service.dart';
import '../domain/execution/local_executor.dart';
import '../domain/execution/sql_executor.dart';
import 'library_notifier.dart';
import 'persistence_coordinator.dart';

// ---- Infrastructure (overridden in main()) --------------------------------

final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) =>
      throw UnimplementedError('libraryRepositoryProvider must be overridden'),
);

final initialLibraryProvider = Provider<LibrarySnapshot>(
  (ref) =>
      throw UnimplementedError('initialLibraryProvider must be overridden'),
);

/// Whether the library folder is watched for changes made by other programs.
/// Enabled by `main()`; tests opt in explicitly.
final libraryWatchEnabledProvider = Provider<bool>((ref) => false);

/// Whether task reminders use operating-system notifications. Enabled by
/// `main()`; widget tests run without the native plugin.
final reminderPlatformEnabledProvider = Provider<bool>((ref) => false);

/// Id of the note when this process is a separate note window.
final noteWindowProvider = Provider<String?>((ref) => null);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => SettingsStore(ref.watch(sharedPrefsProvider)),
);

// ---- Domain state ---------------------------------------------------------

final libraryProvider = NotifierProvider<LibraryNotifier, Library>(
  LibraryNotifier.new,
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsStoreProvider).load();

  void update(AppSettings Function(AppSettings s) fn) {
    state = fn(state);
    final snapshot = state;
    ref
        .read(persistenceProvider)
        .write(
          'settings',
          () => ref.read(settingsStoreProvider).save(snapshot),
        );
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// ---- Execution ------------------------------------------------------------

final localExecutorProvider = Provider<LocalExecutor>((ref) => LocalExecutor());

final executionServiceProvider = Provider<ExecutionService>(
  (ref) => ExecutionService(ref.watch(localExecutorProvider)),
);

final sqlExecutorProvider = Provider.family<SqlExecutor, String>((ref, noteId) {
  final executor = SqlExecutor();
  final persistence = ref.read(persistenceProvider);
  persistence.registerCloser(executor, executor.close);
  ref.onDispose(() {
    persistence.unregisterCloser(executor);
    executor.close();
  });
  return executor;
});
