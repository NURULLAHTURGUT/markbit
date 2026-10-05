import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/l10n/app_strings.dart';
import '../data/models/note.dart';
import '../domain/note_tasks.dart';

/// Task reminders as operating-system notifications, scheduled ahead so they
/// arrive even when Markbit is minimised or closed.
class TaskReminders {
  TaskReminders(this._prefs);

  final SharedPreferences _prefs;
  final _plugin = FlutterLocalNotificationsPlugin();
  static const _key = 'reminder_ids_v1';
  static const _horizon = Duration(days: 60);
  static const _max = 60;

  bool _initialised = false;
  bool available = false;

  /// Called when the user clicks a reminder; receives the note id.
  ValueChanged<String>? onOpen;

  static bool get supported =>
      !kIsWeb &&
      (Platform.isWindows ||
          Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux);

  Future<bool> init() async {
    if (_initialised) return available;
    _initialised = true;
    if (!supported) return false;
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'Markbit',
            appUserModelId: 'Markbit.Markbit.Desktop',
            guid: '186ad914-d194-42b4-a54f-a39be7dba016',
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final id = r.payload;
          if (id != null && id.isNotEmpty) onOpen?.call(id);
        },
      );
      available = ok ?? true;
      if (available && Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }
      // Opened by clicking a reminder while the app was closed.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true &&
          payload != null &&
          payload.isNotEmpty) {
        Future.microtask(() => onOpen?.call(payload));
      }
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
      available = false;
    }
    return available;
  }

  /// Stable 31-bit id for one reminder (FNV-1a of task key and date).
  static int idFor(NoteTask task) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode('${task.key}|${task.due}')) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Schedules reminders for open tasks with a future date and removes the
  /// ones no longer needed.
  Future<void> sync(Iterable<(Note, NoteTask)> tasks) async {
    if (!available) return;
    final now = DateTime.now();
    final wanted = <int, (Note, NoteTask)>{};
    final upcoming =
        tasks
            .where(
              (e) =>
                  !e.$2.done &&
                  e.$2.due != null &&
                  e.$2.due!.isAfter(now) &&
                  e.$2.due!.isBefore(now.add(_horizon)),
            )
            .toList()
          ..sort((a, b) => a.$2.due!.compareTo(b.$2.due!));
    for (final e in upcoming.take(_max)) {
      wanted[idFor(e.$2)] = e;
    }
    final previous = {
      for (final s in _prefs.getStringList(_key) ?? const <String>[])
        ?int.tryParse(s),
    };
    for (final id in previous.difference(wanted.keys.toSet())) {
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
    for (final entry in wanted.entries) {
      if (previous.contains(entry.key)) continue;
      final (note, task) = entry.value;
      try {
        await _plugin.zonedSchedule(
          id: entry.key,
          title: trs('Task reminder'),
          body: '${task.text}\n${note.displayTitle}',
          payload: note.id,
          scheduledDate: tz.TZDateTime.from(task.due!, tz.UTC),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'task_reminders',
              'Task reminders',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
            macOS: DarwinNotificationDetails(),
            linux: LinuxNotificationDetails(),
            windows: WindowsNotificationDetails(),
          ),
        );
      } catch (e) {
        debugPrint('Could not schedule reminder: $e');
        wanted.remove(entry.key);
      }
    }
    await _prefs.setStringList(_key, [for (final id in wanted.keys) '$id']);
  }

  /// Cancels every reminder this app scheduled.
  Future<void> clear() async {
    if (!available) return;
    for (final s in _prefs.getStringList(_key) ?? const <String>[]) {
      final id = int.tryParse(s);
      if (id == null) continue;
      try {
        await _plugin.cancel(id: id);
      } catch (_) {}
    }
    await _prefs.remove(_key);
  }
}
