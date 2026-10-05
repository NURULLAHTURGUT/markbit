import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' show md5;
import 'package:markbit/app/app.dart';
import 'package:markbit/application/library_notifier.dart';
import 'package:markbit/application/persistence_coordinator.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/core/l10n/app_strings.dart';
import 'package:markbit/core/l10n/de_strings.dart';
import 'package:markbit/core/l10n/es_strings.dart';
import 'package:markbit/core/l10n/tr_editor.dart';
import 'package:markbit/core/l10n/tr_misc.dart';
import 'package:markbit/core/l10n/tr_settings.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/data/docx_export.dart';
import 'package:markbit/data/html_export.dart';
import 'package:markbit/data/importers.dart';
import 'package:markbit/data/models/library_models.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/domain/note_tasks.dart';
import 'package:markbit/features/dialogs/calendar_view.dart';
import 'package:markbit/features/dialogs/task_dashboard.dart';
import 'package:markbit/features/sidebar/sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

Note _note(String id, String body, {String title = 'Note', String? daily}) {
  final at = DateTime(2026, 10, 1);
  return Note(
    id: id,
    title: title,
    body: body,
    createdAt: at,
    updatedAt: at,
    dailyDate: daily,
    notebookId: 'inbox',
  );
}

Future<ProviderContainer> _container(
  List<Note> notes, {
  List<Tag> tags = const [],
}) async {
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
          ],
          tags: tags,
          templates: const [],
          isFresh: false,
        ),
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tasks', () {
    test('priority, repeat and due date round-trip', () {
      final note = _note('n', '- [ ] Pay rent');
      final task = noteTasks(note).single;
      var body = changeTask(
        note,
        task,
        id: 'abc',
        due: DateTime(2026, 10, 5, 9),
        setDate: true,
      );
      var t = noteTasks(note.copyWith(body: body)).single;
      body = changeTask(
        note.copyWith(body: body),
        t,
        priority: TaskPriority.high,
      );
      t = noteTasks(note.copyWith(body: body)).single;
      body = changeTask(
        note.copyWith(body: body),
        t,
        repeat: TaskRepeat.monthly,
        setRepeat: true,
      );
      t = noteTasks(note.copyWith(body: body)).single;
      expect(t.text, 'Pay rent');
      expect(t.priority, TaskPriority.high);
      expect(t.repeat, TaskRepeat.monthly);
      expect(t.due, DateTime(2026, 10, 5, 9));
    });

    test('completing a repeating task moves it to the next date', () {
      final note = _note(
        'n',
        '- [ ] Report <!-- task:a due:2026-10-05T09:00:00.000 repeat:weekly -->',
      );
      final task = noteTasks(note).single;
      final (body, next) = completeTask(
        note,
        task,
        true,
        now: DateTime(2026, 10, 5, 10),
      );
      final updated = noteTasks(note.copyWith(body: body)).single;
      expect(next, DateTime(2026, 10, 12, 9));
      expect(updated.done, isFalse);
      expect(updated.due, DateTime(2026, 10, 12, 9));
      // An overdue series skips missed occurrences.
      final (_, later) = completeTask(
        note,
        task,
        true,
        now: DateTime(2026, 10, 30),
      );
      expect(later, DateTime(2026, 11, 2, 9));
    });

    test('repeat rules', () {
      final friday = DateTime(2026, 10, 9, 8);
      expect(TaskRepeat.weekdays.next(friday), DateTime(2026, 10, 12, 8));
      expect(
        TaskRepeat.monthly.next(DateTime(2026, 1, 31)),
        DateTime(2026, 2, 28),
      );
      expect(
        TaskRepeat.yearly.next(DateTime(2028, 2, 29)),
        DateTime(2029, 2, 28),
      );
    });

    test('views and ordering', () {
      final now = DateTime(2026, 10, 5, 12);
      NoteTask t(
        DateTime? due, {
        bool done = false,
        TaskPriority p = TaskPriority.none,
      }) => NoteTask('n', 0, 'x', done, 'i', due, priority: p);
      final overdue = t(DateTime(2026, 10, 1));
      final today = t(DateTime(2026, 10, 5, 18));
      final week = t(DateTime(2026, 10, 9));
      final later = t(DateTime(2026, 11, 1));
      final undated = t(null);
      expect(taskInView(overdue, TaskView.overdue, now), isTrue);
      expect(taskInView(today, TaskView.today, now), isTrue);
      expect(taskInView(week, TaskView.today, now), isFalse);
      expect(taskInView(week, TaskView.week, now), isTrue);
      expect(taskInView(later, TaskView.week, now), isFalse);
      expect(taskInView(undated, TaskView.open, now), isTrue);
      final sorted = [undated, later, today, overdue]..sort(compareTasks);
      expect(sorted, [overdue, today, later, undated]);
    });

    test('calendar lists tasks, repeats and daily notes', () async {
      final c = await _container([
        _note(
          'a',
          '- [ ] Standup <!-- task:s due:2026-10-05T09:00:00.000 repeat:daily -->\n'
              '- [ ] Once <!-- task:o due:2026-10-20T09:00:00.000 -->',
        ),
        _note('d', '', title: '2026-10-07', daily: '2026-10-07'),
      ]);
      addTearDown(c.dispose);
      final month = calendarMonth(
        c.read(libraryProvider),
        DateTime(2026, 10),
        c.read(libraryProvider.notifier),
      );
      expect(month.tasks[DateTime(2026, 10, 5)]!.single.repeatPreview, isFalse);
      expect(month.tasks[DateTime(2026, 10, 31)]!.single.repeatPreview, isTrue);
      expect(month.tasks[DateTime(2026, 10, 4)], isNull);
      expect(month.tasks[DateTime(2026, 10, 20)], hasLength(2));
      expect(month.daily[DateTime(2026, 10, 7)]!.id, 'd');
      final made = c
          .read(libraryProvider.notifier)
          .dailyNoteFor(DateTime(2026, 10, 7));
      expect(made.id, 'd');
      await c.read(persistenceProvider).flush();
    });
  });

  group('export', () {
    final note = _note(
      'x',
      '## Plan\n\nSome **bold** and \$x^2\$ and a link[^1].\n\n'
          '| A | B |\n| --- | --- |\n| 1 | 2 |\n\n'
          '- [x] done\n- todo\n\n```mermaid\ngraph TD\n  A-->B\n```\n\n[^1]: The note.',
      title: 'Doc <1>',
    );

    test('HTML page', () {
      final html = HtmlExport.page(note);
      expect(html, contains('<title>Doc &lt;1&gt;</title>'));
      expect(html, contains('<strong>bold</strong>'));
      expect(html, contains(r'\(x^2\)'));
      expect(html, contains('katex'));
      expect(html, contains('<pre class="mermaid">'));
      expect(html, contains('id="fn-1"'));
      expect(html, contains('<table>'));
    });

    test('Word document', () {
      final bytes = DocxExport.build(note);
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toSet();
      expect(
        names,
        containsAll([
          '[Content_Types].xml',
          'word/document.xml',
          'word/styles.xml',
        ]),
      );
      final doc = utf8.decode(archive.findFile('word/document.xml')!.content);
      expect(doc, contains('Doc &lt;1&gt;'));
      expect(doc, contains('<w:b/>'));
      expect(doc, contains('<w:tbl>'));
      expect(doc, contains('☑'));
      expect(doc, contains('Heading2'));
    });
  });

  group('import', () {
    late Directory dir;
    setUp(
      () async => dir = await Directory.systemTemp.createTemp('markbit_imp_'),
    );
    tearDown(() async => dir.delete(recursive: true));

    Future<Library> lib() async {
      final c = await _container([]);
      addTearDown(c.dispose);
      return c.read(libraryProvider);
    }

    test('Obsidian vault', () async {
      await Directory(p.join(dir.path, 'attachments')).create();
      await Directory(p.join(dir.path, '.obsidian')).create();
      await File(p.join(dir.path, '.obsidian', 'app.md')).writeAsString('skip');
      // 1x1 PNG
      await File(p.join(dir.path, 'attachments', 'pic.png')).writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aE1sAAAAASUVORK5CYII=',
        ),
      );
      await File(p.join(dir.path, 'Note.md')).writeAsString(
        '---\ntags:\n  - project/alpha\n---\nSee [[Other#Part|alias]] ![[pic.png]] #idea/new',
      );
      final plan = await importObsidian(dir.path, await lib());
      final file = plan.files.single;
      expect(file.tags, containsAll(['project/alpha', 'idea/new']));
      expect(file.note.body, contains('[[Other|alias]]'));
      expect(file.note.body, contains('data:image/png;base64'));
    });

    test('Notion export', () async {
      final zip = Archive()
        ..addFile(
          ArchiveFile.string(
            'Home 0123456789abcdef0123456789abcdef.md',
            '# Home\n\nTags: work, ideas\n\nSee [Child](Home%200123456789abcdef0123456789abcdef/Child%20fedcba9876543210fedcba9876543210.md)',
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'Home 0123456789abcdef0123456789abcdef/Child fedcba9876543210fedcba9876543210.md',
            '# Child\n\nText',
          ),
        );
      final path = p.join(dir.path, 'export.zip');
      await File(path).writeAsBytes(ZipEncoder().encode(zip));
      final plan = await importNotion(path, await lib());
      final home = plan.files.firstWhere((f) => f.note.title == 'Home');
      final child = plan.files.firstWhere((f) => f.note.title == 'Child');
      expect(home.tags, ['work', 'ideas']);
      expect(home.note.body.trim(), 'See [[Child]]');
      expect(child.folders, ['Home']);
      expect(child.note.body.trim(), 'Text');
    });

    test('Evernote .enex', () async {
      final data = base64Encode(utf8.encode('pdf bytes'));
      final enex =
          '''<?xml version="1.0" encoding="UTF-8"?>
<en-export><note><title>Trip</title>
<content><![CDATA[<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note><h1>Plan</h1><div>Go <b>early</b>&nbsp;today</div><ul><li>Bags</li><li>Tickets</li></ul><div><en-todo checked="true"/>Booked</div><en-media hash="HASH" type="application/pdf"/></en-note>]]></content>
<created>20240101T120000Z</created><tag>travel</tag>
<resource><data encoding="base64">$data</data><mime>application/pdf</mime><resource-attributes><file-name>ticket.pdf</file-name></resource-attributes></resource>
</note></en-export>''';
      final md5hash = md5.convert(utf8.encode('pdf bytes')).toString();
      final path = p.join(dir.path, 'n.enex');
      await File(path).writeAsString(enex.replaceFirst('HASH', md5hash));
      final plan = await importEvernote([path], await lib());
      final note = plan.files.single.note;
      expect(note.title, 'Trip');
      expect(plan.files.single.tags, ['travel']);
      expect(note.body, contains('# Plan'));
      expect(note.body, contains('**early**'));
      expect(note.body, contains('- Bags'));
      expect(note.body, contains('- [x] Booked'));
      expect(note.attachments.values.single.name, 'ticket.pdf');
      expect(note.body, contains('markbit://attachment/'));
    });

    test('Joplin .jex', () async {
      const folder = 'f0000000000000000000000000000001';
      const n1 = 'a0000000000000000000000000000001';
      const n2 = 'a0000000000000000000000000000002';
      const res = 'b0000000000000000000000000000001';
      const tag = 'c0000000000000000000000000000001';
      final tar = Archive()
        ..addFile(
          ArchiveFile.string('$folder.md', 'Work\n\nid: $folder\ntype_: 2'),
        )
        ..addFile(
          ArchiveFile.string(
            '$n1.md',
            'Plan\n\nSee [the other](:/$n2) ![chart](:/$res)\n\nid: $n1\nparent_id: $folder\ncreated_time: 2024-01-01T10:00:00.000Z\ntype_: 1',
          ),
        )
        ..addFile(
          ArchiveFile.string('$n2.md', 'Other\n\nBody\n\nid: $n2\ntype_: 1'),
        )
        ..addFile(
          ArchiveFile.string(
            '$res.md',
            'chart.png\n\nid: $res\nmime: image/png\nfile_extension: png\ntype_: 4',
          ),
        )
        ..addFile(ArchiveFile('resources/$res.png', 3, [1, 2, 3]))
        ..addFile(ArchiveFile.string('$tag.md', 'urgent\n\nid: $tag\ntype_: 5'))
        ..addFile(
          ArchiveFile.string(
            'd1.md',
            '\n\nid: d0000000000000000000000000000001\nnote_id: $n1\ntag_id: $tag\ntype_: 6',
          ),
        );
      final path = p.join(dir.path, 'notes.jex');
      await File(path).writeAsBytes(TarEncoder().encode(tar));
      final plan = await importJoplin(path, await lib());
      final plan1 = plan.files.firstWhere((f) => f.note.title == 'Plan');
      expect(plan1.folders, ['Work']);
      expect(plan1.tags, ['urgent']);
      expect(plan1.note.body, contains('[[Other]]'));
      expect(plan1.note.body, contains('data:image/png;base64'));
    });
  });

  group('tags', () {
    test('tree, sub-tag filter, rename and merge', () async {
      final c = await _container(
        [
          _note('a', 'x').copyWith(tagIds: ['t1']),
          _note('b', 'y').copyWith(tagIds: ['t2']),
          _note('c', 'z').copyWith(tagIds: ['t3']),
        ],
        tags: const [
          Tag(id: 't1', name: 'work/client', colorValue: 0xFF000000),
          Tag(id: 't2', name: 'work/intern', colorValue: 0xFF000000),
          Tag(id: 't3', name: 'home', colorValue: 0xFF000000),
        ],
      );
      addTearDown(c.dispose);
      var tree = TagNode.build(c.read(libraryProvider));
      final work = tree.children.firstWhere((n) => n.path == 'work');
      expect(work.tag, isNull); // virtual parent
      expect(work.count, 2);
      expect(work.children.map((n) => n.name), ['client', 'intern']);
      c
          .read(navFilterProvider.notifier)
          .select(const NavFilter.tag('path:work'));
      expect(c.read(visibleNotesProvider).map((n) => n.id).toSet(), {'a', 'b'});
      final lib = c.read(libraryProvider.notifier);
      lib.createTag('work');
      final workTag = c.read(libraryProvider).tagByName('work')!;
      lib.updateTag(workTag.id, name: 'jobs');
      expect(c.read(libraryProvider).tag('t1')!.name, 'jobs/client');
      lib.mergeTags('t2', 't1');
      expect(c.read(libraryProvider).tag('t2'), isNull);
      expect(c.read(libraryProvider).notes['b']!.tagIds, ['t1']);
      tree = TagNode.build(c.read(libraryProvider), filter: 'cli');
      expect(tree.children.single.children.single.name, 'client');
      await c.read(persistenceProvider).flush();
    });
  });

  group('languages', () {
    test('German and Spanish cover every Turkish string', () {
      final turkish = {...trEditor, ...trSettings, ...trMisc};
      expect(deStrings.keys.toSet(), containsAll(turkish.keys));
      expect(esStrings.keys.toSet(), containsAll(turkish.keys));
      expect(AppStrings(const Locale('de')).tr('Settings'), 'Einstellungen');
      expect(
        AppStrings(const Locale('es')).tr('{n} words', {'n': 3}),
        '3 palabras',
      );
    });
  });

  testWidgets('calendar opens on a day without tasks', (tester) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 9);
    final c = await _container([
      _note(
        'a',
        '- [ ] Later <!-- task:l due:${tomorrow.toIso8601String()} -->',
      ),
    ]);
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.build(Palettes.light),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCalendarView(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CalendarView), findsOneWidget);
    await tester.tap(find.text('${tomorrow.day}').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Later'), findsWidgets);
  });

  testWidgets('interface scale zooms the whole UI', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: const UiScale(
          scale: 1.25,
          child: Scaffold(body: Center(child: Text('zoomed'))),
        ),
      ),
    );
    final size = tester.getRect(find.text('zoomed')).size;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Palettes.light),
        home: const UiScale(
          scale: 1,
          child: Scaffold(body: Center(child: Text('zoomed'))),
        ),
      ),
    );
    final plain = tester.getRect(find.text('zoomed')).size;
    expect(size.width, closeTo(plain.width * 1.25, 1));
  });
}
