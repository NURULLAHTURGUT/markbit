import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/startup_error.dart';
import 'core/l10n/app_strings.dart';
import 'data/repository/settings_store.dart';
import 'data/installer_language.dart';
import 'application/onboarding.dart';
import 'application/providers.dart';
import 'data/repository/library_repository.dart';
import 'data/seed.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'data/repository/chat_store.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  // "--note=<id>": a separate window showing one note (see openNoteWindow).
  final noteWindow = args
      .where((a) => a.startsWith('--note='))
      .map((a) => a.substring('--note='.length))
      .firstOrNull;

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Unhandled Flutter error: ${details.exceptionAsString()}');
  };

  try {
    var prefs = await SharedPreferences.getInstance();
    if (noteWindow != null) {
      // A note window reads the main window's preferences but never writes
      // them back: both processes rewriting the same file would lose
      // changes. Its own UI state lives in memory only.
      final values = <String, Object>{
        for (final key in prefs.getKeys())
          if (prefs.get(key) case final Object value) key: value,
      };
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.resetStatic();
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues(values);
      prefs = await SharedPreferences.getInstance();
    }
    final settingsStore = SettingsStore(prefs);
    await settingsStore.initialize();
    if (noteWindow == null) await applyInstallerLanguage(settingsStore);
    final language = settingsStore.load().language;
    AppStrings.current = AppStrings(
      language == 'system'
          ? WidgetsBinding.instance.platformDispatcher.locale
          : Locale(language),
    );
    final repository = await FileLibraryRepository.open();
    final snapshot = await loadOrSeed(repository);
    final chatStore = FileChatStore(
      Directory(p.join(repository.root.path, 'chats')),
    );
    await chatStore.migrate(prefs);
    for (final warning in chatStore.migrationWarnings) {
      repository.reportRecoveryIssue(warning);
    }

    runApp(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          settingsStoreProvider.overrideWithValue(settingsStore),
          chatStoreProvider.overrideWithValue(chatStore),
          libraryRepositoryProvider.overrideWithValue(repository),
          initialLibraryProvider.overrideWithValue(snapshot),
          libraryWatchEnabledProvider.overrideWithValue(true),
          // Only the main window schedules reminders and backups.
          reminderPlatformEnabledProvider.overrideWithValue(noteWindow == null),
          noteWindowProvider.overrideWithValue(noteWindow),
          onboardingEnabledProvider.overrideWithValue(noteWindow == null),
        ],
        child: const MarkbitApp(),
      ),
    );
  } catch (_) {
    // AppStrings.current holds the chosen language if settings were read
    // before the failure, English otherwise.
    runApp(StartupErrorApp(onRetry: () => main(args)));
  }
}
