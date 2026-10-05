import '../note_images.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

import '../models/library_models.dart';
import '../models/note.dart';
import 'note_history_store.dart';

class LibrarySnapshot {
  const LibrarySnapshot({
    required this.notes,
    required this.notebooks,
    required this.tags,
    required this.templates,
    required this.isFresh,
  });

  final List<Note> notes;
  final List<Notebook> notebooks;
  final List<Tag> tags;
  final List<NoteTemplate> templates;

  /// True when no library existed on disk yet (first launch).
  final bool isFresh;
}

/// A library file changed by another program (sync client, editor, script).
sealed class ExternalChange {
  const ExternalChange();
}

class ExternalNoteChanged extends ExternalChange {
  const ExternalNoteChanged(this.note);
  final Note note;
}

class ExternalNoteRemoved extends ExternalChange {
  const ExternalNoteRemoved(this.id);
  final String id;
}

class ExternalMetaChanged extends ExternalChange {
  const ExternalMetaChanged({
    required this.notebooks,
    required this.tags,
    required this.templates,
  });
  final List<Notebook> notebooks;
  final List<Tag> tags;
  final List<NoteTemplate> templates;
}

/// Persistence boundary for the note library.
abstract interface class LibraryRepository {
  /// Human readable storage location (shown in settings).
  String get location;

  Future<LibrarySnapshot> load();
  Future<void> saveNote(Note note);
  Future<void> deleteNote(String id);
  Future<void> saveMeta({
    required List<Notebook> notebooks,
    required List<Tag> tags,
    required List<NoteTemplate> templates,
  });
}

/// One JSON file per note plus a `meta.json`. Plain files keep the library
/// portable, diffable and trivially backed-up; writes are atomic and
/// serialised so rapid edits can never interleave.
class FileLibraryRepository implements LibraryRepository {
  FileLibraryRepository(this.root)
    : _notesDir = Directory(p.join(root.path, 'notes')),
      _metaFile = File(p.join(root.path, 'meta.json'));

  final Directory root;
  late final history = NoteHistoryStore(
    Directory(p.join(root.path, 'history')),
  );
  final Directory _notesDir;
  final File _metaFile;
  Future<void> _tail = Future.value();
  final ValueNotifier<List<String>> loadWarnings = ValueNotifier([]);
  final List<String> _warnings = [];
  void reportRecoveryIssue(String message) {
    _warnings.add(message);
    loadWarnings.value = List.unmodifiable(_warnings);
  }

  final Map<String, String> _coverReferences = {};

  /// Last content this process wrote per file, so the folder watcher can
  /// tell its own writes from changes made by other programs.
  final Map<String, String> _written = {};
  final Set<String> _deleted = {};
  static String _key(String path) => p.canonicalize(path);

  File _noteFile(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid note ID');
    }
    return File(p.join(_notesDir.path, '$id.json'));
  }

  Future<void> _releaseCover(String? reference) async {
    if (reference == null ||
        !reference.startsWith('file:') ||
        _coverReferences.containsValue(reference) ||
        _warnings.isNotEmpty) {
      return;
    }
    final file = File.fromUri(Uri.parse(reference));
    if (!p.isWithin(p.join(root.absolute.path, 'covers'), file.absolute.path)) {
      return;
    }
    if (await file.exists()) await file.delete();
  }

  /// Images live outside note JSON so editing text does not rewrite megabytes.
  Future<String?> storeCover(String? data) async {
    if (data == null || data.startsWith('file:')) return data;
    final bytes = await compute(base64Decode, data);
    final folder = Directory(p.join(root.path, 'covers'));
    await folder.create(recursive: true);
    final target = File(p.join(folder.path, '${sha256.convert(bytes)}.png'));
    if (!await target.exists()) {
      final temporary = File('${target.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    }
    return target.uri.toString();
  }

  Future<Map<String, dynamic>?> _readRecoverable(File file) async {
    Object? failure;
    for (final candidate in [
      file,
      File('${file.path}.tmp'),
      File('${file.path}.bak'),
    ]) {
      if (!await candidate.exists()) continue;
      try {
        final decoded =
            jsonDecode(await candidate.readAsString()) as Map<String, dynamic>;
        // Check model validity before considering a recovery successful.
        if (file.path != _metaFile.path) {
          final note = Note.fromJson(decoded);
          if (_noteFile(note.id).path != file.path) {
            throw const FormatException('Note ID does not match its filename');
          }
        } else {
          _list(decoded['notebooks'], Notebook.fromJson);
          _list(decoded['tags'], Tag.fromJson);
          _list(decoded['templates'], NoteTemplate.fromJson);
        }
        if (candidate.path != file.path) {
          if (await file.exists()) await file.copy('${file.path}.corrupt');
          final content = jsonEncode(decoded);
          _written[_key(file.path)] = content;
          await file.writeAsString(content, flush: true);
          _warnings.add('Recovered: ${file.path}');
        }
        return decoded;
      } catch (e) {
        failure = e;
      }
    }
    if (failure != null) _warnings.add('${file.path}: $failure');
    return null;
  }

  static Future<FileLibraryRepository> open({Directory? root}) async {
    final base =
        root ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'Markbit'),
        );
    await Directory(p.join(base.path, 'notes')).create(recursive: true);
    return FileLibraryRepository(base);
  }

  @override
  String get location => root.path;

  @override
  Future<LibrarySnapshot> load() async {
    _warnings.clear();
    _coverReferences.clear();
    var notebooks = <Notebook>[];
    var tags = <Tag>[];
    var templates = <NoteTemplate>[];
    final fresh =
        !await _metaFile.exists() &&
        !await File('${_metaFile.path}.tmp').exists() &&
        !await File('${_metaFile.path}.bak').exists();

    if (!fresh) {
      try {
        final j = await _readRecoverable(_metaFile);
        if (j == null) {
          throw const FormatException('Unreadable library metadata');
        }
        notebooks = _list(j['notebooks'], Notebook.fromJson);
        tags = _list(j['tags'], Tag.fromJson);
        templates = _list(j['templates'], NoteTemplate.fromJson);
      } catch (e) {
        _warnings.add('meta.json: $e');
      }
    }

    final files = await _notesDir
        .list()
        .where(
          (e) =>
              e is File &&
              (e.path.endsWith('.json') ||
                  e.path.endsWith('.json.tmp') ||
                  e.path.endsWith('.json.bak')),
        )
        .cast<File>()
        .toList();
    final primaryFiles = files
        .map((f) => File(f.path.replaceFirst(RegExp(r'\.(tmp|bak)$'), '')))
        .map((f) => f.path)
        .toSet()
        .map(File.new)
        .toList();
    final notes = <Note>[];
    const batch = 64;
    for (var i = 0; i < primaryFiles.length; i += batch) {
      final slice = primaryFiles.skip(i).take(batch);
      final loaded = await Future.wait(slice.map(_readNote));
      notes.addAll(loaded.whereType<Note>());
    }

    loadWarnings.value = List.unmodifiable(_warnings);
    return LibrarySnapshot(
      notes: notes,
      notebooks: notebooks,
      tags: tags,
      templates: templates,
      isFresh: fresh,
    );
  }

  Future<Note?> _readNote(File f) async {
    try {
      final json = await _readRecoverable(f);
      if (json == null) return null;
      var note = NoteImages.compact(Note.fromJson(json));
      if (_noteFile(note.id).path != f.path) {
        throw const FormatException('Note ID does not match its filename');
      }
      if (note.coverImage != null && !note.coverImage!.startsWith('file:')) {
        try {
          note = note.copyWith(coverImage: await storeCover(note.coverImage));
          await _writeAtomic(f, jsonEncode(note.toJson()));
        } catch (e) {
          _warnings.add('Cover recovery: ${f.path}: $e');
        }
      }
      if (note.body != json['body']) {
        try {
          await _writeAtomic(f, jsonEncode(note.toJson()));
        } catch (e) {
          _warnings.add('Image conversion: ${f.path}: $e');
        }
      }
      if (note.coverImage != null) _coverReferences[note.id] = note.coverImage!;
      return note;
    } catch (e) {
      _warnings.add('${f.path}: $e');
      return null;
    }
  }

  List<T> _list<T>(Object? raw, T Function(Map<String, dynamic>) parse) =>
      ((raw as List?) ?? const [])
          .map((e) => parse(e as Map<String, dynamic>))
          .toList();

  @override
  Future<void> saveNote(Note note) => _enqueue(() async {
    final previous = _noteFile(note.id);
    if (await previous.exists()) {
      try {
        final old = Note.fromJson(
          jsonDecode(await previous.readAsString()) as Map<String, dynamic>,
        );
        // Locked notes keep no history: a revision would be ciphertext that
        // cannot be restored as text, and older plain revisions were removed
        // when the note was locked.
        if (!old.isLocked &&
            !note.isLocked &&
            (old.body != note.body ||
                old.title != note.title ||
                old.coverImage != note.coverImage)) {
          await history.record(old);
        }
      } on FormatException {
        /* Preserve corrupt originals through atomic recovery. */
      }
    }
    await _writeAtomic(_noteFile(note.id), jsonEncode(note.toJson()));
    if (note.coverImage != null) {
      _coverReferences[note.id] = note.coverImage!;
    } else {
      _coverReferences.remove(note.id);
    }
    // Previous versions may still refer to an old cover; keep it for recovery.
  });

  @override
  Future<void> deleteNote(String id) => _enqueue(() async {
    await history.delete(id);
    final f = _noteFile(id);
    final oldCover = _coverReferences[id];
    _deleted.add(_key(f.path));
    _written.remove(_key(f.path));
    for (final suffix in ['', '.tmp', '.bak', '.corrupt']) {
      final copy = File('${f.path}$suffix');
      if (await copy.exists()) await copy.delete();
    }
    _coverReferences.remove(id);
    await _releaseCover(oldCover);
  });

  @override
  Future<void> saveMeta({
    required List<Notebook> notebooks,
    required List<Tag> tags,
    required List<NoteTemplate> templates,
  }) => _enqueue(
    () => _writeAtomic(
      _metaFile,
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'notebooks': notebooks.map((e) => e.toJson()).toList(),
        'tags': tags.map((e) => e.toJson()).toList(),
        'templates': templates.map((e) => e.toJson()).toList(),
      }),
    ),
  );

  Future<void> _writeAtomic(File target, String content) async {
    _written[_key(target.path)] = content;
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await target.exists()) {
      try {
        jsonDecode(await target.readAsString());
        await target.copy('${target.path}.bak');
      } on FormatException {
        await target.copy('${target.path}.corrupt');
      }
    }
    await tmp.rename(target.path);
  }

  /// Completes when all queued writes have hit the disk.
  Future<void> flush() => _tail;

  /// Deletes everything stored under [root]: notes, metadata, covers,
  /// versions and chats. The folder itself stays, so a watcher on it does
  /// not break. Returns the paths that could not be removed.
  Future<List<String>> wipe() async {
    final failed = <String>[];
    await _enqueue(() async {
      if (await root.exists()) {
        await for (final entity in root.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
          } on FileSystemException {
            failed.add(entity.path);
          }
        }
      }
      _written.clear();
      _deleted.clear();
      _coverReferences.clear();
      await _notesDir.create(recursive: true);
    });
    return failed;
  }

  /// Reports note and metadata files changed by other programs. Events are
  /// debounced per file and compared with what this process wrote, so the
  /// app's own saves are never reported.
  Stream<ExternalChange> watchExternalChanges({
    Duration debounce = const Duration(milliseconds: 400),
  }) {
    if (!FileSystemEntity.isWatchSupported) return const Stream.empty();
    final notesDir = _key(_notesDir.path);
    final meta = _key(_metaFile.path);
    final timers = <String, Timer>{};
    StreamSubscription<FileSystemEvent>? events;
    late final StreamController<ExternalChange> controller;
    void schedule(String path) {
      final key = _key(path);
      final watched =
          key == meta || (p.dirname(key) == notesDir && key.endsWith('.json'));
      if (!watched) return;
      timers[key]?.cancel();
      timers[key] = Timer(debounce, () async {
        timers.remove(key);
        final change = await _inspect(path, key, isMeta: key == meta);
        if (change != null && !controller.isClosed) controller.add(change);
      });
    }

    controller = StreamController<ExternalChange>(
      onListen: () {
        events = root.watch(recursive: true).listen(
          (event) {
            schedule(event.path);
            if (event is FileSystemMoveEvent && event.destination != null) {
              schedule(event.destination!);
            }
          },
          // A watcher failure must not take the app down; changes are
          // still picked up at the next launch.
          onError: (Object _) {},
        );
      },
      onCancel: () async {
        for (final timer in timers.values) {
          timer.cancel();
        }
        timers.clear();
        await events?.cancel();
      },
    );
    return controller.stream;
  }

  Future<ExternalChange?> _inspect(
    String path,
    String key, {
    required bool isMeta,
  }) async {
    // Let queued writes from this process land before comparing.
    await _tail;
    final file = File(path);
    if (!await file.exists()) {
      if (_deleted.remove(key) || isMeta) return null;
      // An atomic save replaces the file in two steps; wait for it.
      if (await File('$path.tmp').exists()) return null;
      _written.remove(key);
      return ExternalNoteRemoved(p.basenameWithoutExtension(path));
    }
    final String content;
    try {
      content = await file.readAsString();
    } on FileSystemException {
      return null;
    }
    if (_written[key] == content) return null;
    try {
      final json = jsonDecode(content) as Map<String, dynamic>;
      if (isMeta) {
        final change = ExternalMetaChanged(
          notebooks: _list(json['notebooks'], Notebook.fromJson),
          tags: _list(json['tags'], Tag.fromJson),
          templates: _list(json['templates'], NoteTemplate.fromJson),
        );
        _written[key] = content;
        return change;
      }
      final note = NoteImages.compact(Note.fromJson(json));
      if (_key(_noteFile(note.id).path) != key) return null;
      _written[key] = content;
      _deleted.remove(key);
      if (note.coverImage != null) _coverReferences[note.id] = note.coverImage!;
      return ExternalNoteChanged(note);
    } catch (_) {
      // Half-written by the other program; its next event retries.
      return null;
    }
  }

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _tail.then((_) => op());
    _tail = next.catchError((Object _) {});
    return next;
  }
}
