import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/l10n/app_strings.dart';
import 'repository/settings_store.dart';

/// Name of the file the Windows installer writes next to the executable,
/// holding the language chosen in setup (`en`, `tr`, `de` or `es`).
const installerLanguageFile = 'setup-language';

/// On the very first launch, starts the app in the language picked in the
/// installer. Does nothing once settings have been saved, so the user's own
/// choice always wins. [appDir] defaults to the executable's folder.
Future<void> applyInstallerLanguage(
  SettingsStore store, {
  String? appDir,
}) async {
  if (store.hasSaved) return;
  final file = File(
    p.join(
      appDir ?? p.dirname(Platform.resolvedExecutable),
      installerLanguageFile,
    ),
  );
  try {
    if (!await file.exists()) return;
    final code = (await file.readAsString()).trim().toLowerCase();
    if (!AppStrings.languageNames.containsKey(code)) return;
    await store.save(store.load().copyWith(language: code));
  } on FileSystemException {
    // Unreadable marker: keep following the system language.
  }
}
