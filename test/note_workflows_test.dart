import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markbit/application/auto_backup.dart';
import 'package:markbit/application/library_notifier.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/data/backup_service.dart';
import 'package:markbit/data/export_service.dart';
import 'package:markbit/application/persistence_coordinator.dart';
import 'package:markbit/data/models/library_models.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/note_import_service.dart';
import 'package:markbit/data/pdf_export_service.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/data/repository/note_history_store.dart';
import 'package:markbit/data/repository/chat_store.dart';
import 'package:markbit/data/models/app_settings.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/features/editor/find_replace_bar.dart';
import 'package:markbit/features/editor/syntax_controller.dart';
import 'package:markbit/features/editor/preview/markdown_preview.dart';
import 'package:markbit/features/notelist/bulk_note_actions.dart';
import 'package:markbit/domain/visual_block.dart';

const pixel =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
Note sample({
  String id = 'n',
  String body = 'Initial',
  String title = 'Türkçe not',
}) => Note(
  id: id,
  title: title,
  body: body,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  notebookId: 'inbox',
);
Library library([List<Note> notes = const []]) => Library(
  notes: {for (final n in notes) n.id: n},
  notebooks: [const Notebook(id: 'inbox', name: 'Inbox', isInbox: true)],
  tags: [],
  templates: [],
);

class _MemoryRepository implements LibraryRepository {
  final notes = <String, Note>{};
  @override
  String get location => 'memory';
  @override
  Future<void> saveNote(Note note) async {
    notes[note.id] = note;
  }

  @override
  Future<void> deleteNote(String id) async {
    notes.remove(id);
  }

  @override
  Future<void> saveMeta({
    required List<Notebook> notebooks,
    required List<Tag> tags,
    required List<NoteTemplate> templates,
  }) async {}
  @override
  Future<LibrarySnapshot> load() async => LibrarySnapshot(
    notes: notes.values.toList(),
    notebooks: [],
    tags: [],
    templates: [],
    isFresh: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SharedPreferences prefs;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('markbit_workflows_');
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'import preview preserves inline and referenced local images and marks repeats',
    () async {
      await File('${root.path}/image.png').writeAsBytes(base64Decode(pixel));
      final markdown = File('${root.path}/one.md');
      await markdown.writeAsString(
        '---\ntitle: "My note"\ntags: ["work"]\n---\n![Inline](image.png)\n\n![Reference][photo]\n[photo]: image.png\n',
      );
      final plan = await NoteImportService.prepare([markdown.path], library());
      expect(plan.files, hasLength(1));
      expect(plan.files.single.note.body, contains('data:image/png;base64,'));
      expect(plan.files.single.note.body, isNot(contains('image.png')));
      expect(plan.files.single.tags, ['work']);
      final again = await NoteImportService.prepare([
        markdown.path,
      ], library([plan.files.single.note]));
      expect(again.files.single.duplicate, isTrue);
      await File('${root.path}/image.png').delete();
      expect(
        Uri.parse(
          RegExp(
            r'\((data:[^)]+)\)',
          ).firstMatch(plan.files.single.note.body)![1]!,
        ).data!.contentAsBytes(),
        base64Decode(pixel),
      );
      final missing = await NoteImportService.prepare([
        markdown.path,
      ], library());
      expect(missing.files.single.warnings, isNotEmpty);
    },
  );

  test(
    'import keeps folder hierarchy and selected export excludes other notes',
    () async {
      final folder = Directory('${root.path}/Work/Projects');
      await folder.create(recursive: true);
      await File('${folder.path}/test.py').writeAsString('print(42)');
      final repo = await FileLibraryRepository.open(
        root: Directory('${root.path}/app'),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(repo),
          initialLibraryProvider.overrideWithValue(
            LibrarySnapshot(
              notes: [],
              notebooks: library().notebooks,
              tags: [],
              templates: [],
              isFresh: false,
            ),
          ),
        ],
      );
      final plan = await NoteImportService.folder(
        '${root.path}/Work',
        library(),
      );
      NoteImportService.apply(
        container.read(libraryProvider.notifier),
        library(),
        plan.files,
      );
      final imported = container.read(libraryProvider).notes.values.single;
      expect(imported.kind, NoteKind.code);
      expect(
        container.read(libraryProvider).notebookPath(imported.notebookId),
        'Projects',
      );
      final exportFolder = '${root.path}/export';
      final count = await ExportService.exportAll(
        library([imported, sample(id: 'other')]),
        exportFolder,
        selectedIds: {imported.id},
      );
      expect(count, 1);
      final exported = await Directory(
        exportFolder,
      ).list(recursive: true).where((e) => e is File).toList();
      expect(exported, hasLength(1));
      expect(
        await File(exported.single.path).readAsString(),
        contains('print(42)'),
      );
      container.dispose();
      await repo.flush();
    },
  );

  test(
    'history records old content, survives reload and travels in full backup',
    () async {
      final repo = await FileLibraryRepository.open(root: root);
      final first = sample();
      await repo.saveNote(first);
      await repo.saveNote(first.copyWith(body: 'Changed'));
      expect((await repo.history.read('n')).single.note.body, 'Initial');
      await repo.history.record(
        first.copyWith(body: 'Before restore'),
        force: true,
      );
      expect(
        (await NoteHistoryStore(
          Directory('${root.path}/history'),
        ).read('n')).last.note.body,
        'Before restore',
      );
      final raw = await BackupService.encode(
        library([first]),
        const AppSettings(),
        PreferenceChatStore(prefs),
        prefs,
        history: repo.history,
      );
      final restored = BackupService.decode(raw, 'inbox');
      expect(restored.history.values.single, hasLength(2));
      expect(restored.history.keys.single, restored.library.notes.single.id);
      await repo.deleteNote('n');
      expect(await repo.history.read('n'), isEmpty);
    },
  );

  test(
    'automatic backup runs once daily and retention keeps unrelated files',
    () async {
      final raw = await BackupService.encode(
        library([sample()]),
        const AppSettings(),
        PreferenceChatStore(prefs),
        prefs,
      );
      final folder = Directory('${root.path}/backups');
      await folder.create();
      await File('${folder.path}/personal.markbit').writeAsString(raw);
      await File(
        '${folder.path}/Markbit-Auto-2020-01-01T00-00-00-000000.markbit',
      ).writeAsString(raw);
      var captures = 0;
      final service = AutoBackup(prefs, () async {
        captures++;
        return raw;
      });
      await service.configure(folder: folder.path, keep: 1);
      await prefs.setBool('auto_backup_enabled', true);
      await service.check();
      await service.check();
      expect(captures, 1);
      expect(await File('${folder.path}/personal.markbit').exists(), isTrue);
      expect(
        await File(
          '${folder.path}/Markbit-Auto-2020-01-01T00-00-00-000000.markbit',
        ).exists(),
        isFalse,
      );
      expect(service.error, isNull);
      service.dispose();
    },
  );

  testWidgets(
    'find and replace treats patterns literally and updates every match',
    (tester) async {
      final controller = SyntaxController(
        text: 'a.b A.B a.b',
        palette: Palettes.light,
      );
      final found = findTextMatches(controller.text, 'a.b');
      expect(found, hasLength(3));
      expect(
        findTextMatches(controller.text, 'a.b', caseSensitive: true),
        hasLength(2),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Palettes.light),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: FindReplaceBar(
                controller: controller,
                replace: true,
                readOnly: false,
                onNavigate: (_) {},
                onChanged: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Find in note'),
        'a.b',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Replace with'),
        'x',
      );
      await tester.tap(find.text('Replace all'));
      await tester.pumpAndSettle();
      expect(controller.text, 'x x x');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets(
    'preview task checkbox maps to its source line outside code fences',
    (tester) async {
      int? line;
      bool? checked;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: AppTheme.build(Palettes.light),
            home: Scaffold(
              body: MarkdownPreview(
                body:
                    'Intro\n\n```txt\n- [ ] code only\n```\n\n- [ ] Actual task',
                resolveNoteId: (_) => null,
                onOpenNote: (_) {},
                onCreateNote: (_) {},
                onRun: (_, code) {},
                onToggleTask: (i, value) {
                  line = i;
                  checked = value;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.byType(Checkbox), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(line, 6);
      expect(checked, isTrue);
    },
  );

  testWidgets('bulk actions select only visible notes and move the selection', (
    tester,
  ) async {
    final repo = _MemoryRepository();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        libraryRepositoryProvider.overrideWithValue(repo),
        initialLibraryProvider.overrideWithValue(
          LibrarySnapshot(
            notes: [
              sample(id: 'a'),
              sample(id: 'b'),
              sample(id: 'c'),
            ],
            notebooks: [
              ...library().notebooks,
              const Notebook(id: 'target', name: 'Target'),
            ],
            tags: [],
            templates: [],
            isFresh: false,
          ),
        ),
      ],
    );
    container.read(noteSelectionProvider.notifier).enable();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.light),
          home: Scaffold(body: BulkNoteActions(visibleIds: ['a', 'b'])),
        ),
      ),
    );
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(container.read(noteSelectionProvider).ids, {'a', 'b'});
    expect(find.text('Deselect all'), findsOneWidget);
    await tester.tap(find.text('Deselect all'));
    await tester.pumpAndSettle();
    expect(container.read(noteSelectionProvider).ids, isEmpty);
    expect(container.read(noteSelectionProvider).enabled, isTrue);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to notebook'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target'));
    await tester.pumpAndSettle();
    expect(container.read(libraryProvider).notes['a']!.notebookId, 'target');
    expect(container.read(libraryProvider).notes['b']!.notebookId, 'target');
    expect(container.read(libraryProvider).notes['c']!.notebookId, 'inbox');
    expect(container.read(noteSelectionProvider).enabled, isFalse);
    expect(repo.notes['a']!.notebookId, 'target');
    expect(repo.notes['b']!.notebookId, 'target');
    await container.read(persistenceProvider).flush();
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  test(
    'PDF renders Turkish text, images, tables, charts and mind maps',
    () async {
      final chart = VisualBlock.fromInput(
        kind: VisualKind.chart,
        title: 'Satış grafiği',
        input: 'Ocak; 20\nŞubat; 40',
      );
      final map = VisualBlock.fromInput(
        kind: VisualKind.mindmap,
        title: 'Plan',
        input: 'Proje\n  Araştırma\n  Geliştirme',
      );
      final body =
          '# Başlık\nTürkçe: ğüşöçı İĞÜŞÖÇ\n\n![Resim](data:image/png;base64,$pixel)\n\n| A | B |\n|---|---|\n| Bir | İki |\n\n${chart.markdown}\n${map.markdown}';
      final bytes = await PdfExportService.generate(sample(body: body));
      expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
      await Directory('build/verification').create(recursive: true);
      await File('build/verification/note-workflows.pdf').writeAsBytes(bytes);
    },
  );
}
