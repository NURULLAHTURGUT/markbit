import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/util/platform_info.dart';
import '../data/repository/chat_store.dart';
import '../data/repository/library_repository.dart';
import 'persistence_coordinator.dart';
import 'providers.dart';
import 'reminders.dart';

/// Runs after all data was deleted: on desktop Markbit starts again with an
/// empty library; elsewhere it closes and starts fresh on the next launch.
/// Nothing in memory may be written back, so the process always ends.
/// Overridden in tests.
final appRestartProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    if (PlatformInfo.isDesktop) {
      await Process.start(
        Platform.resolvedExecutable,
        const [],
        mode: ProcessStartMode.detached,
      );
    }
    exit(0);
  },
);

/// Deletes every note, notebook, tag, template, version, cover, AI chat,
/// setting, preference and stored API key, and cancels scheduled reminders.
/// Backups the user saved elsewhere are not touched.
///
/// Returns the paths that could not be removed (for example a file another
/// program keeps open). The caller should restart the app afterwards with
/// [appRestartProvider].
Future<List<String>> deleteAllData(WidgetRef ref) async {
  final persistence = ref.read(persistenceProvider);
  persistence.flushEditors();
  await persistence.flush();
  final chats = ref.read(chatStoreProvider);
  if (chats is FileChatStore) await chats.flush();

  if (ref.read(reminderPlatformEnabledProvider)) {
    try {
      final reminders = TaskReminders(ref.read(sharedPrefsProvider));
      if (await reminders.init()) await reminders.clear();
    } catch (_) {
      // Reminders for deleted tasks only show a missing note; carry on.
    }
  }

  final repository = ref.read(libraryRepositoryProvider);
  final failed = repository is FileLibraryRepository
      ? await repository.wipe()
      : <String>[];
  await ref.read(settingsStoreProvider).clearAll();
  return failed;
}
