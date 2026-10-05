import 'dart:convert';

import '../domain/markdown_utils.dart';
import '../core/l10n/app_strings.dart';
import 'package:flutter/foundation.dart';
import '../data/note_images.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_palette.dart';
import '../core/util/ids.dart';
import '../data/models/library_models.dart';
import '../data/models/note.dart';
import 'providers.dart';
import 'ai_notifier.dart';
import 'note_vault.dart';
import '../domain/note_crypto.dart';
import '../domain/template_variables.dart';
import 'persistence_coordinator.dart';
import '../data/repository/library_repository.dart';
import '../data/repository/chat_store.dart';
import '../data/seed.dart';

/// Immutable in-memory view of the whole library.
class Library {
  const Library({
    required this.notes,
    required this.notebooks,
    required this.tags,
    required this.templates,
  });

  final Map<String, Note> notes;
  final List<Notebook> notebooks;
  final List<Tag> tags;
  final List<NoteTemplate> templates;

  Notebook? notebook(String? id) {
    if (id == null) return null;
    for (final n in notebooks) {
      if (n.id == id) return n;
    }
    return null;
  }

  Tag? tag(String id) {
    for (final t in tags) {
      if (t.id == id) return t;
    }
    return null;
  }

  Tag? tagByName(String name) {
    final lower = name.toLowerCase();
    for (final t in tags) {
      if (t.name.toLowerCase() == lower) return t;
    }
    return null;
  }

  Notebook get inbox =>
      notebooks.firstWhere((n) => n.isInbox, orElse: () => notebooks.first);

  List<Notebook> childrenOf(String? parentId) =>
      notebooks.where((n) => n.parentId == parentId && !n.isInbox).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// The notebook itself plus all nested notebooks.
  Set<String> descendantIds(String id) {
    final out = <String>{id};
    var frontier = <String>[id];
    while (frontier.isNotEmpty) {
      final next = <String>[];
      for (final n in notebooks) {
        if (n.parentId != null &&
            frontier.contains(n.parentId) &&
            out.add(n.id)) {
          next.add(n.id);
        }
      }
      frontier = next;
    }
    return out;
  }

  String notebookPath(String? id) {
    final parts = <String>[];
    var cur = notebook(id);
    var guard = 0;
    while (cur != null && guard++ < 16) {
      parts.insert(0, cur.name);
      cur = notebook(cur.parentId);
    }
    return parts.join(' / ');
  }

  String? findNoteIdByTitle(String title) {
    if (title.startsWith('id:')) {
      final id = title.substring(3);
      return notes[id]?.trashed == false ? id : null;
    }
    final lower = title.trim().toLowerCase();
    for (final n in notes.values) {
      if (!n.trashed && n.title.trim().toLowerCase() == lower) return n.id;
    }
    return null;
  }

  /// Non-trashed notes that link to [note] with `[[Title]]`.
  List<Note> backlinksTo(Note note) {
    final title = note.title.trim();
    if (title.isEmpty) return const [];
    final needle = RegExp(
      r'\[\[' + RegExp.escape(title) + r'(?:\|[^\]]*)?\]\]',
      caseSensitive: false,
    );
    return notes.values
        .where(
          (n) =>
              !n.trashed &&
              n.id != note.id &&
              (needle.hasMatch(n.body) ||
                  n.body.contains('[[id:${note.id}|') ||
                  n.body.contains('markbit://note/${note.id}')),
        )
        .toList();
  }

  Library copyWith({
    Map<String, Note>? notes,
    List<Notebook>? notebooks,
    List<Tag>? tags,
    List<NoteTemplate>? templates,
  }) => Library(
    notes: notes ?? this.notes,
    notebooks: notebooks ?? this.notebooks,
    tags: tags ?? this.tags,
    templates: templates ?? this.templates,
  );
}

class LibraryNotifier extends Notifier<Library> {
  @override
  Library build() {
    final snap = ref.watch(initialLibraryProvider);
    return Library(
      notes: {for (final n in snap.notes) n.id: n},
      notebooks: snap.notebooks,
      tags: snap.tags,
      templates: snap.templates,
    );
  }

  // ---------------------------------------------------------------- notes

  Note createNote({
    String? notebookId,
    List<String> tagIds = const [],
    NoteStatus status = NoteStatus.none,
    NoteKind kind = NoteKind.markdown,
    String? language,
    String title = '',
    String body = '',
    String? coverImage,
    Map<String, String> images = const {},
    Map<String, NoteAttachment> attachments = const {},
    String? dailyDate,
  }) {
    final now = DateTime.now();
    final note = Note(
      id: newId(),
      title: title,
      body: body,
      coverImage: coverImage,
      images: images,
      attachments: attachments,
      dailyDate: dailyDate,
      notebookId: notebookId ?? state.inbox.id,
      status: status,
      tagIds: tagIds,
      kind: kind,
      language: language,
      createdAt: now,
      updatedAt: now,
    );
    _putNote(note);
    return note;
  }

  /// Where `{{cursor}}` was in a note just created from a template; the
  /// editor places the caret there once and removes the entry.
  final Map<String, int> pendingCursor = {};

  Note? createFromTemplate(NoteTemplate t, {String? notebookId}) {
    final notebook =
        state.notebook(notebookId) ??
        state.notebook(t.notebookId) ??
        state.inbox;
    final now = DateTime.now();
    TemplateContext context(String title) => TemplateContext(
      now: now,
      title: title,
      notebook: notebook.isInbox ? trs('General') : notebook.name,
      language: AppStrings.current.locale.languageCode,
    );
    final title = expandTemplate(t.title, context(t.name)).text.trim();
    final body = expandTemplate(t.body, context(title));
    final note = createNote(
      notebookId: notebook.id,
      title: title,
      body: body.text,
      tagIds: t.tagIds.where((id) => state.tag(id) != null).toList(),
      images: t.images,
      attachments: t.attachments,
    );
    if (body.cursor != null) pendingCursor[note.id] = body.cursor!;
    return note;
  }

  /// Saves edited title/body. Skips the write when nothing changed.
  void updateContent(
    String id, {
    String? title,
    String? body,
    Map<String, String>? images,
    Map<String, NoteAttachment>? attachments,
  }) {
    final n = readable(id);
    if (n == null || n.trashed) return;
    if ((title == null || title == n.title) &&
        (body == null || body == n.body) &&
        (images == null || mapEquals(images, n.images)) &&
        (attachments == null || mapEquals(attachments, n.attachments))) {
      return;
    }
    if (title != null && title != n.title) {
      for (final other in state.notes.values.toList()) {
        if (other.kind != NoteKind.markdown || other.isLocked) continue;
        final linked = bindWikiLinks(other.body, _uniqueTitleId);
        if (linked != other.body && other.id != id) {
          _putNote(other.copyWith(body: linked));
        }
      }
      body = bindWikiLinks(body ?? n.body, _uniqueTitleId);
    }
    _putNote(
      n.copyWith(
        title: title,
        body: body,
        images: images,
        attachments: attachments,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void setImages(String id, Map<String, String> images) =>
      _mutate(id, (n) => n.copyWith(images: images));

  void setNotebook(String id, String? notebookId) =>
      _mutate(id, (n) => n.copyWith(notebookId: notebookId));

  void setStatus(String id, NoteStatus status) =>
      _mutate(id, (n) => n.copyWith(status: status));

  Future<void> setCover(String id, String? image) async {
    final repository = ref.read(libraryRepositoryProvider);
    final persistence = ref.read(persistenceProvider);
    await persistence.write('cover:$id', () async {
      final stored = repository is FileLibraryRepository
          ? await repository.storeCover(image)
          : image;
      if (!ref.mounted || state.notes[id]?.trashed != false) return;
      _mutate(id, (n) => n.copyWith(coverImage: stored));
    });
  }

  void setLanguage(String id, String? language) =>
      _mutate(id, (n) => n.copyWith(language: language));

  void togglePin(String id) =>
      _mutate(id, (n) => n.copyWith(pinned: !n.pinned));

  void toggleStar(String id) =>
      _mutate(id, (n) => n.copyWith(starred: !n.starred));

  /// Moves several notes to [notebookId] (drag and drop).
  void moveNotes(Iterable<String> ids, String notebookId) {
    if (state.notebook(notebookId) == null) return;
    for (final id in ids) {
      if (state.notes[id]?.notebookId != notebookId) {
        setNotebook(id, notebookId);
      }
    }
  }

  /// Adds [tagId] to several notes (drag and drop).
  void tagNotes(Iterable<String> ids, String tagId) {
    for (final id in ids) {
      final n = state.notes[id];
      if (n != null && !n.tagIds.contains(tagId)) toggleTag(id, tagId);
    }
  }

  void toggleTag(String id, String tagId) => _mutate(id, (n) {
    final tags = [...n.tagIds];
    tags.contains(tagId) ? tags.remove(tagId) : tags.add(tagId);
    return n.copyWith(tagIds: tags);
  });

  void trash(String id) => _mutate(
    id,
    (n) => n.copyWith(trashed: true, pinned: false, trashedAt: DateTime.now()),
  );

  void restore(String id) =>
      _mutate(id, (n) => n.copyWith(trashed: false, trashedAt: null));

  void deleteForever(String id) {
    if (!state.notes.containsKey(id)) return;
    final notes = {...state.notes}..remove(id);
    state = state.copyWith(notes: notes);
    _deleteFiles(id);
  }

  /// Permanently deletes notes that have been in the trash longer than
  /// [days]. Trashed notes from before deletion dates were recorded get
  /// today's date, so they are kept for the full period. Returns the number
  /// of deleted notes.
  int purgeExpiredTrash(int days, {DateTime? now}) {
    if (days <= 0) return 0;
    final clock = now ?? DateTime.now();
    final expired = <String>[];
    for (final n in state.notes.values.toList()) {
      if (!n.trashed) continue;
      final since = n.trashedAt;
      if (since == null) {
        _putNote(n.copyWith(trashedAt: clock));
      } else if (clock.difference(since) >= Duration(days: days)) {
        expired.add(n.id);
      }
    }
    if (expired.isEmpty) return 0;
    final notes = {...state.notes};
    for (final id in expired) {
      notes.remove(id);
    }
    state = state.copyWith(notes: notes);
    for (final id in expired) {
      _deleteFiles(id);
    }
    return expired.length;
  }

  void emptyTrash() {
    final ids = state.notes.values
        .where((n) => n.trashed)
        .map((n) => n.id)
        .toList();
    if (ids.isEmpty) return;
    final notes = {...state.notes};
    for (final id in ids) {
      notes.remove(id);
    }
    state = state.copyWith(notes: notes);
    for (final id in ids) {
      _deleteFiles(id);
    }
  }

  void _deleteFiles(String id) {
    ref.read(noteVaultProvider.notifier).forget(id);
    final persistence = ref.read(persistenceProvider);
    persistence.forget('note:$id');
    persistence.forget('cover:$id');
    if (ref.exists(aiProvider(id))) {
      ref.read(aiProvider(id).notifier).deleteNoteData();
    } else {
      // Do not open and read a conversation just to delete it. On Windows that
      // read could hold the file while deletion tries to remove it.
      persistence.forget('chat:$id');
      final chats = ref.read(chatStoreProvider);
      persistence.write('delete-chat:$id', () => chats.delete(id));
    }
    final repository = ref.read(libraryRepositoryProvider);
    persistence.write('delete:$id', () => repository.deleteNote(id));
  }

  Future<void> reloadFromDisk() async {
    await ref.read(persistenceProvider).flush();
    final snapshot = await loadOrSeed(ref.read(libraryRepositoryProvider));
    state = Library(
      notes: {for (final note in snapshot.notes) note.id: note},
      notebooks: snapshot.notebooks,
      tags: snapshot.tags,
      templates: snapshot.templates,
    );
  }

  void importSnapshot(LibrarySnapshot snapshot) {
    for (final note in snapshot.notes) {
      _saveNote(note);
    }
    state = Library(
      notes: {...state.notes, for (final n in snapshot.notes) n.id: n},
      notebooks: [...state.notebooks, ...snapshot.notebooks],
      tags: [...state.tags, ...snapshot.tags],
      templates: [...state.templates, ...snapshot.templates],
    );
    _saveMeta();
  }

  Note? duplicate(String id) {
    final n = state.notes[id];
    if (n == null) return null;
    if (n.isLocked) {
      // Copy the ciphertext as is: the copy opens with the same password.
      final now = DateTime.now();
      final copy = Note(
        id: newId(),
        title: '${n.displayTitle} (copy)',
        body: '',
        notebookId: n.notebookId,
        tagIds: n.tagIds,
        status: n.status,
        kind: n.kind,
        language: n.language,
        coverImage: n.coverImage,
        createdAt: now,
        updatedAt: now,
        lock: n.lock,
      );
      state = state.copyWith(notes: {...state.notes, copy.id: copy});
      _saveNote(copy);
      return copy;
    }
    return createNote(
      notebookId: n.notebookId,
      tagIds: n.tagIds,
      status: n.status,
      kind: n.kind,
      language: n.language,
      title: '${n.displayTitle} (copy)',
      body: n.body,
      coverImage: n.coverImage,
      images: n.images,
      attachments: n.attachments,
    );
  }

  /// Bulk insert used by importers.
  void importNotes(Iterable<Note> notes) {
    final map = {...state.notes};
    for (final n in notes) {
      map[n.id] = n;
      _saveNote(n);
    }
    state = state.copyWith(notes: map);
  }

  // ------------------------------------------------------------ notebooks

  Notebook createNotebook(String name, {String? parentId}) {
    final nb = Notebook(id: newId(), name: name.trim(), parentId: parentId);
    state = state.copyWith(notebooks: [...state.notebooks, nb]);
    _saveMeta();
    return nb;
  }

  void renameNotebook(String id, String name) {
    state = state.copyWith(
      notebooks: [
        for (final n in state.notebooks)
          if (n.id == id && !n.isInbox) n.copyWith(name: name.trim()) else n,
      ],
    );
    _saveMeta();
  }

  /// Nests notebook [id] under [parentId] (null = top level). Refused for the
  /// inbox and when it would put a notebook inside its own subtree.
  bool moveNotebook(String id, String? parentId) {
    final nb = state.notebook(id);
    if (nb == null || nb.isInbox || nb.parentId == parentId) return false;
    if (parentId != null) {
      final parent = state.notebook(parentId);
      if (parent == null || parent.isInbox) return false;
      if (state.descendantIds(id).contains(parentId)) return false;
    }
    state = state.copyWith(
      notebooks: [
        for (final n in state.notebooks)
          if (n.id == id)
            n.copyWith(parentId: parentId, clearParent: parentId == null)
          else
            n,
      ],
    );
    _saveMeta();
    return true;
  }

  /// Deletes a notebook. Nested notebooks and notes move up one level.
  void deleteNotebook(String id) {
    final nb = state.notebook(id);
    if (nb == null || nb.isInbox) return;
    final parent = nb.parentId ?? state.inbox.id;
    final notebooks = [
      for (final n in state.notebooks)
        if (n.id != id)
          if (n.parentId == id)
            n.copyWith(parentId: nb.parentId, clearParent: nb.parentId == null)
          else
            n,
    ];
    final notes = {...state.notes};
    for (final n in state.notes.values) {
      if (n.notebookId == id) {
        final moved = n.copyWith(notebookId: parent);
        notes[n.id] = moved;
        _saveNote(moved);
      }
    }
    state = state.copyWith(notebooks: notebooks, notes: notes);
    _saveMeta();
  }

  // ----------------------------------------------------------------- tags

  Tag createTag(String name, {int? colorValue}) {
    final existing = state.tagByName(name.trim());
    if (existing != null) return existing;
    final color =
        colorValue ??
        AppPalette.tagColors[state.tags.length % AppPalette.tagColors.length]
            .toARGB32();
    final tag = Tag(id: newId(), name: name.trim(), colorValue: color);
    state = state.copyWith(tags: [...state.tags, tag]);
    _saveMeta();
    return tag;
  }

  void updateTag(String id, {String? name, int? colorValue}) {
    final old = state.tag(id)?.name;
    final renamed = name?.trim();
    // Renaming "work" to "jobs" also moves "work/x" to "jobs/x".
    final prefix = old != null && renamed != null && renamed != old
        ? '${old.toLowerCase()}/'
        : null;
    state = state.copyWith(
      tags: [
        for (final t in state.tags)
          if (t.id == id)
            t.copyWith(name: renamed, colorValue: colorValue)
          else if (prefix != null && t.name.toLowerCase().startsWith(prefix))
            t.copyWith(name: '$renamed/${t.name.substring(prefix.length)}')
          else
            t,
      ],
    );
    _saveMeta();
  }

  /// Moves every note from tag [fromId] to [intoId] and deletes [fromId].
  void mergeTags(String fromId, String intoId) {
    if (fromId == intoId ||
        state.tag(fromId) == null ||
        state.tag(intoId) == null) {
      return;
    }
    final notes = {...state.notes};
    for (final n in state.notes.values) {
      if (!n.tagIds.contains(fromId)) continue;
      final ids = [
        for (final t in n.tagIds)
          if (t != fromId) t,
        if (!n.tagIds.contains(intoId)) intoId,
      ];
      final updated = n.copyWith(tagIds: ids);
      notes[n.id] = updated;
      _saveNote(updated);
    }
    state = state.copyWith(
      notes: notes,
      tags: [
        for (final t in state.tags)
          if (t.id != fromId) t,
      ],
    );
    _saveMeta();
  }

  void deleteTag(String id) {
    final notes = {...state.notes};
    for (final n in state.notes.values) {
      if (n.tagIds.contains(id)) {
        final updated = n.copyWith(
          tagIds: n.tagIds.where((t) => t != id).toList(),
        );
        notes[n.id] = updated;
        _saveNote(updated);
      }
    }
    state = state.copyWith(
      tags: state.tags.where((t) => t.id != id).toList(),
      notes: notes,
    );
    _saveMeta();
  }

  // ------------------------------------------------------------ templates

  NoteTemplate saveTemplate({
    String? id,
    required String name,
    String title = '',
    required String body,
    String? notebookId,
    List<String> tagIds = const [],
    Map<String, String> images = const {},
    Map<String, NoteAttachment> attachments = const {},
  }) {
    final t = NoteTemplate(
      id: id ?? newId(),
      name: name.trim(),
      title: title,
      body: body,
      notebookId: notebookId,
      tagIds: tagIds,
      images: images,
      attachments: attachments,
    );
    final exists = state.templates.any((e) => e.id == t.id);
    state = state.copyWith(
      templates: exists
          ? [for (final e in state.templates) e.id == t.id ? t : e]
          : [...state.templates, t],
    );
    _saveMeta();
    return t;
  }

  void deleteTemplate(String id) {
    state = state.copyWith(
      templates: state.templates.where((t) => t.id != id).toList(),
    );
    _saveMeta();
  }

  Note dailyNote() => dailyNoteFor(DateTime.now());

  /// The daily note of [day], created when missing.
  Note dailyNoteFor(DateTime day) {
    final date = DateTime(
      day.year,
      day.month,
      day.day,
    ).toIso8601String().substring(0, 10);
    for (final n in state.notes.values) {
      if (!n.trashed && n.dailyDate == date) return n;
    }
    final nb =
        state.notebooks.where((n) => n.name == 'Daily').firstOrNull ??
        createNotebook('Daily');
    return createNote(
      notebookId: nb.id,
      title: date,
      dailyDate: date,
      body: '# $date\n\n## ${trs('Tasks')}\n- [ ] \n\n## ${trs('Notes')}\n',
    );
  }

  // -------------------------------------------------------------- helpers

  void _mutate(String id, Note Function(Note) fn) {
    final n = readable(id);
    if (n == null) return;
    final updated = fn(n);
    _putNote(updated.copyWith(updatedAt: DateTime.now()));
  }

  String? _uniqueTitleId(String title) {
    final matches = state.notes.values
        .where(
          (n) =>
              !n.trashed &&
              n.title.trim().toLowerCase() == title.trim().toLowerCase(),
        )
        .toList();
    return matches.length == 1 ? matches.single.id : null;
  }

  void _putNote(Note note) {
    note = NoteImages.compact(note);
    if (note.kind == NoteKind.markdown) {
      note = note.copyWith(body: bindWikiLinks(note.body, _uniqueTitleId));
    }
    if (note.isLocked) {
      _putLocked(note);
      return;
    }
    state = state.copyWith(notes: {...state.notes, note.id: note});
    _saveNote(note);
  }

  // ---------------------------------------------------------- locked notes

  /// The note as the user sees it: locked notes that are unlocked include
  /// their decrypted content. The library itself only holds ciphertext.
  Note? readable(String id) {
    final n = state.notes[id];
    if (n == null || !n.isLocked) return n;
    final content = ref.read(noteVaultProvider.notifier).content(id);
    return content == null
        ? n
        : n.copyWith(
            body: content.body,
            images: content.images,
            attachments: content.attachments,
          );
  }

  /// Plaintext never enters the library state or the note file: it goes to
  /// the vault and the file receives a freshly sealed lock.
  void _putLocked(Note note) {
    final vault = ref.read(noteVaultProvider.notifier);
    final stripped = note.copyWith(
      body: '',
      images: const {},
      attachments: const {},
    );
    state = state.copyWith(notes: {...state.notes, note.id: stripped});
    if (!vault.isUnlocked(note.id)) {
      // Metadata change on a locked note: the stored ciphertext stays valid.
      _saveNote(stripped);
      return;
    }
    vault.update(note.id, LockedContent.of(note));
    final sealing = vault.seal(note.id)!;
    final repository = ref.read(libraryRepositoryProvider);
    ref.read(persistenceProvider).write('note:${note.id}', () async {
      final lock = await sealing;
      final current = state.notes[note.id];
      if (!ref.mounted || current == null || !current.isLocked) return;
      final sealed = current.copyWith(lock: lock);
      state = state.copyWith(notes: {...state.notes, note.id: sealed});
      await repository.saveNote(sealed);
    });
  }

  /// Encrypts [id] with [password]. Its version history is deleted because
  /// earlier versions hold the plaintext.
  Future<void> lockNote(
    String id,
    String password, {
    int iterations = NoteCrypto.defaultIterations,
  }) async {
    final n = readable(id);
    if (n == null || n.isLocked) return;
    final vault = ref.read(noteVaultProvider.notifier);
    final content = LockedContent.of(n);
    await vault.adopt(id, password, content, iterations: iterations);
    // Edits saved while the key was being derived are included.
    final latest = readable(id);
    if (latest != null && !latest.isLocked) {
      vault.update(id, LockedContent.of(latest));
    }
    final lock = await vault.seal(id)!;
    if (!ref.mounted) return;
    final current = state.notes[id];
    if (current == null || current.isLocked) return;
    final sealed = current.copyWith(
      body: '',
      images: const {},
      attachments: const {},
      lock: lock,
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(notes: {...state.notes, id: sealed});
    final repository = ref.read(libraryRepositoryProvider);
    await ref.read(persistenceProvider).write('note:$id', () async {
      await repository.saveNote(sealed);
      if (repository is FileLibraryRepository) {
        await repository.history.delete(id);
      }
    });
    vault.lock(id);
  }

  /// Removes the password from an unlocked note and stores it as plain text.
  void removeLock(String id) {
    final n = readable(id);
    final vault = ref.read(noteVaultProvider.notifier);
    if (n == null || !n.isLocked || !vault.isUnlocked(id)) return;
    vault.forget(id);
    _putNote(n.copyWith(lock: null, updatedAt: DateTime.now()));
  }

  // ------------------------------------------------------- external changes

  /// Applies a note file changed by another program. Nothing is written back.
  void applyExternalNote(Note note) {
    final current = state.notes[note.id];
    if (current != null && jsonEncodeNote(current) == jsonEncodeNote(note)) {
      return;
    }
    final vault = ref.read(noteVaultProvider.notifier);
    if (note.isLocked && current?.lock != note.lock) vault.forget(note.id);
    state = state.copyWith(notes: {...state.notes, note.id: note});
  }

  /// A note file was deleted by another program.
  void applyExternalRemoval(String id) {
    if (!state.notes.containsKey(id)) return;
    ref.read(noteVaultProvider.notifier).forget(id);
    state = state.copyWith(notes: {...state.notes}..remove(id));
  }

  /// meta.json was replaced by another program.
  void applyExternalMeta({
    required List<Notebook> notebooks,
    required List<Tag> tags,
    required List<NoteTemplate> templates,
  }) {
    if (notebooks.isEmpty) return;
    state = state.copyWith(
      notebooks: notebooks,
      tags: tags,
      templates: templates,
    );
  }

  void _saveNote(Note note) {
    final repository = ref.read(libraryRepositoryProvider);
    ref
        .read(persistenceProvider)
        .write('note:${note.id}', () => repository.saveNote(note));
  }

  void _saveMeta() {
    final repository = ref.read(libraryRepositoryProvider);
    final snapshot = state;
    ref
        .read(persistenceProvider)
        .write(
          'metadata',
          () => repository.saveMeta(
            notebooks: snapshot.notebooks,
            tags: snapshot.tags,
            templates: snapshot.templates,
          ),
        );
  }
}

/// Canonical JSON of a note, used to compare versions.
String jsonEncodeNote(Note note) => jsonEncode(note.toJson());
