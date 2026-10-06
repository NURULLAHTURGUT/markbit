import 'package:markbit/features/runner/run_panel.dart';
import 'package:markbit/features/editor/preview/code_block_view.dart';
import 'package:markbit/app/app.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:markbit/application/ai_notifier.dart';
import 'package:markbit/domain/ai/ai_client.dart';
import 'package:markbit/features/ai/ai_panel.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/application/runner_notifier.dart';
import 'package:markbit/application/collections.dart';
import 'package:markbit/application/persistence_coordinator.dart';
import 'package:markbit/application/data_reset.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/models/library_models.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/data/repository/chat_store.dart';
import 'package:markbit/data/backup_service.dart';
import 'package:markbit/data/models/app_settings.dart';
import 'package:markbit/data/note_attachment_service.dart';
import 'package:markbit/domain/markdown_utils.dart';
import 'package:markbit/domain/note_tasks.dart';
import 'package:markbit/features/editor/note_editor.dart';
import 'package:markbit/features/settings/settings_dialog.dart';
import 'package:markbit/features/sidebar/sidebar.dart';
import 'package:markbit/features/dialogs/task_dashboard.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/l10n/app_strings.dart';

Note sample(String id, {String title = 'Title', String body = 'Text'}) => Note(
  id: id,
  title: title,
  body: body,
  notebookId: 'general',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class CaptureAi extends AiClient {
  CaptureAi() : super(baseUrl: 'http://test', model: 'test');
  List<ChatMessage> sent = [];
  StreamController<String>? pending;
  @override
  Stream<String> streamChat(List<ChatMessage> messages) {
    sent = messages;
    return pending?.stream ?? Stream.value('Comparison ready.');
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SharedPreferences prefs;
  late FileLibraryRepository repo;
  late ProviderContainer c;
  late CaptureAi ai;
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    var complete = false;
    c.read(persistenceProvider).flush().then((_) => complete = true);
    for (var i = 0; i < 100 && !complete; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(complete, isTrue);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('markbit_features_');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ai = CaptureAi();
    prefs = await SharedPreferences.getInstance();
    repo = await FileLibraryRepository.open(root: root);
    c = ProviderContainer(
      overrides: [
        aiClientFactoryProvider.overrideWithValue((_, _) => ai),
        aiModelsProvider.overrideWith((ref) async => []),
        sharedPrefsProvider.overrideWithValue(prefs),
        libraryRepositoryProvider.overrideWithValue(repo),
        initialLibraryProvider.overrideWithValue(
          LibrarySnapshot(
            notes: [
              sample('one'),
              sample('two', title: 'Second'),
            ],
            notebooks: [
              const Notebook(id: 'general', name: 'General', isInbox: true),
            ],
            tags: [
              const Tag(id: 'tag', name: 'Project', colorValue: 0xFF123456),
            ],
            templates: [],
            isFresh: false,
          ),
        ),
        chatStoreProvider.overrideWithValue(PreferenceChatStore(prefs)),
      ],
    );
    AppStrings.current = AppStrings(const Locale('en'));
  });
  tearDown(() async {
    await c.read(persistenceProvider).flush();
    c.dispose();
    await root.delete(recursive: true);
  });
  test(
    'tabs persist across sessions and close active to remaining note',
    () async {
      final nav = c.read(openNoteProvider.notifier);
      nav.open('one');
      nav.open('two');
      nav.split('one');
      expect(c.read(openNoteProvider).tabs, ['one', 'two']);
      expect(c.read(openNoteProvider).secondaryId, 'one');
      nav.closeTab('two');
      expect(c.read(openNoteIdProvider), 'one');
      await c.read(persistenceProvider).flush();
      expect(prefs.getStringList('note_tabs_v1'), ['one']);
    },
  );
  test('saved collections survive notifier recreation', () async {
    c
        .read(collectionsProvider.notifier)
        .save(
          const SavedCollection('col', 'Python tasks', 'lang:python has:tasks'),
        );
    await c.read(persistenceProvider).flush();
    c.invalidate(collectionsProvider);
    expect(c.read(collectionsProvider).single.query, 'lang:python has:tasks');
  });
  test(
    'rename binds legacy links and ID links survive a duplicate title',
    () async {
      final lib = c.read(libraryProvider.notifier);
      lib.updateContent('two', body: '[[Title|Go]]');
      expect(c.read(libraryProvider).notes['two']!.body, '[[id:one|Go]]');
      lib.updateContent('one', title: 'Changed');
      lib.createNote(title: 'Changed');
      expect(c.read(libraryProvider).findNoteIdByTitle('id:one'), 'one');
      expect(
        c
            .read(libraryProvider)
            .backlinksTo(c.read(libraryProvider).notes['one']!)
            .single
            .id,
        'two',
      );
    },
  );
  test('binding does not edit fenced or inline source code', () {
    final text = '[[Title]]\n`[[Title]]`\n```dart\n[[Title]]\n```';
    expect(
      bindWikiLinks(text, (_) => 'one'),
      '[[id:one|Title]]\n`[[Title]]`\n```dart\n[[Title]]\n```',
    );
  });
  test('tasks ignore code and preserve metadata when toggled', () {
    final n = sample('one', body: '- [ ] Do work\n```md\n- [ ] example\n```');
    final t = noteTasks(n).single;
    final due = DateTime(2026, 11, 2, 12);
    final updated = n.copyWith(
      body: changeTask(n, t, id: 'task-one', due: due, setDate: true),
    );
    final dated = noteTasks(updated).single;
    expect(dated.due, due);
    expect(dated.id, 'task-one');
    final completed = updated.copyWith(
      body: changeTask(updated, dated, done: true),
    );
    expect(noteTasks(completed).single.done, isTrue);
    expect(noteTasks(completed).single.due, due);
  });
  test('daily note is idempotent and templates carry defaults and files', () {
    final lib = c.read(libraryProvider.notifier);
    final first = lib.dailyNote();
    expect(lib.dailyNote().id, first.id);
    const file = NoteAttachment(name: 'doc.pdf', data: 'YWJj', size: 3);
    final t = lib.saveTemplate(
      name: 'Meeting',
      title: 'Meeting {{date}}',
      body: '{{time}} {{title}}',
      notebookId: 'general',
      tagIds: ['tag'],
      images: {'image': 'data:image/png;base64,YWJj'},
      attachments: {'file': file},
    );
    final n = lib.createFromTemplate(t)!;
    expect(
      n.title,
      contains(DateTime.now().toIso8601String().substring(0, 10)),
    );
    expect(n.tagIds, ['tag']);
    expect(n.images, t.images);
    expect(n.attachments['file']!.name, 'doc.pdf');
  });
  test(
    'attachments and durable links survive backup with remapped IDs',
    () async {
      final lib = c.read(libraryProvider.notifier);
      lib.updateContent(
        'one',
        attachments: {
          'file': const NoteAttachment(name: 'a.txt', data: 'YWJj', size: 3),
        },
      );
      lib.updateContent('two', body: '[[Title]]');
      final t = lib.saveTemplate(
        name: 'Doc',
        body: '[[id:one|Title]]',
        notebookId: 'general',
        tagIds: ['tag'],
        attachments: c.read(libraryProvider).notes['one']!.attachments,
      );
      final raw = await BackupService.encode(
        c.read(libraryProvider),
        const AppSettings(),
        PreferenceChatStore(prefs),
        prefs,
      );
      final restored = BackupService.decode(raw, 'general');
      final a = restored.library.notes.firstWhere((n) => n.title == 'Title');
      final b = restored.library.notes.firstWhere((n) => n.title == 'Second');
      expect(a.attachments['file']!.data, 'YWJj');
      expect(b.body, '[[id:${a.id}|Title]]');
      expect(
        restored.library.templates.single.attachments['file']!.data,
        t.attachments['file']!.data,
      );
    },
  );
  test('file attachment export produces relative portable files', () async {
    final file = File('${root.path}/source.pdf');
    await file.writeAsBytes([1, 2, 3]);
    final a = await NoteAttachmentService.read(file.path);
    final n = sample(
      'one',
      body: '[source](markbit://attachment/file)',
    ).copyWith(attachments: {'file': a});
    final body = await NoteAttachmentService.exportBody(
      n,
      File('${root.path}/export.md'),
    );
    expect(body, '[source](export-files/file-source.pdf)');
    expect(
      await File('${root.path}/export-files/file-source.pdf').readAsBytes(),
      [1, 2, 3],
    );
  });
  testWidgets('delete all data wipes notes, settings and keys, then restarts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var restarted = false;
    final scope = ProviderContainer(
      parent: c,
      overrides: [
        appRestartProvider.overrideWithValue(() async => restarted = true),
      ],
    );
    addTearDown(scope.dispose);
    await tester.runAsync(() async {
      await repo.saveNote(sample('one'));
      await c.read(settingsStoreProvider).setAiApiKey('secret-key');
      await prefs.setString('note_tabs_marker', 'x');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSettingsDialog(context, initialTab: 4),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('delete-all-data'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('delete-all-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('delete-all-understood')));
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    for (var i = 0; i < 100 && !restarted; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(restarted, isTrue);
    final left = root.listSync().map(
      (e) => e.path.split(RegExp(r'[\\/]')).last,
    );
    expect(left, ['notes']);
    expect(Directory('${root.path}/notes').listSync(), isEmpty);
    expect(prefs.getKeys(), isEmpty);
    expect(c.read(settingsStoreProvider).aiApiKey, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('focus mode never hides navigation without an open note', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    c.read(notesOverviewProvider.notifier).set(false);
    c.read(openNoteProvider.notifier).open('one');
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MarkbitApp()),
    );
    await tester.pumpAndSettle();
    double sidebarWidth() => tester
        .getSize(
          find
              .ancestor(
                of: find.byType(Sidebar),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        )
        .width;
    expect(sidebarWidth(), greaterThan(0));

    c.read(focusModeProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(sidebarWidth(), 0);

    // Closing the last tab leaves focus mode and brings navigation back.
    c.read(openNoteProvider.notifier).closeTab('one');
    await tester.pumpAndSettle();
    expect(c.read(openNoteIdProvider), isNull);
    expect(c.read(focusModeProvider), isFalse);
    expect(sidebarWidth(), greaterThan(0));

    // Turning focus mode on with nothing open does not hide anything.
    c.read(focusModeProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(sidebarWidth(), greaterThan(0));
    c.read(focusModeProvider.notifier).set(false);
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('app shortcuts work after the editor loses focus', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MarkbitApp()),
    );
    await tester.pumpAndSettle();
    Future<void> ctrl(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    // Focus a text field, then drop focus the way a click outside does.
    final field = find.byType(EditableText).first;
    await tester.tap(field);
    await tester.pump();
    tester.widget<EditableText>(field).focusNode.unfocus();
    await tester.pump();
    await ctrl(LogicalKeyboardKey.comma);
    expect(find.byType(SettingsView), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsView), findsNothing);
    // Nothing focused at all: the palette still opens.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await ctrl(LogicalKeyboardKey.keyK);
    expect(find.text('New code note (JavaScript)'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('save failure uses the top notification and retry still saves', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MarkbitApp()),
    );
    await tester.pumpAndSettle();
    var fail = true;
    final persistence = c.read(persistenceProvider);
    persistence.write('notice-test', () async {
      if (fail) throw StateError('Disk full');
    });
    await tester.pumpAndSettle();
    expect(persistence.error, isNotNull);
    expect(find.byKey(const ValueKey('app-notification')), findsOneWidget);
    final notice = tester.getRect(
      find.byKey(const ValueKey('app-notification')),
    );
    expect(notice.top, lessThan(60));
    expect(notice.width, lessThanOrEqualTo(460));
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(persistence.error, isNull);
    expect(find.byKey(const ValueKey('app-notification')), findsNothing);
    expect(tester.takeException(), isNull);
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  test('focused editor shortcuts and run output remain note specific', () {
    c.read(openNoteProvider.notifier).open('one');
    c.read(openNoteProvider.notifier).split('two');
    c.read(noteUiProvider('one'));
    c.read(noteUiProvider('two'));
    c.read(editorFocusProvider.notifier).set('two');
    c.read(viewModeProvider.notifier).set(ViewMode.preview);
    expect(c.read(noteUiProvider('two')).mode, ViewMode.preview);
    expect(c.read(noteUiProvider('one')).mode, ViewMode.split);
    c.read(aiPanelVisibleProvider.notifier).toggle();
    expect(c.read(noteUiProvider('two')).ai, isTrue);
    expect(c.read(noteUiProvider('one')).ai, isFalse);
    c.read(aiPanelVisibleProvider.notifier).toggle();
    expect(c.read(noteUiProvider('two')).ai, isFalse);
    c.read(outlineVisibleProvider.notifier).toggle();
    expect(c.read(noteUiProvider('two')).outline, isTrue);
    expect(c.read(noteUiProvider('one')).outline, isFalse);
    c.read(noteRunnerProvider('two').notifier).setStdin('Right input');
    c.read(noteRunnerProvider('two').notifier).showPanel();
    expect(c.read(noteRunnerProvider('one')).stdin, isEmpty);
    expect(c.read(noteRunnerProvider('one')).panelVisible, isFalse);
    expect(c.read(noteRunnerProvider('two')).panelVisible, isTrue);
  });
  testWidgets(
    'side by side modes AI context and insertion use the clicked note',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      c.read(openNoteProvider.notifier).open('one');
      c.read(openNoteProvider.notifier).split('two');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.dark),
            home: const Scaffold(body: EditorPane()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder pane(String id) =>
          find.byWidgetPredicate((w) => w is NoteEditor && w.noteId == id);
      Finder tool(String id, String label) =>
          find.descendant(of: pane(id), matching: find.byTooltip(label));
      await tester.tap(tool('one', 'Preview'));
      await tester.pumpAndSettle();
      expect(c.read(noteUiProvider('one')).mode, ViewMode.preview);
      expect(c.read(noteUiProvider('two')).mode, ViewMode.split);
      await tester.tap(tool('two', 'Editor'));
      await tester.pumpAndSettle();
      expect(c.read(noteUiProvider('one')).mode, ViewMode.preview);
      expect(c.read(noteUiProvider('two')).mode, ViewMode.edit);
      for (final label in ['Split view', 'Preview', 'Editor']) {
        await tester.tap(tool('two', label));
        await tester.pumpAndSettle();
        expect(c.read(noteUiProvider('one')).mode, ViewMode.preview);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(tool('two', 'AI assistant'));
      await tester.pumpAndSettle();
      expect(tester.widget<AiPanel>(find.byType(AiPanel)).noteId, 'two');
      expect(c.read(noteUiProvider('one')).ai, isFalse);
      expect(c.read(activeEditorNoteIdProvider), 'two');
      await tester.enterText(
        find.byKey(const ValueKey('ai-input')),
        'Explain this note',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pumpAndSettle();
      expect(
        ai.sent.any(
          (m) =>
              m.content.contains('currently editing this note') &&
              m.content.contains('Second'),
        ),
        isTrue,
      );
      expect(c.read(aiProvider('one')).items, isEmpty);
      expect(c.read(aiProvider('two')).items, hasLength(2));
      await tester.tap(find.text('Insert into note'));
      await tester.pumpAndSettle();
      expect(
        c.read(libraryProvider).notes['two']!.body,
        contains('Comparison ready.'),
      );
      expect(c.read(libraryProvider).notes['one']!.body, 'Text');
      expect(tester.takeException(), isNull);
      await drain(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
  testWidgets(
    'chat scrollbar extent is stable and streaming respects reading position',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await prefs.setString(
        'ai_chats_v1_one',
        jsonEncode({
          'activeId': 'history',
          'conversations': [
            {
              'id': 'history',
              'title': 'Scroll history',
              'items': [
                for (var i = 0; i < 24; i++)
                  {
                    'role': i.isEven ? 'user' : 'assistant',
                    'text': i.isEven
                        ? 'Question $i'
                        : '## Answer $i\n\n${List.filled(8 + i, 'A paragraph with variable height.').join(' ')}',
                  },
              ],
            },
          ],
        }),
      );
      ai.pending = StreamController<String>();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.dark),
            home: Scaffold(
              body: AiPanel(
                noteId: 'one',
                noteContext: () => 'Title',
                onInsert: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final view = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('ai-message-scroll')),
      );
      final scroll = view.controller!;
      final extent = scroll.position.maxScrollExtent;
      expect(extent, greaterThan(2000));
      expect(scroll.position.extentAfter, lessThan(1));
      for (final fraction in [.1, .7, .3]) {
        scroll.jumpTo(extent * fraction);
        await tester.pumpAndSettle();
        expect(scroll.position.maxScrollExtent, closeTo(extent, .01));
        expect(scroll.offset, closeTo(extent * fraction, .01));
      }
      expect(find.byKey(const ValueKey('ai-jump-to-latest')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-jump-to-latest')));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));
      expect(find.byKey(const ValueKey('ai-jump-to-latest')), findsNothing);
      // Drag the actual thumb from the bottom, not just the controller.
      final rect = tester.getRect(
        find.byKey(const ValueKey('ai-message-scroll')),
      );
      final thumb = await tester.startGesture(
        Offset(rect.right - 3, rect.bottom - 12),
        kind: PointerDeviceKind.mouse,
      );
      await thumb.moveBy(const Offset(0, -110));
      await thumb.up();
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, greaterThan(80));
      expect(scroll.position.maxScrollExtent, closeTo(extent, .01));
      await tester.tap(find.byKey(const ValueKey('ai-jump-to-latest')));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));
      await tester.enterText(
        find.byKey(const ValueKey('ai-input')),
        'New question',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump(const Duration(milliseconds: 50));
      ai.pending!.add('A streaming response. ');
      await tester.pump(const Duration(milliseconds: 80));
      scroll.jumpTo(300);
      await tester.pump(const Duration(milliseconds: 300));
      ai.pending!.add(List.filled(30, 'More content.').join(' '));
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.offset, closeTo(300, .01));
      await ai.pending!.close();
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(300, .01));
      expect(find.byKey(const ValueKey('ai-jump-to-latest')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-jump-to-latest')));
      await tester.pumpAndSettle();
      expect(scroll.position.extentAfter, lessThan(1));
      expect(tester.takeException(), isNull);
      await drain(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
    variant: TargetPlatformVariant({TargetPlatform.windows}),
  );
  testWidgets('side by side note title fields share the same top edge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    c.read(openNoteProvider.notifier).open('one');
    c.read(openNoteProvider.notifier).split('two');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.dark),
          home: const Scaffold(body: EditorPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == 'Title',
    );
    final second = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == 'Second',
    );
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
    expect(find.text('Second'), findsNWidgets(1));
    expect(tester.takeException(), isNull);
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('AI composer fits narrow panels in light dark and glass themes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final palette in [Palettes.light, Palettes.dark, Palettes.glassDark]) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.build(palette),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 280,
                  child: AiPanel(
                    noteId: 'one',
                    width: 280,
                    noteContext: () => 'Current note',
                    noteBody: () => 'Text',
                    onInsert: (_) {},
                    onClose: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final composer = tester.getRect(
        find.byKey(const ValueKey('ai-composer')),
      );
      final input = tester.getRect(find.byKey(const ValueKey('ai-input')));
      final send = tester.getRect(find.byTooltip('Send'));
      expect(composer.contains(input.topLeft), isTrue);
      expect(composer.contains(send.bottomRight), isTrue);
      expect(send.top, greaterThanOrEqualTo(input.bottom));
      expect(tester.takeException(), isNull);
    }
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets(
    'AI sends chosen reference note separately from editable current note',
    (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.dark),
            home: Scaffold(
              body: AiPanel(
                noteId: 'one',
                noteContext: () => 'Current note',
                noteBody: () => 'Current body',
                onInsert: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add context'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose source notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Second'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-input')),
        'Compare notes',
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();
      expect(
        ai.sent.any(
          (m) =>
              m.content.contains('Additional reference notes') &&
              m.content.contains('Second'),
        ),
        isTrue,
      );
      expect(
        ai.sent.any(
          (m) =>
              m.content.contains('currently editing this note') &&
              m.content.contains('Current note'),
        ),
        isTrue,
      );
      await drain(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
  testWidgets('Ctrl V pastes plain text when clipboard has no image', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pasteboard'),
          (call) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('pasteboard'), null),
    );
    c.read(openNoteProvider.notifier).open('one');
    c.read(viewModeProvider.notifier).set(ViewMode.edit);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.dark),
          home: const Scaffold(body: EditorPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.maxLines == null,
    );
    await tester.tap(field);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async =>
              call.method == 'Clipboard.getData' ? {'text': ' pasted'} : null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field).controller!.text,
      contains('pasted'),
    );
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('clipboard image becomes a short portable attachment link', (
    tester,
  ) async {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    final image = File('${root.path}/clipboard.png');
    await tester.runAsync(() => image.writeAsBytes(base64Decode(png)));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('pasteboard'),
          // Like the plugin: a temporary file on Windows, bytes elsewhere.
          (call) async => call.method != 'image'
              ? null
              : Platform.isWindows
              ? image.path
              : base64Decode(png),
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('pasteboard'), null),
    );
    c.read(openNoteProvider.notifier).open('one');
    c.read(viewModeProvider.notifier).set(ViewMode.edit);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.dark),
          home: const Scaffold(body: EditorPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is TextField && w.maxLines == null),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    for (
      var i = 0;
      i < 100 && c.read(libraryProvider).notes['one']!.images.isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final n = c.read(libraryProvider).notes['one']!;
    expect(n.images, hasLength(1));
    expect(n.body, contains('attachment:'));
    expect(n.body, isNot(contains('base64')));
    expect(n.body.length, lessThan(120));
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('dropped PDF is attached with a short link', (tester) async {
    final file = File('${root.path}/manual.pdf');
    await tester.runAsync(() => file.writeAsBytes([1, 2, 3]));
    c.read(openNoteProvider.notifier).open('one');
    c.read(viewModeProvider.notifier).set(ViewMode.edit);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.dark),
          home: const Scaffold(body: EditorPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final target = tester.widget<DropTarget>(find.byType(DropTarget));
    target.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile(file.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    for (
      var i = 0;
      i < 100 && c.read(libraryProvider).notes['one']!.attachments.isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final n = c.read(libraryProvider).notes['one']!;
    expect(n.attachments.values.single.name, 'manual.pdf');
    expect(n.body, contains('markbit://attachment/'));
    expect(tester.takeException(), isNull);
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('short window keeps covered notes from overflowing the split', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    c.read(openNoteProvider.notifier).open('one');
    c.read(openNoteProvider.notifier).open('two');
    c.read(openNoteProvider.notifier).split('one');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.byId('glass')),
          home: const Scaffold(body: EditorPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditor), findsOneWidget);
    expect(find.text('Open second note'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets(
    'two editors preserve separate content in narrow Glass workspace',
    (tester) async {
      tester.view.physicalSize = const Size(700, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      c.read(openNoteProvider.notifier).open('one');
      c.read(openNoteProvider.notifier).open('two');
      c.read(openNoteProvider.notifier).split('one');
      c.read(viewModeProvider.notifier).set(ViewMode.edit);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.byId('glass-dark')),
            home: const Scaffold(body: EditorPane()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await drain(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
    },
  );
  testWidgets('task dashboard stays usable on small Glass window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 580);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    c
        .read(libraryProvider.notifier)
        .updateContent('one', body: '- [ ] Do work');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.byId('glass')),
          home: const Scaffold(body: TaskDashboard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Do work'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      noteTasks(c.read(libraryProvider).notes['one']!).single.done,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await drain(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets(
    'SQL code block Run uses the existing output panel without a dialog',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      c
          .read(libraryProvider.notifier)
          .updateContent(
            'one',
            body:
                "```sql\nCREATE TABLE Calisanlar(id INTEGER, ad TEXT);\n```\n\n```sql\nINSERT INTO Calisanlar VALUES(1,'Ahmet'),(2,'Mehmet');\n```\n\n```sql\nSELECT * FROM Calisanlar;\n```",
          );
      c.read(openNoteProvider.notifier).open('one');
      c.read(noteUiProvider('one').notifier).mode(ViewMode.preview);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.dark),
            home: const Scaffold(body: EditorPane()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> click(int index) async {
        final block = find.byType(CodeBlockView).at(index);
        final button = find.descendant(of: block, matching: find.text('Run'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        for (
          var i = 0;
          i < 100 && c.read(noteRunnerProvider('one')).isBusy;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(
          c.read(noteRunnerProvider('one')).result?.success,
          true,
          reason: c.read(noteRunnerProvider('one').notifier).outputText,
        );
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(RunPanel), findsOneWidget);
      }

      await click(0);
      await click(1);
      await click(2);
      final output = c.read(noteRunnerProvider('one').notifier).outputText;
      expect(output, contains('Ahmet'));
      expect(output, contains('Mehmet'));
      expect(c.read(noteRunnerProvider('two')).panelVisible, false);
      expect(tester.takeException(), isNull);
      await drain(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
