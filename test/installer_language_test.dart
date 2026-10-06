import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markbit/data/installer_language.dart';
import 'package:markbit/data/repository/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('markbit_setup_');
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() => dir.delete(recursive: true));

  Future<SettingsStore> store([Map<String, Object> values = const {}]) async {
    SharedPreferences.setMockInitialValues(values);
    final s = SettingsStore(await SharedPreferences.getInstance());
    await s.initialize();
    return s;
  }

  Future<void> marker(String text) =>
      File('${dir.path}/$installerLanguageFile').writeAsString(text);

  test('first launch uses the language chosen in the installer', () async {
    final s = await store();
    await marker('tr\r\n');
    await applyInstallerLanguage(s, appDir: dir.path);
    expect(s.load().language, 'tr');
    expect(s.hasSaved, isTrue);
  });

  test('a saved choice is never overridden', () async {
    final s = await store();
    await s.save(s.load().copyWith(language: 'de'));
    await marker('es');
    await applyInstallerLanguage(s, appDir: dir.path);
    expect(s.load().language, 'de');
  });

  test('missing or unknown marker keeps the system language', () async {
    final s = await store();
    await applyInstallerLanguage(s, appDir: dir.path);
    expect(s.load().language, 'system');
    expect(s.hasSaved, isFalse);
    await marker('klingon');
    await applyInstallerLanguage(s, appDir: dir.path);
    expect(s.load().language, 'system');
  });
}
