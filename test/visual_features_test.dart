import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:markbit/core/widgets/app_dialog.dart';
import 'package:markbit/core/widgets/color_picker_panel.dart';
import 'package:markbit/app/app.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/data/models/library_models.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/models/app_settings.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/domain/markdown_utils.dart';
import 'package:markbit/domain/visual_block.dart';
import 'package:markbit/features/editor/preview/visual_block_view.dart';
import 'package:markbit/features/editor/preview/markdown_preview.dart';
import 'package:markbit/features/ai/ai_panel.dart';
import 'package:markbit/application/ai_notifier.dart';
import 'package:markbit/features/notelist/notes_overview.dart';
import 'package:markbit/features/sidebar/sidebar.dart';
import 'package:markbit/features/editor/note_editor.dart';
import 'package:markbit/features/editor/code_text_editor.dart';
import 'package:markbit/features/editor/format_toolbar.dart';
import 'package:markbit/features/editor/note_meta_bar.dart';
import 'package:markbit/features/editor/note_cover_header.dart';
import 'package:markbit/features/editor/visual_block_dialog.dart';
import 'package:markbit/features/dialogs/searchable_picker.dart';
import 'package:markbit/core/widgets/app_icon_button.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/toolbar.dart';

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
  testWidgets(
    'searchable picker marks selection and filters long option lists',
    (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Palettes.zenGlass),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  picked = await showSearchablePicker<String>(
                    context,
                    title: 'Pick',
                    selected: '17',
                    options: List.generate(
                      40,
                      (i) => PickerOption('$i', 'Option $i'),
                    ),
                  );
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open picker'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Option 17');
      await tester.pumpAndSettle();
      expect(find.byType(DialogListItem), findsOneWidget);
      expect(
        tester.widget<DialogListItem>(find.byType(DialogListItem)).selected,
        isTrue,
      );
      await tester.tap(find.byType(DialogListItem));
      await tester.pumpAndSettle();
      expect(picked, '17');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'new and edited tags share the spectrum picker and keep chosen colors',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
          initialLibraryProvider.overrideWithValue(
            const LibrarySnapshot(
              notes: [],
              notebooks: [Notebook(id: 'inbox', name: 'Inbox', isInbox: true)],
              tags: [],
              templates: [],
              isFresh: false,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MarkbitApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('New tag'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ColorPickerPanel), findsOneWidget);
      await tester.enterText(
        find
            .descendant(
              of: find.byType(AppDialog),
              matching: find.byType(TextField),
            )
            .first,
        'Custom tag',
      );
      await tester.enterText(find.byKey(const ValueKey('color-hex')), '9333EA');
      await tester.pump();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final tag = container.read(libraryProvider).tags.single;
      expect(tag.colorValue, 0xFF9333EA);
      await tester.tap(
        find.text('Custom tag'),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Rename / change colour'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ColorPickerPanel), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('color-hex')))
            .controller!
            .text,
        '9333EA',
      );
      expect(find.byKey(const ValueKey('recent-color-0')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('color-hex')), '16A34A');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        container.read(libraryProvider).tags.single.colorValue,
        0xFF16A34A,
      );
      expect(await RecentColors.load(), [
        const Color(0xFF16A34A),
        const Color(0xFF9333EA),
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  testWidgets('starred opens its notes as cards', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
        initialLibraryProvider.overrideWithValue(
          const LibrarySnapshot(
            notes: [],
            notebooks: [Notebook(id: 'a', name: 'Notebook A')],
            tags: [],
            templates: [],
            isFresh: false,
          ),
        ),
      ],
    );
    final lib = container.read(libraryProvider.notifier);
    final star = lib.createNote(notebookId: 'a', title: 'Shining note');
    lib.createNote(notebookId: 'a', title: 'Plain note');
    lib.toggleStar(star.id);
    // Start from the classic list with a note open.
    container.read(notesOverviewProvider.notifier).set(false);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MarkbitApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Starred').first);
    await tester.pumpAndSettle();
    expect(container.read(notesOverviewProvider), isTrue);
    expect(find.byType(NotesOverview), findsOneWidget);
    expect(find.text('Shining note'), findsOneWidget);
    expect(find.text('Plain note'), findsNothing);
    lib.toggleStar(star.id);
    await tester.pumpAndSettle();
    expect(
      find.text('No starred notes yet. Star a note from its menu.'),
      findsOneWidget,
    );
  });

  testWidgets('notebook navigation opens only its notes as cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
        initialLibraryProvider.overrideWithValue(
          const LibrarySnapshot(
            notes: [],
            notebooks: [
              Notebook(id: 'a', name: 'Notebook A'),
              Notebook(id: 'b', name: 'Notebook B'),
            ],
            tags: [],
            templates: [],
            isFresh: false,
          ),
        ),
      ],
    );
    final lib = container.read(libraryProvider.notifier);
    lib.createNote(notebookId: 'a', title: 'Inside A');
    lib.createNote(notebookId: 'b', title: 'Inside B');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MarkbitApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notebook A').first);
    await tester.pumpAndSettle();
    expect(container.read(notesOverviewProvider), isTrue);
    expect(find.byType(NotesOverview), findsOneWidget);
    expect(find.text('Inside A'), findsOneWidget);
    expect(find.text('Inside B'), findsNothing);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
    await tester.pumpAndSettle();
    expect(find.text('Inside A'), findsNothing);
    expect(find.text('No notes match your filter'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Active'));
    await tester.pumpAndSettle();
    expect(find.text('Inside A'), findsOneWidget);
    await tester.tap(find.text('Notebook B').first);
    await tester.pumpAndSettle();
    expect(find.text('Inside B'), findsOneWidget);
    final tag = lib.createTag('Review tag');
    final target = container
        .read(libraryProvider)
        .notes
        .values
        .firstWhere((n) => n.title == 'Inside B');
    lib.toggleTag(target.id, tag.id);
    lib.setStatus(target.id, NoteStatus.active);
    await tester.pumpAndSettle();
    // The tag row may be below the fold of the (longer) sidebar.
    final tagRow = find.descendant(
      of: find.byType(Sidebar),
      matching: find.text('Review tag'),
    );
    await tester.scrollUntilVisible(
      tagRow,
      200,
      scrollable: find
          .descendant(
            of: find.byType(Sidebar),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(tagRow);
    await tester.pumpAndSettle();
    expect(container.read(notesOverviewProvider), isTrue);
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.text('Active').first);
    await tester.pumpAndSettle();
    expect(container.read(notesOverviewProvider), isTrue);
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.text('Notebook B').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'On Hold'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Dropped'), findsOneWidget);
    final grid = tester.widget<GridView>(find.byType(GridView));
    final before =
        (grid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent)
            .mainAxisExtent!;
    await tester.tap(find.byTooltip('Compact cards'));
    await tester.pumpAndSettle();
    final compactGrid = tester.widget<GridView>(find.byType(GridView));
    expect(
      (compactGrid.gridDelegate as SliverGridDelegateWithMaxCrossAxisExtent)
          .mainAxisExtent,
      lessThan(before),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  for (final kind in VisualKind.values) {
    testWidgets(
      '${kind.name} editor has a growing data field and live responsive preview',
      (tester) async {
        tester.view.physicalSize = const Size(1400, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(Palettes.light),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showVisualBlockDialog(context, kind: kind),
                  child: const Text('Open chart'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open chart'));
        await tester.pumpAndSettle();
        final data = find.widgetWithText(
          TextField,
          kind == VisualKind.chart ? 'Data points' : 'Topics',
        );
        expect(tester.widget<TextField>(data).maxLines, isNull);
        expect(tester.getSize(data).height, greaterThan(300));
        await tester.enterText(
          data,
          List.generate(
            24,
            (i) => kind == VisualKind.chart ? 'Item $i; ${i + 1}' : 'Topic $i',
          ).join('\n'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(VisualBlockView), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(VisualBlockView)).dx,
          greaterThan(tester.getTopRight(data).dx),
        );
        await tester.enterText(
          find.widgetWithText(
            TextField,
            kind == VisualKind.chart ? 'Chart title' : 'Central topic',
          ),
          'Live title',
        );
        await tester.pumpAndSettle();
        expect(find.text('Live title'), findsWidgets);
        final previewBeforeScroll = tester.getTopLeft(
          find.byType(VisualBlockView),
        );
        await tester.drag(data, const Offset(0, -220));
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(VisualBlockView)),
          previewBeforeScroll,
        );
        tester.view.physicalSize = const Size(600, 900);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.byType(VisualBlockView)).dy,
          greaterThan(tester.getBottomLeft(data).dy),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'fixed toolbar stays below tags without covering text and overflows into a menu in narrow panes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final note = Note(
        id: 'toolbar',
        title: 'Toolbar',
        body: List.generate(30, (i) => 'Line $i').join('\n'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
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
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.build(
              Palettes.light,
            ).copyWith(platform: TargetPlatform.windows),
            home: const Scaffold(
              body: SizedBox(width: 300, child: NoteEditor(noteId: 'toolbar')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FormatToolbar), findsOneWidget);
      expect(find.byTooltip('Insert visual block'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(NoteCoverHeader),
          matching: find.byType(PopupMenuButton<VisualKind>),
        ),
        findsNothing,
      );
      final field = find.descendant(
        of: find.byType(CodeTextEditor),
        matching: find.byType(TextField),
      );
      final textField = tester.widget<TextField>(field);
      textField.focusNode!.requestFocus();
      textField.controller!.selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(find.byType(FormatToolbar));
      expect(
        first.top,
        greaterThanOrEqualTo(tester.getBottomLeft(find.byType(NoteMetaBar)).dy),
      );
      expect(first.bottom, lessThanOrEqualTo(tester.getTopLeft(field).dy));
      final actions = find.descendant(
        of: find.byType(FormatToolbar),
        matching: find.byType(AppIconButton),
      );
      // One row only: what does not fit moves into the "More" menu.
      expect(actions, findsWidgets);
      expect(actions.evaluate().length, lessThan(21));
      expect(find.byTooltip('More formatting'), findsOneWidget);
      expect(first.height, lessThan(48));
      for (final element in actions.evaluate()) {
        final rect = tester.getRect(find.byWidget(element.widget));
        expect(first.contains(rect.center), isTrue);
        expect(rect.right, lessThanOrEqualTo(first.right));
      }
      textField.controller!.selection = TextSelection.collapsed(
        offset: note.body.indexOf('Line 12'),
      );
      await tester.pumpAndSettle();
      final moved = tester.getRect(find.byType(FormatToolbar));
      expect(moved, first);
      final scroll = tester
          .widget<CodeTextEditor>(find.byType(CodeTextEditor))
          .scrollController;
      scroll.jumpTo(80);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(FormatToolbar)), first);
      await tester.tap(
        find.descendant(
          of: find.byType(NoteCoverHeader),
          matching: find.byType(TextField),
        ),
      );
      await tester.pumpAndSettle();
      expect(textField.focusNode!.hasFocus, isFalse);
      expect(tester.getRect(find.byType(FormatToolbar)), first);
      // Formatting still acts on the body selection after another field gets focus.
      final start = textField.controller!.text.indexOf('Line 12');
      textField.controller!.selection = TextSelection(
        baseOffset: start,
        extentOffset: start + 7,
      );
      await tester.tap(find.byTooltip('Bold'));
      await tester.pumpAndSettle();
      expect(textField.controller!.text, contains('**Line 12**'));
      expect(textField.focusNode!.hasFocus, isTrue);
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      scroll.jumpTo(0);
      textField.controller!.selection = const TextSelection.collapsed(
        offset: 0,
      );
      await tester.pumpAndSettle();
      final bounded = tester.getRect(find.byType(FormatToolbar));
      final viewport = tester.getRect(find.byType(CodeTextEditor));
      expect(bounded.bottom, lessThanOrEqualTo(viewport.top));
      expect(viewport.height, greaterThan(0));
      container.read(noteUiProvider(note.id).notifier).mode(ViewMode.preview);
      await tester.pumpAndSettle();
      expect(find.byType(FormatToolbar), findsNothing);
      container.read(noteUiProvider(note.id).notifier).mode(ViewMode.edit);
      await tester.pumpAndSettle();
      expect(find.byType(FormatToolbar), findsOneWidget);
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.build(
              Palettes.glassDark,
            ).copyWith(platform: TargetPlatform.windows),
            home: const Scaffold(
              body: SizedBox(width: 1000, child: NoteEditor(noteId: 'toolbar')),
            ),
          ),
        ),
      );
      container.read(noteUiProvider(note.id).notifier).mode(ViewMode.split);
      await tester.pumpAndSettle();
      final toolbarBounds = tester.getRect(find.byType(FormatToolbar));
      final editBounds = tester.getRect(find.byType(CodeTextEditor));
      final previewBounds = tester.getRect(find.byType(MarkdownPreview));
      expect(toolbarBounds.right, editBounds.right);
      expect(toolbarBounds.right, lessThanOrEqualTo(previewBounds.left));
      expect(toolbarBounds.bottom, editBounds.top);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
  testWidgets(
    'cover shrinks once the note scrolls and split is disabled when narrow',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final png = await tester.runAsync(
        () => File('assets/icon/markbit.png').readAsBytes(),
      );
      final note = Note(
        id: 'covered',
        title: 'Covered',
        body: List.generate(80, (i) => 'Line $i').join('\n'),
        coverImage: base64Encode(png!),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
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
            theme: AppTheme.build(
              Palettes.dark,
            ).copyWith(platform: TargetPlatform.windows),
            home: const Scaffold(body: NoteEditor(noteId: 'covered')),
          ),
        ),
      );
      container.read(noteUiProvider(note.id).notifier).mode(ViewMode.split);
      await tester.pumpAndSettle();
      double coverHeight() => tester
          .getSize(
            find
                .descendant(
                  of: find.byType(NoteCoverHeader),
                  matching: find.byType(ClipRRect),
                )
                .first,
          )
          .height;
      expect(coverHeight(), 158);
      // A 600px pane cannot split: the editor is shown and the split
      // segment is disabled instead of looking selected.
      expect(find.byType(MarkdownPreview), findsNothing);
      expect(find.byTooltip('Split view needs a wider pane'), findsOneWidget);
      tester
          .widget<CodeTextEditor>(find.byType(CodeTextEditor))
          .scrollController
          .jumpTo(200);
      await tester.pumpAndSettle();
      expect(coverHeight(), 64);
      tester
          .widget<CodeTextEditor>(find.byType(CodeTextEditor))
          .scrollController
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(coverHeight(), 158);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'trash opens cards and empty trash deletes every trashed note despite search',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
          initialLibraryProvider.overrideWithValue(
            LibrarySnapshot(
              notes: [],
              notebooks: [
                const Notebook(id: 'inbox', name: 'Inbox', isInbox: true),
              ],
              tags: [],
              templates: [],
              isFresh: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final lib = container.read(libraryProvider.notifier);
      final keep = lib.createNote(title: 'Keep this');
      final first = lib.createNote(title: 'Discard one');
      final second = lib.createNote(title: 'Discard two');
      lib.trash(first.id);
      lib.trash(second.id);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MarkbitApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trash').first);
      await tester.pumpAndSettle();
      expect(find.byType(NotesOverview), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('Discard one'), findsOneWidget);
      expect(find.text('Discard two'), findsOneWidget);
      expect(find.text('Keep this'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search your notes'),
        'Discard one',
      );
      await tester.pumpAndSettle();
      expect(find.text('Discard two'), findsNothing);
      await tester.tap(find.text('Empty trash'));
      await tester.pumpAndSettle();
      expect(
        find.text('2 note(s) will be deleted permanently.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Empty trash').last);
      await tester.pumpAndSettle();
      expect(container.read(libraryProvider).notes.keys, [keep.id]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('assistant resizes by drag and expand button with saved width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
        aiModelsProvider.overrideWith((ref) async => []),
        initialLibraryProvider.overrideWithValue(
          LibrarySnapshot(
            notes: [],
            notebooks: [
              const Notebook(id: 'inbox', name: 'Inbox', isInbox: true),
            ],
            tags: [],
            templates: [],
            isFresh: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final note = container
        .read(libraryProvider.notifier)
        .createNote(title: 'Resize');
    container.read(openNoteProvider.notifier).open(note.id);
    expect(container.read(noteListVisibleProvider), isTrue);
    container.read(aiPanelVisibleProvider.notifier).set(true);
    expect(container.read(noteListVisibleProvider), isFalse);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MarkbitApp(),
      ),
    );
    await tester.pumpAndSettle();
    final start = tester.getSize(find.byType(AiPanel)).width;
    await tester.drag(
      find.byKey(const ValueKey('ai-panel-resize')),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    final wider = tester.getSize(find.byType(AiPanel)).width;
    expect(wider, greaterThan(start));
    expect(prefs.getDouble('ai_panel_width_v1'), wider);
    await tester.tap(find.byTooltip('Narrow assistant'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AiPanel)).width, 360);
    await tester.tap(find.byTooltip('Expand assistant'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(AiPanel)).width, greaterThan(wider));
    final input = find.descendant(
      of: find.byType(AiPanel),
      matching: find.byType(TextField),
    );
    final firstChat = container.read(aiProvider(note.id)).activeId!;
    await tester.enterText(input, 'Keep my first draft');
    container.read(aiProvider(note.id).notifier).newChat();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);
    await tester.enterText(input, 'Keep my second draft');
    container.read(aiProvider(note.id).notifier).selectChat(firstChat);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Keep my first draft',
    );
    container.read(aiPanelVisibleProvider.notifier).set(false);
    await tester.pumpAndSettle();
    container.read(aiPanelVisibleProvider.notifier).set(true);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(input).controller!.text,
      'Keep my first draft',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
  testWidgets('insert and edit a visual block without losing note text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _MemoryRepository();
    late ProviderContainer container;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final snap = LibrarySnapshot(
        notes: [],
        notebooks: [const Notebook(id: 'inbox', name: 'Inbox', isInbox: true)],
        tags: [],
        templates: [],
        isFresh: false,
      );
      container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(repo),
          initialLibraryProvider.overrideWithValue(snap),
        ],
      );
    });
    final note = container
        .read(libraryProvider.notifier)
        .createNote(title: 'Visual note', body: 'Before\n\nAfter');
    container.read(openNoteProvider.notifier).open(note.id);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MarkbitApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tapToolbarAction(tester, 'Mind map');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Central topic'),
      'Roadmap',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Topics'),
      'Research\n  Ideas\nLaunch',
    );
    await tester.tap(find.text('Insert').last);
    await tester.pumpAndSettle();
    expect(find.byType(VisualBlockView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Edit visual block'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Central topic'),
      'Updated roadmap',
    );
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    final body = container.read(libraryProvider).notes[note.id]!.body;
    expect(body, contains('Before\n\nAfter'));
    final segment = splitSegments(body).whereType<CodeSegment>().single;
    expect(VisualBlock.parse(segment.code)!.title, 'Updated roadmap');
    await tapToolbarAction(tester, 'Chart');
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Chart title'),
      'Sales',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Data points'),
      'January; 40\nFebruary; 65',
    );
    await tester.tap(find.text('Insert').last);
    await tester.pumpAndSettle();
    final blocks = splitSegments(
      container.read(libraryProvider).notes[note.id]!.body,
    ).whereType<CodeSegment>().map((s) => VisualBlock.parse(s.code)!).toList();
    expect(
      blocks.map((b) => b.kind),
      containsAll([VisualKind.mindmap, VisualKind.chart]),
    );
    expect(
      blocks.singleWhere((b) => b.kind == VisualKind.chart).title,
      'Sales',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  test('nested mind map survives Markdown and JSON round trips', () {
    final map = VisualBlock.fromInput(
      kind: VisualKind.mindmap,
      title: 'Proje',
      input: 'Araştırma\n  Kaynaklar\n  Fikirler\nPlanlama\n  İşler',
    );
    final body = '# Not\n\n${map.markdown}\n\nDiğer metin';
    final segment = splitSegments(body).whereType<CodeSegment>().single;
    expect(segment.info, VisualBlock.fence);
    final loaded = VisualBlock.parse(segment.code)!;
    expect(loaded.input, map.input);
    expect(loaded.title, 'Proje');
    expect(loaded.items[1].depth, 1);
  });

  test(
    'invalid nesting, nonfinite values and nonpositive donut data are rejected',
    () {
      expect(
        () => VisualBlock.fromInput(
          kind: VisualKind.mindmap,
          title: 'Map',
          input: 'Root\n    Skipped level',
        ),
        throwsFormatException,
      );
      expect(
        () => VisualBlock.fromInput(
          kind: VisualKind.chart,
          title: 'Chart',
          input: 'Bad; NaN',
        ),
        throwsFormatException,
      );
      expect(
        () => VisualBlock.fromInput(
          kind: VisualKind.chart,
          title: 'Chart',
          input: 'Bad; -3',
          style: ChartStyle.donut,
        ),
        throwsFormatException,
      );
      expect(VisualBlock.parse('{broken'), isNull);
    },
  );

  test('chart accepts decimal comma and signed data', () {
    final chart = VisualBlock.fromInput(
      kind: VisualKind.chart,
      title: 'Trend',
      input: 'Ocak; -12,5\nŞubat; 7',
      style: ChartStyle.line,
    );
    expect(VisualBlock.parse(chart.json)!.items.first.value, -12.5);
  });

  test(
    'cover and diagrams persist; legacy notes and cover removal stay supported',
    () async {
      final dir = await Directory.systemTemp.createTemp('markbit_visual_');
      try {
        final repo = await FileLibraryRepository.open(root: dir);
        final map = VisualBlock.fromInput(
          kind: VisualKind.mindmap,
          title: 'A',
          input: 'B',
        );
        final note = Note(
          id: 'cover',
          title: 'T',
          body: map.markdown,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          coverImage: 'AQID',
        );
        await repo.saveNote(note);
        final restored = (await repo.load()).notes.single;
        expect(restored.coverImage, startsWith('file:'));
        expect(
          await File.fromUri(Uri.parse(restored.coverImage!)).readAsBytes(),
          [1, 2, 3],
        );
        expect(restored.body, map.markdown);
        expect(restored.copyWith(title: 'New').coverImage, restored.coverImage);
        expect(restored.copyWith(coverImage: null).coverImage, isNull);
        final legacy = note.toJson()..remove('coverImage');
        expect(Note.fromJson(legacy).coverImage, isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  for (final palette in [
    Palettes.light,
    Palettes.dark,
    Palettes.zenGlass,
    Palettes.glassDark,
  ]) {
    testWidgets('visual blocks render in a narrow ${palette.id} pane', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final blocks = [
        VisualBlock.fromInput(
          kind: VisualKind.mindmap,
          title: 'Project',
          input: 'Research\n  Ideas\nPlans',
        ),
        for (final style in ChartStyle.values)
          VisualBlock.fromInput(
            kind: VisualKind.chart,
            title: style.name,
            input: 'A long readable category; 40\nAnother category; 65',
            style: style,
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(palette),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  for (final b in blocks) VisualBlockView(source: b.json),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
