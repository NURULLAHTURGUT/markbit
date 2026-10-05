import 'dart:io';

import 'package:markbit/application/providers.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/data/seed.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  FileLibraryRepository? openRepo;

  Future<FileLibraryRepository> open() async =>
      openRepo = await FileLibraryRepository.open(root: dir);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('markbit_test_');
  });

  tearDown(() async {
    await openRepo?.flush();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('first launch seeds a library and persists it', () async {
    final repo = await open();
    final snap = await loadOrSeed(repo);
    expect(snap.notebooks.any((n) => n.isInbox), isTrue);
    expect(snap.notes, isNotEmpty);

    final again = await repo.load();
    expect(again.isFresh, isFalse);
    expect(again.notes.length, snap.notes.length);
    expect(again.tags.length, snap.tags.length);
  });

  test('note json round trip', () {
    final now = DateTime.utc(2025, 5, 4, 3, 2, 1);
    final n = Note(
      id: 'a',
      title: 'T',
      body: 'B',
      createdAt: now,
      updatedAt: now,
      tagIds: const ['x'],
      kind: NoteKind.code,
      language: 'dart',
      status: NoteStatus.onHold,
      pinned: true,
    );
    final back = Note.fromJson(n.toJson());
    expect(back.toJson(), n.toJson());
  });

  test('library notifier: create, filter, trash, delete', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = await open();
    final snap = await loadOrSeed(repo);

    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        libraryRepositoryProvider.overrideWithValue(repo),
        initialLibraryProvider.overrideWithValue(snap),
      ],
    );
    addTearDown(container.dispose);

    final lib = container.read(libraryProvider.notifier);
    final before = container.read(visibleNotesProvider).length;

    final note = lib.createNote(title: 'Zebra note', body: 'needle');
    expect(container.read(visibleNotesProvider).length, before + 1);

    container.read(searchTextProvider.notifier).set('needle');
    expect(container.read(visibleNotesProvider).map((n) => n.id), [note.id]);
    container.read(searchTextProvider.notifier).set('');

    lib.trash(note.id);
    expect(container.read(visibleNotesProvider).length, before);
    container.read(navFilterProvider.notifier).select(const NavFilter.trash());
    expect(container.read(visibleNotesProvider).single.id, note.id);

    lib.deleteForever(note.id);
    expect(container.read(visibleNotesProvider), isEmpty);
    expect(container.read(libraryProvider).notes.containsKey(note.id), isFalse);

    // Persistence: the deleted note must be gone after reload.
    await repo.flush();
    final reloaded = await repo.load();
    expect(reloaded.notes.any((n) => n.id == note.id), isFalse);
  });

  test('deleting a notebook moves notes up', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = await open();
    final snap = await loadOrSeed(repo);
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        libraryRepositoryProvider.overrideWithValue(repo),
        initialLibraryProvider.overrideWithValue(snap),
      ],
    );
    addTearDown(container.dispose);

    final lib = container.read(libraryProvider.notifier);
    final parent = lib.createNotebook('Parent');
    final child = lib.createNotebook('Child', parentId: parent.id);
    final note = lib.createNote(notebookId: child.id, title: 'x');

    lib.deleteNotebook(child.id);
    final state = container.read(libraryProvider);
    expect(state.notebook(child.id), isNull);
    expect(state.notes[note.id]!.notebookId, parent.id);
  });
}
