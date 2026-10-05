import 'package:markbit/application/persistence_coordinator.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/data/models/library_models.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/domain/search_query.dart';
import 'package:markbit/features/command_palette/command_palette.dart';
import 'package:markbit/features/graph/graph_view.dart';
import 'package:markbit/features/notelist/note_drag.dart';
import 'package:markbit/features/sidebar/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryRepository implements LibraryRepository {
  @override
  String get location => 'memory';
  @override
  Future<void> saveNote(Note note) async {}
  @override
  Future<void> deleteNote(String id) async {}
  @override
  Future<void> saveMeta({
    required List<Notebook> notebooks,
    required List<Tag> tags,
    required List<NoteTemplate> templates,
  }) async {}
  @override
  Future<LibrarySnapshot> load() async => const LibrarySnapshot(
    notes: [],
    notebooks: [],
    tags: [],
    templates: [],
    isFresh: false,
  );
}

Note _note(
  String id, {
  String title = '',
  String body = '',
  DateTime? created,
  DateTime? updated,
  bool pinned = false,
  bool starred = false,
  String? notebookId,
}) {
  final at = DateTime(2026, 9, 15);
  return Note(
    id: id,
    title: title,
    body: body,
    createdAt: created ?? at,
    updatedAt: updated ?? created ?? at,
    pinned: pinned,
    starred: starred,
    notebookId: notebookId,
  );
}

int _score(String query, Note note, {List<String> tags = const []}) =>
    SearchQuery.parse(
      query,
      now: DateTime(2026, 10, 5, 12),
    ).match(note, tagNames: tags, notebookName: 'Projects');

Future<ProviderContainer> _container(List<Note> notes) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
      initialLibraryProvider.overrideWithValue(
        LibrarySnapshot(
          notes: notes,
          notebooks: const [
            Notebook(id: 'inbox', name: 'General', isInbox: true),
            Notebook(id: 'work', name: 'Work'),
            Notebook(id: 'sub', name: 'Sub', parentId: 'work'),
          ],
          tags: [Tag(id: 't1', name: 'urgent', colorValue: 0xFF4C8DF6)],
          templates: const [],
          isFresh: false,
        ),
      ),
    ],
  );
}

void main() {
  group('search syntax', () {
    final n = _note('a', title: 'Deploy checklist', body: 'Run the migrations');

    test('negation excludes words and filters', () {
      expect(_score('deploy -draft', n), greaterThan(0));
      expect(_score('deploy -migrations', n), -1);
      expect(_score('-tag:urgent', n, tags: ['urgent']), -1);
      expect(
        _score('-tag:urgent', n, tags: ['later']),
        greaterThanOrEqualTo(0),
      );
    });

    test('OR matches either side', () {
      expect(_score('missing OR deploy', n), greaterThan(0));
      expect(_score('missing | absent', n), -1);
      expect(_score('missing OR deploy migrations', n), greaterThan(0));
      expect(_score('missing OR deploy absent', n), -1);
    });

    test('date filters', () {
      final old = _note('o', title: 'x', created: DateTime(2026, 8, 1));
      final fresh = _note('f', title: 'x', created: DateTime(2026, 10, 5, 9));
      expect(_score('created:>2026-09-01', old), -1);
      expect(_score('created:>2026-09-01', fresh), greaterThanOrEqualTo(0));
      expect(_score('created:<2026-09-01', old), greaterThanOrEqualTo(0));
      expect(_score('created:2026-08-01', old), greaterThanOrEqualTo(0));
      expect(_score('updated:today', fresh), greaterThanOrEqualTo(0));
      expect(_score('updated:today', old), -1);
      expect(_score('updated:7d', fresh), greaterThanOrEqualTo(0));
      expect(_score('updated:<30d', old), greaterThanOrEqualTo(0));
      expect(_score('updated:<30d', fresh), -1);
    });

    test('typos and Turkish characters are tolerated', () {
      final tr = _note('t', title: 'Görev listesi', body: 'Şifre değişikliği');
      expect(_score('gorev', tr), greaterThan(0));
      expect(_score('GÖREV', tr), greaterThan(0));
      expect(_score('sifre', tr), greaterThan(0));
      expect(_score('migratoins', n), greaterThan(0)); // swapped letters
      expect(_score('checklsit', n), greaterThan(0));
      expect(_score('"checklsit"', n), -1); // quoted: exact only
      expect(_score('xyzzy', n), -1);
    });

    test('flags', () {
      final s = _note('s', title: 'x', starred: true);
      expect(_score('is:starred', s), greaterThanOrEqualTo(0));
      expect(_score('is:starred', n), -1);
      expect(_score('is:locked', n), -1);
    });

    test('title matches rank above body matches', () {
      final inTitle = _note('1', title: 'Kubernetes notes');
      final inBody = _note('2', title: 'Misc', body: 'about kubernetes');
      expect(
        _score('kubernetes', inTitle),
        greaterThan(_score('kubernetes', inBody)),
      );
    });
  });

  group('highlighting', () {
    test('words, ranges and snippet around the match', () {
      final n = _note(
        'h',
        title: 'Notes',
        body: '# Intro\n\nSomething else.\n\nThe **migration** plan is here.',
      );
      final q = SearchQuery.parse('migratoin');
      expect(q.highlightWords(n), contains('migration'));
      expect(
        snippetAround(n.body, {'migration'}),
        'The migration plan is here.',
      );
      expect(highlightRanges('Görev listesi', {'gorev'}), [(0, 5)]);
      final long = '${'word ' * 60}target ${'tail ' * 60}';
      final snippet = snippetAround(long, {'target'}, max: 60)!;
      expect(snippet, contains('target'));
      expect(snippet, startsWith('…'));
    });
  });

  group('navigation state', () {
    test('recent and starred lists', () async {
      final c = await _container([
        _note('a', title: 'A', updated: DateTime(2026, 9, 1)),
        _note('b', title: 'B', starred: true),
        _note('c', title: 'C'),
      ]);
      addTearDown(c.dispose);
      final open = c.read(openNoteProvider.notifier);
      open.open('a');
      open.open('c');
      open.open('a');
      c.read(navFilterProvider.notifier).select(const NavFilter.recent());
      expect(c.read(visibleNotesProvider).map((n) => n.id), ['a', 'c']);
      c.read(navFilterProvider.notifier).select(const NavFilter.starred());
      expect(c.read(visibleNotesProvider).map((n) => n.id), ['b']);
      c.read(libraryProvider.notifier).toggleStar('c');
      expect(c.read(visibleNotesProvider).map((n) => n.id).toSet(), {'b', 'c'});
      await c.read(persistenceProvider).flush();
    });

    test('tabs reorder, cycle and jump', () async {
      final c = await _container([
        _note('a', title: 'A'),
        _note('b', title: 'B'),
        _note('c', title: 'C'),
      ]);
      addTearDown(c.dispose);
      final open = c.read(openNoteProvider.notifier);
      for (final id in ['a', 'b', 'c']) {
        open.open(id);
      }
      open.moveTab('c', 0);
      expect(c.read(openNoteProvider).tabs, ['c', 'a', 'b']);
      open.cycleTab(1); // from c (index 0) to a
      expect(c.read(openNoteIdProvider), 'a');
      open.cycleTab(-1);
      expect(c.read(openNoteIdProvider), 'c');
      open.openTabAt(8); // Alt+9: last tab
      expect(c.read(openNoteIdProvider), 'b');
      await c.read(persistenceProvider).flush();
    });

    test('notebooks nest without cycles; notes move and get tags', () async {
      final c = await _container([_note('a', title: 'A', notebookId: 'inbox')]);
      addTearDown(c.dispose);
      final lib = c.read(libraryProvider.notifier);
      expect(lib.moveNotebook('work', 'sub'), isFalse); // own child
      expect(lib.moveNotebook('work', 'inbox'), isFalse);
      expect(lib.moveNotebook('sub', null), isTrue);
      expect(c.read(libraryProvider).notebook('sub')!.parentId, isNull);
      expect(lib.moveNotebook('work', 'sub'), isTrue);
      lib.moveNotes(['a'], 'work');
      expect(c.read(libraryProvider).notes['a']!.notebookId, 'work');
      lib.tagNotes(['a'], 't1');
      lib.tagNotes(['a'], 't1');
      expect(c.read(libraryProvider).notes['a']!.tagIds, ['t1']);
      await c.read(persistenceProvider).flush();
    });
  });

  group('link graph', () {
    test('wiki links and focus', () async {
      final c = await _container([
        _note('a', title: 'Alpha', body: 'see [[Beta]]'),
        _note('b', title: 'Beta', body: 'back to [[id:a|Alpha]]'),
        _note('c', title: 'Gamma', body: 'links [[Delta]]'),
        _note('d', title: 'Delta'),
        _note('e', title: 'Lonely'),
      ]);
      addTearDown(c.dispose);
      final lib = c.read(libraryProvider);
      final all = NoteGraph.build(lib);
      expect(all.nodes.map((n) => n.id).toSet(), {'a', 'b', 'c', 'd'});
      expect(all.edges, hasLength(2));
      final withLonely = NoteGraph.build(lib, includeUnlinked: true);
      expect(withLonely.nodes, hasLength(5));
      final around = NoteGraph.build(lib, focusId: 'a');
      expect(around.nodes.map((n) => n.id).toSet(), {'a', 'b'});
    });
  });

  testWidgets('dragging a note onto a sidebar notebook moves it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _container([
      _note('a', title: 'Draggable note', notebookId: 'inbox'),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(
            Palettes.dark,
          ).copyWith(platform: TargetPlatform.windows),
          home: const Scaffold(
            body: Row(
              children: [
                SizedBox(width: 260, child: Sidebar()),
                Expanded(
                  child: Center(
                    child: NoteDraggable(
                      noteId: 'a',
                      title: 'Draggable note',
                      child: Text('drag me'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('drag me')),
    );
    await gesture.moveBy(const Offset(-20, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.text('Work')));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.read(libraryProvider).notes['a']!.notebookId, 'work');
    await tester.pump(const Duration(seconds: 5));
    await c.read(persistenceProvider).flush();
  });

  testWidgets('command palette finds notes by their content', (tester) async {
    final c = await _container([
      _note('a', title: 'Server setup', body: 'install nginx and certbot'),
      _note('b', title: 'Groceries', body: 'milk, eggs'),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showCommandPalette(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'certbot');
    await tester.pumpAndSettle();
    expect(find.text('Server setup'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
    expect(find.textContaining('certbot'), findsWidgets);
    await tester.enterText(find.byType(TextField), '>graph');
    await tester.pumpAndSettle();
    expect(find.textContaining('Link graph'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
