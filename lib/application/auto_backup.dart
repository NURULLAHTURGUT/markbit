import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../data/backup_service.dart';
import '../data/repository/chat_store.dart';
import '../data/repository/library_repository.dart';
import 'ai_notifier.dart';
import 'providers.dart';
import 'persistence_coordinator.dart';

class AutoBackup extends ChangeNotifier {
  AutoBackup(this.preferences, this.capture);
  final SharedPreferences preferences;
  final Future<String> Function() capture;
  Timer? _timer;
  bool busy = false;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String? error;
  bool get enabled => preferences.getBool('auto_backup_enabled') ?? false;
  String? get folder => preferences.getString('auto_backup_folder');
  int get keep => (preferences.getInt('auto_backup_keep') ?? 7).clamp(1, 30);
  DateTime? get last =>
      DateTime.tryParse(preferences.getString('auto_backup_last') ?? '');
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => check());
    unawaited(check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> configure({bool? enabled, String? folder, int? keep}) async {
    if (folder != null &&
        !await preferences.setString('auto_backup_folder', folder)) {
      throw StateError('Could not save backup folder');
    }
    if (keep != null &&
        !await preferences.setInt('auto_backup_keep', keep.clamp(1, 30))) {
      throw StateError('Could not save backup retention');
    }
    if (enabled != null &&
        !await preferences.setBool('auto_backup_enabled', enabled)) {
      throw StateError('Could not save backup settings');
    }
    error = null;
    _notify();
    if (enabled == true) unawaited(check());
  }

  Future<void> check({bool force = false}) async {
    if (busy || !enabled || folder == null) return;
    final now = DateTime.now();
    if (!force &&
        last != null &&
        now.difference(last!) < const Duration(days: 1)) {
      return;
    }
    busy = true;
    error = null;
    _notify();
    try {
      final directory = Directory(folder!);
      await directory.create(recursive: true);
      final resolved = await directory.resolveSymbolicLinks();
      final raw = await capture();
      final stamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File(p.join(resolved, 'Markbit-Auto-$stamp.markbit'));
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(raw, flush: true);
      await temp.rename(file.path);
      final copies = <File>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File &&
            RegExp(
              r'^Markbit-Auto-\d{4}-\d{2}-\d{2}T[\d-]+\.markbit$',
            ).hasMatch(p.basename(entity.path))) {
          // Only valid app backups are candidates for retention cleanup.
          try {
            BackupService.validateHeader(await entity.readAsString());
            copies.add(entity);
          } catch (_) {}
        }
      }
      copies.sort((a, b) => b.path.compareTo(a.path));
      for (final old in copies.skip(keep)) {
        final target = p.normalize(await old.resolveSymbolicLinks());
        if (!p.isWithin(p.normalize(p.absolute(resolved)), target)) continue;
        await old.delete();
      }
      if (!await preferences.setString(
        'auto_backup_last',
        now.toIso8601String(),
      )) {
        throw StateError('Could not save backup time');
      }
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}

final autoBackupProvider = Provider<AutoBackup>((ref) {
  final preferences = ref.read(sharedPrefsProvider);
  final service = AutoBackup(preferences, () async {
    final persistence = ref.read(persistenceProvider);
    persistence.flushEditors();
    final library = ref.read(libraryProvider);
    final settings = ref.read(settingsProvider);
    final chats = ref.read(chatStoreProvider);
    final repository = ref.read(libraryRepositoryProvider);
    final activeNotifiers = [
      for (final note in library.notes.values)
        if (ref.exists(aiProvider(note.id)))
          ref.read(aiProvider(note.id).notifier),
    ];
    for (final notifier in activeNotifiers) {
      await notifier.flush();
    }
    await persistence.flush();
    return BackupService.encode(
      library,
      settings,
      chats,
      preferences,
      history: repository is FileLibraryRepository ? repository.history : null,
    );
  });
  ref.onDispose(service.dispose);
  return service;
});
