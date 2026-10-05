import '../note_images.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/note.dart';

class NoteRevision {
  const NoteRevision(this.savedAt, this.note);
  final DateTime savedAt;
  final Note note;
}

class NoteHistoryStore {
  NoteHistoryStore(this.directory);
  final Directory directory;

  /// Versions kept per note (Settings -> Data).
  int limit = 100;
  Future<void> _tail = Future.value();
  final _lastRecorded = <String, DateTime>{};
  File _file(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid note ID');
    }
    return File(p.join(directory.path, '$id.json'));
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<List<NoteRevision>> read(String id) => _enqueue(() => _read(id));
  Future<List<NoteRevision>> _read(String id) async {
    final file = _file(id);
    if (!await file.exists()) return [];
    final raw = jsonDecode(await file.readAsString()) as List;
    return raw
        .map(
          (r) => NoteRevision(
            DateTime.parse(r['savedAt'] as String),
            NoteImages.compact(
              Note.fromJson(Map<String, dynamic>.from(r['note'] as Map)),
            ),
          ),
        )
        .toList();
  }

  Future<void> record(Note note, {bool force = false}) => _enqueue(() async {
    final cached = _lastRecorded[note.id];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached) < const Duration(minutes: 1)) {
      return;
    }
    final revisions = await _read(note.id);
    if (revisions.isNotEmpty &&
        revisions.last.note.title == note.title &&
        revisions.last.note.body == note.body &&
        revisions.last.note.coverImage == note.coverImage) {
      return;
    }
    final now = DateTime.now();
    final last = _lastRecorded[note.id] ?? revisions.lastOrNull?.savedAt;
    // Keep a checkpoint each minute instead of hundreds of keystroke saves.
    if (!force &&
        last != null &&
        now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    revisions.add(NoteRevision(now, note));
    if (revisions.length > limit) {
      revisions.removeRange(0, revisions.length - limit);
    }
    await directory.create(recursive: true);
    final file = _file(note.id);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode([
        for (final r in revisions)
          {'savedAt': r.savedAt.toIso8601String(), 'note': r.note.toJson()},
      ]),
      flush: true,
    );
    await temp.rename(file.path);
    _lastRecorded[note.id] = now;
  });
  Future<void> delete(String id) => _enqueue(() async {
    final file = _file(id);
    for (final path in [file.path, '${file.path}.tmp']) {
      final candidate = File(path);
      if (await candidate.exists()) await candidate.delete();
    }
    _lastRecorded.remove(id);
  });
  Future<void> restore(String id, List<NoteRevision> revisions) =>
      _enqueue(() async {
        await directory.create(recursive: true);
        final file = _file(id);
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(
          jsonEncode([
            for (final r in revisions.take(limit))
              {'savedAt': r.savedAt.toIso8601String(), 'note': r.note.toJson()},
          ]),
          flush: true,
        );
        await tmp.rename(file.path);
      });
}
