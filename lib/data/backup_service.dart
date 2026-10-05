import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../application/library_notifier.dart';
import '../application/ai_notifier.dart';
import '../core/util/ids.dart';
import 'models/app_settings.dart';
import 'models/library_models.dart';
import 'models/note.dart';
import 'repository/chat_store.dart';
import 'repository/library_repository.dart';
import 'repository/note_history_store.dart';

class RestoredBackup {
  const RestoredBackup(
    this.library,
    this.settings,
    this.chats,
    this.preferences, [
    this.history = const {},
  ]);
  final LibrarySnapshot library;
  final AppSettings settings;
  final Map<String, Map<String, dynamic>> chats;
  final Map<String, Object> preferences;
  final Map<String, List<NoteRevision>> history;
}

/// Portable backup. Secrets are deliberately excluded; existing keys stay intact.
abstract final class BackupService {
  static void validateHeader(String raw) {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['format'] != 'markbit-backup' ||
        data['version'] != 1 ||
        data['notes'] is! List) {
      throw const FormatException('Invalid backup');
    }
  }

  static String _remapLinks(String body, Map<String, String> ids) {
    return body
        .replaceAllMapped(
          RegExp(r'\[\[id:([\w-]+)([|\]])'),
          (m) => '[[id:${ids[m[1]] ?? m[1]}${m[2]}',
        )
        .replaceAllMapped(
          RegExp(r'markbit://note/([\w-]+)'),
          (m) => 'markbit://note/${ids[m[1]] ?? m[1]}',
        );
  }

  static bool includedPreference(String key) =>
      key == 'ai_panel_width_v1' ||
      key == 'collections_v1' ||
      key.startsWith('ai_model_capabilities');

  static Future<String> encode(
    Library library,
    AppSettings settings,
    ChatStore chats,
    SharedPreferences prefs, {
    NoteHistoryStore? history,
  }) async {
    final notes = <Map<String, dynamic>>[];
    final conversations = <String, dynamic>{};
    final versions = <String, dynamic>{};
    for (final note in library.notes.values) {
      final json = note.toJson();
      if (note.coverImage?.startsWith('file:') == true) {
        json['coverImage'] = base64Encode(
          await File.fromUri(Uri.parse(note.coverImage!)).readAsBytes(),
        );
      }
      notes.add(json);
      final raw = await chats.read(note.id);
      if (raw != null) conversations[note.id] = jsonDecode(raw);
      if (history != null) {
        final revisions = await history.read(note.id);
        final items = <Map<String, dynamic>>[];
        for (final revision in revisions) {
          final data = revision.note.toJson();
          if (revision.note.coverImage?.startsWith('file:') == true) {
            data['coverImage'] = base64Encode(
              await File.fromUri(
                Uri.parse(revision.note.coverImage!),
              ).readAsBytes(),
            );
          }
          items.add({
            'savedAt': revision.savedAt.toIso8601String(),
            'note': data,
          });
        }
        if (items.isNotEmpty) versions[note.id] = items;
      }
    }
    return compute(jsonEncode, {
      'format': 'markbit-backup',
      'version': 1,
      'notes': notes,
      'notebooks': library.notebooks.map((n) => n.toJson()).toList(),
      'tags': library.tags.map((t) => t.toJson()).toList(),
      'templates': library.templates.map((t) => t.toJson()).toList(),
      'settings': settings.toJson(),
      'chats': conversations,
      'history': versions,
      'preferences': {
        for (final key in prefs.getKeys().where(includedPreference))
          key: prefs.get(key),
      },
    });
  }

  /// Validate everything before any mutation. Restore adds a separate copy,
  /// retaining current notes, even when restoring the same backup twice.
  static RestoredBackup decode(String raw, String generalId) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['format'] != 'markbit-backup' || json['version'] != 1) {
      throw const FormatException('Unsupported backup');
    }
    Map<String, dynamic> map(Object? value) =>
        Map<String, dynamic>.from(value as Map);
    final originalNotes = (json['notes'] as List)
        .map((n) => Note.fromJson(map(n)))
        .toList();
    final originalBooks = (json['notebooks'] as List)
        .map((n) => Notebook.fromJson(map(n)))
        .toList();
    final originalTags = (json['tags'] as List)
        .map((n) => Tag.fromJson(map(n)))
        .toList();
    final originalTemplates = (json['templates'] as List)
        .map((n) => NoteTemplate.fromJson(map(n)))
        .toList();
    void unique(Iterable<String> ids) {
      final values = ids.toList();
      if (values.toSet().length != values.length ||
          values.any((id) => id.isEmpty)) {
        throw const FormatException('Duplicate or empty IDs');
      }
    }

    unique(originalNotes.map((n) => n.id));
    unique(originalBooks.map((n) => n.id));
    unique(originalTags.map((n) => n.id));
    unique(originalTemplates.map((n) => n.id));
    final bookIds = {
      for (final n in originalBooks) n.id: n.isInbox ? generalId : newId(),
    };
    final tagIds = {for (final n in originalTags) n.id: newId()};
    final noteIds = {for (final n in originalNotes) n.id: newId()};
    for (final book in originalBooks) {
      final visited = <String>{book.id};
      var parent = book.parentId;
      while (parent != null) {
        if (!visited.add(parent) || !bookIds.containsKey(parent)) {
          throw const FormatException('Invalid notebook hierarchy');
        }
        parent = originalBooks.firstWhere((b) => b.id == parent).parentId;
      }
    }
    final notes = originalNotes.map((note) {
      if (note.coverImage != null) {
        if (note.coverImage!.startsWith('file:')) {
          throw const FormatException('Non-portable cover');
        }
        base64Decode(note.coverImage!);
      }
      final data = note.toJson();
      data['id'] = noteIds[note.id];
      data['body'] = _remapLinks(note.body, noteIds);
      data['notebookId'] = bookIds[note.notebookId] ?? generalId;
      data['tagIds'] = note.tagIds
          .map((id) => tagIds[id])
          .whereType<String>()
          .toList();
      return Note.fromJson(data);
    }).toList();
    final chats = <String, Map<String, dynamic>>{};
    for (final entry in map(json['chats']).entries) {
      if (!noteIds.containsKey(entry.key)) {
        throw const FormatException('Orphaned conversation');
      }
      final data = map(entry.value);
      for (final chat in data['conversations'] as List) {
        AiConversation.fromJson(map(chat));
      }
      chats[noteIds[entry.key]!] = data;
    }
    final preferences = <String, Object>{};
    final history = <String, List<NoteRevision>>{};
    for (final entry in map(json['history'] ?? {}).entries) {
      final id = noteIds[entry.key];
      if (id == null ||
          entry.value is! List ||
          (entry.value as List).length > 100) {
        throw const FormatException('Invalid version history');
      }
      history[id] = (entry.value as List).map((item) {
        final revision = map(item);
        final old = Note.fromJson(map(revision['note']));
        if (old.coverImage != null) base64Decode(old.coverImage!);
        final data = old.toJson();
        data['id'] = id;
        data['body'] = _remapLinks(old.body, noteIds);
        data['notebookId'] = bookIds[old.notebookId] ?? generalId;
        data['tagIds'] = old.tagIds
            .map((t) => tagIds[t])
            .whereType<String>()
            .toList();
        return NoteRevision(
          DateTime.parse(revision['savedAt'] as String),
          Note.fromJson(data),
        );
      }).toList();
    }
    for (final entry in map(json['preferences'] ?? {}).entries) {
      if (includedPreference(entry.key) && entry.value != null) {
        if (entry.key == 'collections_v1' && entry.value is String) {
          final values = (jsonDecode(entry.value as String) as List).map((e) {
            final data = Map<String, dynamic>.from(e as Map);
            if (data['scope'] == 'notebook') {
              data['scopeId'] = bookIds[data['scopeId']];
            }
            if (data['scope'] == 'tag') {
              data['scopeId'] = tagIds[data['scopeId']];
            }
            return data;
          }).toList();
          preferences[entry.key] = jsonEncode(values);
        } else {
          preferences[entry.key] = entry.value as Object;
        }
      }
    }
    return RestoredBackup(
      LibrarySnapshot(
        notes: notes,
        notebooks: [
          for (final b in originalBooks)
            if (!b.isInbox)
              Notebook(
                id: bookIds[b.id]!,
                name: b.name,
                parentId: bookIds[b.parentId],
              ),
        ],
        tags: [
          for (final t in originalTags)
            Tag(id: tagIds[t.id]!, name: t.name, colorValue: t.colorValue),
        ],
        templates: [
          for (final t in originalTemplates)
            NoteTemplate(
              id: newId(),
              name: t.name,
              title: t.title,
              body: _remapLinks(t.body, noteIds),
              notebookId: bookIds[t.notebookId],
              tagIds: t.tagIds
                  .map((id) => tagIds[id])
                  .whereType<String>()
                  .toList(),
              images: t.images,
              attachments: t.attachments,
            ),
        ],
        isFresh: false,
      ),
      AppSettings.fromJson(map(json['settings'])),
      chats,
      preferences,
      history,
    );
  }
}
