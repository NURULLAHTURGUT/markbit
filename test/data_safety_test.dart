import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:markbit/application/note_vault.dart';
import 'package:markbit/application/persistence_coordinator.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/util/time_ago.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/data/seed.dart';
import 'package:markbit/domain/note_crypto.dart';
import 'package:markbit/features/editor/note_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Low PBKDF2 cost keeps the tests fast; the format is the same.
const _iterations = 1000;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SharedPreferences prefs;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('markbit_safety_');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<(ProviderContainer, FileLibraryRepository)> open() async {
    final repo = await FileLibraryRepository.open(root: root);
    final snapshot = await loadOrSeed(repo);
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        libraryRepositoryProvider.overrideWithValue(repo),
        initialLibraryProvider.overrideWithValue(snapshot),
      ],
    );
    addTearDown(container.dispose);
    return (container, repo);
  }

  Future<String> fileOf(String id) =>
      File(p.join(root.path, 'notes', '$id.json')).readAsString();

  group('trash retention', () {
    test('records the trash date and deletes expired notes', () async {
      final (container, repo) = await open();
      final library = container.read(libraryProvider.notifier);
      final old = library.createNote(title: 'Old');
      final recent = library.createNote(title: 'Recent');
      library.trash(old.id);
      library.trash(recent.id);
      final trashedAt = container
          .read(libraryProvider)
          .notes[old.id]!
          .trashedAt;
      expect(trashedAt, isNotNull);

      final later = trashedAt!.add(const Duration(days: 31));
      expect(library.purgeExpiredTrash(0, now: later), 0);
      expect(library.purgeExpiredTrash(60, now: later), 0);
      expect(library.purgeExpiredTrash(30, now: later), 2);
      await container.read(persistenceProvider).flush();
      final ids = (await repo.load()).notes.map((n) => n.id);
      expect(ids, isNot(contains(old.id)));
      expect(ids, isNot(contains(recent.id)));
    });

    test(
      'restoring clears the date; legacy trash gets a full period',
      () async {
        final (container, _) = await open();
        final library = container.read(libraryProvider.notifier);
        final restored = library.createNote(title: 'Restored');
        library.trash(restored.id);
        library.restore(restored.id);
        expect(
          container.read(libraryProvider).notes[restored.id]!.trashedAt,
          isNull,
        );

        // A note trashed before dates were recorded.
        final legacy = library.createNote(title: 'Legacy');
        library.importNotes([
          container
              .read(libraryProvider)
              .notes[legacy.id]!
              .copyWith(trashed: true),
        ]);
        final now = DateTime(2026, 10, 5);
        expect(library.purgeExpiredTrash(30, now: now), 0);
        final stamped = container.read(libraryProvider).notes[legacy.id]!;
        expect(stamped.trashedAt, now);
        expect(
          library.purgeExpiredTrash(30, now: now.add(const Duration(days: 30))),
          1,
        );
        await container.read(persistenceProvider).flush();
      },
    );

    test('countdown text', () {
      final now = DateTime(2026, 10, 5, 12);
      expect(trashCountdown(now, 0, now: now), isNull);
      expect(
        trashCountdown(now.subtract(const Duration(days: 25)), 30, now: now),
        'Deleted in 5 days',
      );
      expect(
        trashCountdown(now.subtract(const Duration(days: 29)), 30, now: now),
        'Deleted in 1 day',
      );
      expect(
        trashCountdown(
          now.subtract(const Duration(days: 29, hours: 13)),
          30,
          now: now,
        ),
        'Deleted within a day',
      );
    });
  });

  group('locked notes', () {
    test(
      'content is only stored encrypted and opens with the password',
      () async {
        final (container, repo) = await open();
        final library = container.read(libraryProvider.notifier);
        final note = library.createNote(
          title: 'Secrets',
          body: 'the launch code is 4242',
        );
        await container.read(persistenceProvider).flush();
        library.updateContent(note.id, body: 'the launch code is 4242!');
        await container.read(persistenceProvider).flush();
        expect(await repo.history.read(note.id), isNotEmpty);

        await library.lockNote(
          note.id,
          'correct horse',
          iterations: _iterations,
        );
        await container.read(persistenceProvider).flush();

        final stored = await fileOf(note.id);
        expect(stored, isNot(contains('4242')));
        expect(jsonDecode(stored)['lock'], isA<Map>());
        expect(container.read(libraryProvider).notes[note.id]!.body, isEmpty);
        expect(container.read(noteProvider(note.id))!.body, isEmpty);
        // Plain revisions are removed when a note is locked.
        expect(await repo.history.read(note.id), isEmpty);

        final vault = container.read(noteVaultProvider.notifier);
        await expectLater(
          vault.unlock(note.id, 'wrong password'),
          throwsA(isA<WrongPasswordException>()),
        );
        await vault.unlock(note.id, 'correct horse');
        expect(container.read(noteProvider(note.id))!.body, contains('4242!'));

        // Edits are sealed again before they reach the disk.
        library.updateContent(note.id, body: 'moved to vault 7');
        await container.read(persistenceProvider).flush();
        final edited = await fileOf(note.id);
        expect(edited, isNot(contains('vault 7')));
        expect(container.read(libraryProvider).notes[note.id]!.body, isEmpty);

        vault.lock(note.id);
        expect(container.read(noteProvider(note.id))!.body, isEmpty);

        // A fresh load (new session) still opens with the password.
        final reloaded = (await repo.load()).notes.firstWhere(
          (n) => n.id == note.id,
        );
        expect(reloaded.isLocked, isTrue);
        final content = LockedContent.fromJson(
          await NoteCrypto.open(
            await NoteCrypto.deriveKey(
              'correct horse',
              reloaded.lock!.salt,
              reloaded.lock!.iterations,
            ),
            reloaded.lock!,
          ),
        );
        expect(content.body, 'moved to vault 7');
      },
    );

    test('removing the lock stores plain text again', () async {
      final (container, _) = await open();
      final library = container.read(libraryProvider.notifier);
      final note = library.createNote(title: 'Temp', body: 'plain again');
      await library.lockNote(note.id, 'secret pw', iterations: _iterations);
      await container.read(persistenceProvider).flush();
      await container
          .read(noteVaultProvider.notifier)
          .unlock(note.id, 'secret pw');
      library.removeLock(note.id);
      await container.read(persistenceProvider).flush();
      final stored = jsonDecode(await fileOf(note.id)) as Map;
      expect(stored['lock'], isNull);
      expect(stored['body'], 'plain again');
      expect(container.read(noteVaultProvider), isEmpty);
    });

    test('a copy of a locked note stays encrypted', () async {
      final (container, _) = await open();
      final library = container.read(libraryProvider.notifier);
      final note = library.createNote(title: 'Original', body: 'hidden');
      await library.lockNote(note.id, 'secret pw', iterations: _iterations);
      final copy = library.duplicate(note.id)!;
      await container.read(persistenceProvider).flush();
      expect(copy.isLocked, isTrue);
      expect(await fileOf(copy.id), isNot(contains('hidden')));
    });

    testWidgets('a locked note shows its unlock screen, not its content', (
      tester,
    ) async {
      // Rendering only: unlocking is covered above, and key derivation runs
      // on an isolate that cannot finish inside the widget test's fake clock.
      final now = DateTime(2026, 10, 5);
      final note = Note(
        id: 'diary',
        title: 'Diary',
        body: '',
        createdAt: now,
        updatedAt: now,
        lock: NoteLock(
          salt: List.filled(16, 1),
          iterations: _iterations,
          nonce: List.filled(12, 2),
          cipherText: List.filled(8, 3),
          mac: List.filled(16, 4),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(
            FileLibraryRepository(root),
          ),
          initialLibraryProvider.overrideWithValue(
            LibrarySnapshot(
              notes: [note],
              notebooks: [],
              tags: [],
              templates: [],
              isFresh: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.dark),
            home: Scaffold(body: LockedNoteView(noteId: note.id)),
          ),
        ),
      );
      expect(find.text('Diary'), findsOneWidget);
      expect(find.text('This note is locked.'), findsOneWidget);
      expect(find.byKey(const ValueKey('unlock-password')), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      expect(container.read(noteProvider(note.id))!.body, isEmpty);
      expect(tester.takeException(), isNull);
    });
  });

  group('external changes', () {
    test(
      'own saves are ignored, other programs are reported',
      () async {
        final repo = await FileLibraryRepository.open(root: root);
        final changes = <ExternalChange>[];
        final sub = repo
            .watchExternalChanges(debounce: const Duration(milliseconds: 100))
            .listen(changes.add);
        addTearDown(sub.cancel);
        await Future<void>.delayed(const Duration(milliseconds: 200));

        final now = DateTime(2026, 10, 5);
        final note = Note(
          id: 'watched',
          title: 'Watched',
          body: 'from markbit',
          createdAt: now,
          updatedAt: now,
        );
        await repo.saveNote(note);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(changes, isEmpty);

        final file = File(p.join(root.path, 'notes', 'watched.json'));
        await file.writeAsString(
          jsonEncode(note.copyWith(body: 'from a sync client').toJson()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(
          changes.whereType<ExternalNoteChanged>().single.note.body,
          'from a sync client',
        );

        await file.delete();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(changes.whereType<ExternalNoteRemoved>().single.id, 'watched');
      },
      skip: !FileSystemEntity.isWatchSupported,
    );

    test('applying a change does not write it back', () async {
      final (container, repo) = await open();
      final library = container.read(libraryProvider.notifier);
      final note = library.createNote(title: 'Synced', body: 'v1');
      await container.read(persistenceProvider).flush();
      final external = note.copyWith(body: 'v2 from elsewhere');
      library.applyExternalNote(external);
      expect(container.read(noteProvider(note.id))!.body, 'v2 from elsewhere');
      expect(
        container.read(persistenceProvider).isPending('note:${note.id}'),
        isFalse,
      );
      library.applyExternalRemoval(note.id);
      expect(container.read(libraryProvider).notes[note.id], isNull);
      // The repository still holds the last version Markbit wrote.
      expect(jsonDecode(await fileOf(note.id))['body'], 'v1');
      expect(repo.location, root.path);
    });
  });

  group('save state', () {
    test('pending and failed writes are reported per key', () async {
      final persistence = PersistenceCoordinator();
      final gate = Completer<void>();
      final write = persistence.write('note:a', () => gate.future);
      expect(persistence.isPending('note:a'), isTrue);
      expect(persistence.isPending('note:b'), isFalse);
      gate.complete();
      await write;
      expect(persistence.isPending('note:a'), isFalse);
      await persistence.write('note:a', () async => throw StateError('disk'));
      expect(persistence.hasFailed('note:a'), isTrue);
      await persistence.write('note:a', () async {});
      expect(persistence.hasFailed('note:a'), isFalse);
    });
  });
}
