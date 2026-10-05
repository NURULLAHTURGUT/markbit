import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:markbit/application/persistence_coordinator.dart';
import 'package:markbit/application/ai_notifier.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/data/backup_service.dart';
import 'package:markbit/data/export_service.dart';
import 'package:markbit/data/models/app_settings.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/repository/chat_store.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/data/repository/settings_store.dart';
import 'package:markbit/data/seed.dart';
import 'package:markbit/domain/ai/ai_client.dart';
import 'package:markbit/domain/ai/ai_attachment.dart';
import 'package:markbit/features/editor/code_text_editor.dart';
import 'package:markbit/features/notelist/note_list_pane.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class _IdleClient extends http.BaseClient {
  final controller = StreamController<List<int>>();
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(controller.stream, 200);
  @override
  void close() {
    closed = true;
    controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SharedPreferences prefs;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('markbit_reliability_');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'chat drafts retain text and attachments across switching and reload',
    () async {
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      final notifier = container.read(aiProvider('drafts').notifier);
      final first = container.read(aiProvider('drafts')).activeId!;
      const attachment = AiAttachment(
        name: 'draft.png',
        mime: 'image/png',
        data: 'AQID',
        size: 3,
      );
      notifier.saveDraft('Unsent first message', [attachment]);
      notifier.newChat();
      notifier.saveDraft('Second draft', []);
      notifier.selectChat(first);
      expect(
        container.read(aiProvider('drafts')).active.draft!.text,
        'Unsent first message',
      );
      await notifier.flush();
      final store = FileChatStore(Directory(p.join(root.path, 'draft-chats')));
      final raw = await container.read(chatStoreProvider).read('drafts');
      await store.write('drafts', jsonDecode(raw!) as Map<String, dynamic>);
      expect(
        await store.file('drafts').readAsString(),
        isNot(contains('AQID')),
      );
      final restored =
          jsonDecode((await store.read('drafts'))!) as Map<String, dynamic>;
      final chats = (restored['conversations'] as List)
          .map(
            (c) => AiConversation.fromJson(Map<String, dynamic>.from(c as Map)),
          )
          .toList();
      expect(chats.first.draft!.attachments.single.data, 'AQID');
      expect(chats.last.draft!.text, 'Second draft');
      container.dispose();
    },
  );

  test('opening either side panel closes the competing panel', () {
    final container = ProviderContainer();
    container.read(aiPanelVisibleProvider.notifier).set(true);
    expect(container.read(noteListVisibleProvider), isFalse);
    container.read(noteListVisibleProvider.notifier).toggle();
    expect(container.read(noteListVisibleProvider), isTrue);
    expect(container.read(aiPanelVisibleProvider), isFalse);
    container.read(aiPanelVisibleProvider.notifier).set(true);
    expect(container.read(noteListVisibleProvider), isFalse);
    container.dispose();
  });

  testWidgets('covered note tile keeps its thumbnail and title visible', (
    tester,
  ) async {
    final snapshot = (await tester.runAsync(
      () async => loadOrSeed(await FileLibraryRepository.open(root: root)),
    ))!;
    final note = snapshot.notes.first.copyWith(
      title: 'Covered note',
      coverImage: base64Encode(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aE1sAAAAASUVORK5CYII=',
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          initialLibraryProvider.overrideWithValue(snapshot),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Palettes.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: NoteTile(note: note, selected: false, onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Covered note'), findsOneWidget);
    expect(tester.getSize(find.byType(Image)).height, 56);
  });

  test(
    'empty trash removes covered notes and chats without a save failure',
    () async {
      final repo = await FileLibraryRepository.open(root: root);
      final snapshot = await loadOrSeed(repo);
      final chats = FileChatStore(Directory(p.join(root.path, 'chats')));
      await chats.migrate(prefs);
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(repo),
          initialLibraryProvider.overrideWithValue(snapshot),
          chatStoreProvider.overrideWithValue(chats),
        ],
      );
      addTearDown(container.dispose);
      final library = container.read(libraryProvider.notifier);
      final note = library.createNote(title: 'Delete this');
      await library.setCover(
        note.id,
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aE1sAAAAASUVORK5CYII=',
      );
      await chats.write(note.id, {
        'activeId': 'c',
        'conversations': [
          {'id': 'c', 'title': 'Conversation', 'items': []},
        ],
      });
      final persistence = container.read(persistenceProvider);
      await persistence.flush();
      library.trash(note.id);
      library.emptyTrash();
      expect(container.exists(aiProvider(note.id)), isFalse);
      await persistence.flush(retry: false);
      expect(persistence.error, isNull);
      expect((await repo.load()).notes.any((n) => n.id == note.id), isFalse);
      expect(await chats.read(note.id), isNull);
    },
  );

  test('chat reads and permanent deletion are serialized', () async {
    final chats = FileChatStore(Directory(p.join(root.path, 'chats')));
    await chats.write('note', {
      'activeId': 'c',
      'conversations': [
        {'id': 'c', 'title': 'Conversation', 'items': []},
      ],
    });
    final reading = chats.read('note');
    final deleting = chats.delete('note');
    expect(await reading, contains('Conversation'));
    await deleting;
    expect(await chats.read('note'), isNull);
  });

  test(
    'corrupt legacy chats are reported without preventing other chat migrations',
    () async {
      final store = FileChatStore(Directory(p.join(root.path, 'chats')));
      await prefs.setString('ai_chats_v1_bad', '{broken');
      await prefs.setString(
        'ai_chats_v1_good',
        jsonEncode({
          'activeId': 'c',
          'conversations': [
            {'id': 'c', 'title': 'C', 'items': []},
          ],
        }),
      );
      await store.migrate(prefs);
      expect(store.migrationWarnings, hasLength(1));
      expect(prefs.containsKey('ai_chats_v1_bad'), isTrue);
      expect(prefs.containsKey('ai_chats_v1_good'), isFalse);
      expect(await store.read('good'), contains('C'));
      await expectLater(store.read('bad'), throwsFormatException);
    },
  );

  test('failed writes remain visible, retry, and prevent closing', () async {
    final coordinator = PersistenceCoordinator();
    var failing = true;
    await coordinator.write('note:1', () async {
      if (failing) throw const FileSystemException('disk full');
    });
    expect(coordinator.error, isNotNull);
    expect(await coordinator.prepareClose(), isFalse);
    failing = false;
    expect(await coordinator.prepareClose(), isTrue);
    expect(coordinator.error, isNull);
  });

  test(
    'closing flushes editor changes and waits for disk completion',
    () async {
      final coordinator = PersistenceCoordinator();
      final gate = Completer<void>();
      var scheduled = false;
      coordinator.registerEditor('editor', () {
        if (!scheduled) {
          scheduled = true;
          coordinator.write('note', () => gate.future);
        }
      });
      var closed = false;
      final closing = coordinator.prepareClose().then(
        (value) => closed = value,
      );
      await Future<void>.delayed(Duration.zero);
      expect(scheduled, isTrue);
      expect(closed, isFalse);
      gate.complete();
      await closing;
      expect(closed, isTrue);
    },
  );

  test(
    'repository propagates disk failure and later writes still work',
    () async {
      final repo = await FileLibraryRepository.open(root: root);
      await Directory(p.join(root.path, 'notes')).delete();
      final note = Note(
        id: 'n',
        title: 'T',
        body: 'B',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await expectLater(
        repo.saveNote(note),
        throwsA(isA<FileSystemException>()),
      );
      await Directory(p.join(root.path, 'notes')).create();
      await repo.saveNote(note);
      expect((await repo.load()).notes.single.body, 'B');
    },
  );

  test(
    'damaged notes recover the last valid backup and preserve the damaged original',
    () async {
      final repo = await FileLibraryRepository.open(root: root);
      final n = Note(
        id: 'n',
        title: 'T',
        body: 'first',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      );
      await repo.saveNote(n);
      await repo.saveNote(n.copyWith(body: 'second'));
      final file = File(p.join(root.path, 'notes', 'n.json'));
      await file.writeAsString('{broken');
      expect((await repo.load()).notes.single.body, 'first');
      expect(await File('${file.path}.corrupt').readAsString(), '{broken');
      expect(repo.loadWarnings.value, isNotEmpty);
      await repo.deleteNote('n');
      expect((await repo.load()).notes, isEmpty);
    },
  );

  test(
    'legacy keys migrate to secure storage and disappear from preferences',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      await prefs.setString('secret_ai_api_key', 'test-secret');
      final store = SettingsStore(prefs);
      await store.initialize();
      expect(store.aiApiKey, 'test-secret');
      expect(prefs.containsKey('secret_ai_api_key'), isFalse);
      expect(
        await const FlutterSecureStorage().read(key: 'secret_ai_api_key'),
        isNull,
      );
      await store.setAiApiKey('updated');
      expect(
        jsonDecode(
          (await const FlutterSecureStorage().read(key: 'secret_ai_keys_v2'))!,
        )['https://api.openai.com/v1'],
        'updated',
      );
    },
  );

  test('AI stream inactivity times out and releases the client', () async {
    final transport = _IdleClient();
    final ai = AiClient(
      baseUrl: 'http://test',
      model: 'test',
      idleTimeout: const Duration(milliseconds: 20),
      createClient: () => transport,
    );
    await expectLater(
      ai.streamChat([const ChatMessage(ChatRole.user, 'hello')]).toList(),
      throwsA(isA<AiException>()),
    );
    expect(transport.closed, isTrue);
  });

  test(
    'file chats externalize binary attachments, restore them, and delete all copies',
    () async {
      final store = FileChatStore(Directory(p.join(root.path, 'chats')));
      final payload = {
        'activeId': 'c',
        'conversations': [
          {
            'id': 'c',
            'title': 'C',
            'items': [
              {
                'role': 'user',
                'text': 'image',
                'attachments': [
                  {
                    'name': 'x.png',
                    'mime': 'image/png',
                    'data': 'AQID',
                    'size': 3,
                    'text': null,
                  },
                ],
              },
            ],
          },
        ],
      };
      await store.write('n', payload);
      expect(await store.file('n').readAsString(), isNot(contains('AQID')));
      expect(await store.read('n'), contains('AQID'));
      await store.delete('n');
      expect(await store.read('n'), isNull);
      expect(
        await Directory(
          p.join(store.directory.path, 'attachments', 'n'),
        ).exists(),
        isFalse,
      );
      await store.write('n', payload);
      expect(
        await store.read('n'),
        isNull,
      ); // A late disposed notifier cannot resurrect data.
    },
  );

  test(
    'exports avoid existing files and imports preserve nested notebooks and dates',
    () async {
      final repo = await FileLibraryRepository.open(
        root: Directory(p.join(root.path, 'library')),
      );
      final snapshot = await loadOrSeed(repo);
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(repo),
          initialLibraryProvider.overrideWithValue(snapshot),
        ],
      );
      addTearDown(container.dispose);
      final library = container.read(libraryProvider.notifier);
      final parent = library.createNotebook('Parent');
      final child = library.createNotebook('Child', parentId: parent.id);
      library.createNote(notebookId: child.id, title: 'Same', body: 'original');
      await container.read(persistenceProvider).flush();
      final destination = Directory(p.join(root.path, 'export'));
      await ExportService.exportAll(
        container.read(libraryProvider),
        destination.path,
      );
      final original = File(
        p.join(destination.path, 'Parent', 'Child', 'Same.md'),
      );
      final before = await original.readAsString();
      await ExportService.exportAll(
        container.read(libraryProvider),
        destination.path,
      );
      expect(await original.readAsString(), before);
      expect(
        await File(
          p.join(destination.path, 'Parent', 'Child', 'Same (2).md'),
        ).exists(),
        isTrue,
      );
      expect(ExportService.safeName('..'), 'Untitled');
      expect(ExportService.safeName('CON.txt'), '_CON.txt');
      final dated = File(p.join(destination.path, 'dated.md'));
      await dated.writeAsString(
        '---\r\ntitle: "Date"\r\ncreated: 2020-01-01T00:00:00Z\r\nupdated: 2021-01-01T00:00:00Z\r\ntags: ["one, two"]\r\n---\r\nbody',
      );
      await ExportService.importFolder(
        library,
        container.read(libraryProvider),
        destination.path,
      );
      final date = container
          .read(libraryProvider)
          .notes
          .values
          .firstWhere((n) => n.title == 'Date');
      expect(date.createdAt, DateTime.utc(2020));
      expect(date.updatedAt, DateTime.utc(2021));
      expect(
        date.notebookId,
        snapshot.notebooks.firstWhere((n) => n.isInbox).id,
      );
      expect(date.body, 'body');
      expect(
        container.read(libraryProvider).tag(date.tagIds.single)!.name,
        'one, two',
      );
      final imported = container
          .read(libraryProvider)
          .notes
          .values
          .where((n) => n.title == 'Same')
          .last;
      expect(
        container.read(libraryProvider).notebookPath(imported.notebookId),
        'Parent / Child',
      );
      await container.read(persistenceProvider).flush();
    },
  );

  test(
    'full backup carries covers, trash, chats and settings without secrets',
    () async {
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
      final notifier = container.read(libraryProvider.notifier);
      final n = notifier.createNote(title: 'Backup', body: 'body');
      await notifier.setCover(
        n.id,
        base64Encode(Uint8List.fromList([1, 2, 3])),
      );
      notifier.trash(n.id);
      final chats = PreferenceChatStore(prefs);
      await chats.write(n.id, {
        'activeId': 'c',
        'conversations': [
          {'id': 'c', 'title': 'Hello', 'items': []},
        ],
      });
      await prefs.setString('secret_ai_api_key', 'excluded-secret');
      final raw = await BackupService.encode(
        container.read(libraryProvider),
        const AppSettings(themeId: 'zen-glass'),
        chats,
        prefs,
      );
      expect(raw, isNot(contains('excluded-secret')));
      final restored = BackupService.decode(
        raw,
        snapshot.notebooks.firstWhere((n) => n.isInbox).id,
      );
      final copied = restored.library.notes.firstWhere(
        (n) => n.title == 'Backup',
      );
      expect(copied.id, isNot(n.id));
      expect(copied.coverImage, 'AQID');
      expect(copied.trashed, isTrue);
      expect(restored.chats.containsKey(copied.id), isTrue);
      expect(restored.settings.themeId, 'zen-glass');
      await container.read(persistenceProvider).flush();
    },
  );

  test(
    '3000-note searches remain correct and body edits do not rebuild sidebar counts',
    () async {
      final repo = await FileLibraryRepository.open(root: root);
      final seeded = await loadOrSeed(repo);
      final notes = List.generate(
        3000,
        (i) => Note(
          id: 'n$i',
          title: 'Note $i',
          body: 'entry $i',
          notebookId: seeded.notebooks.first.id,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
      final snapshot = LibrarySnapshot(
        notes: notes,
        notebooks: seeded.notebooks,
        tags: seeded.tags,
        templates: seeded.templates,
        isFresh: false,
      );
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(repo),
          initialLibraryProvider.overrideWithValue(snapshot),
        ],
      );
      addTearDown(container.dispose);
      var countUpdates = 0;
      container.listen(sidebarCountsProvider, (_, _) => countUpdates++);
      expect(container.read(sidebarCountsProvider).all, 3000);
      container.read(searchTextProvider.notifier).set('"entry 2999"');
      expect(container.read(visibleNotesProvider).single.id, 'n2999');
      container
          .read(libraryProvider.notifier)
          .updateContent('n2999', body: 'changed');
      expect(container.read(visibleNotesProvider), isEmpty);
      expect(container.read(sidebarCountsProvider).all, 3000);
      expect(countUpdates, 0);
      await container.read(persistenceProvider).flush();
    },
  );

  testWidgets('trash keyboard shortcuts cannot change text', (tester) async {
    final controller = TextEditingController(text: 'original');
    final focus = FocusNode();
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: Scaffold(
          body: CodeTextEditor(
            controller: controller,
            focusNode: focus,
            scrollController: scroll,
            metrics: EditorMetrics(),
            fontSize: 14,
            showLineNumbers: true,
            isCode: false,
            readOnly: true,
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(controller.text, 'original');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focus.dispose();
    scroll.dispose();
  });
}
