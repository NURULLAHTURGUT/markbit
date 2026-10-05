import 'package:markbit/features/editor/image_size_dialog.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/application/persistence_coordinator.dart';
import 'package:markbit/data/pdf_export_service.dart';
import 'package:markbit/data/note_images.dart';
import 'package:markbit/data/export_service.dart';
import 'package:markbit/application/library_notifier.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markbit/app/app.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/models/library_models.dart';
import 'package:markbit/data/note_image_service.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/features/editor/code_text_editor.dart';
import 'package:markbit/features/editor/markdown_commands.dart';
import 'package:flutter/foundation.dart';

import 'support/toolbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'valid images are portable and invalid or oversized files are rejected',
    () async {
      final bytes = await File('assets/icon/markbit.png').readAsBytes();
      final uri = Uri.parse(await NoteImageService.embed(bytes));
      expect(uri.data!.mimeType, 'image/png');
      expect(uri.data!.contentAsBytes(), bytes);
      await expectLater(
        NoteImageService.embed(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
      await expectLater(
        NoteImageService.embed(Uint8List(10 * 1024 * 1024 + 1)),
        throwsFormatException,
      );
    },
  );
  test('large dimensions are reduced before embedding', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 2400, 100),
      Paint()..color = Colors.blue,
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(2400, 100);
    final png = await source.toByteData(format: ui.ImageByteFormat.png);
    final result = Uri.parse(
      await NoteImageService.embed(png!.buffer.asUint8List()),
    );
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(result.data!.contentAsBytes()),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    expect(descriptor.width, 1600);
    expect(descriptor.height, lessThanOrEqualTo(100));
    descriptor.dispose();
    buffer.dispose();
    source.dispose();
    picture.dispose();
  });
  test(
    'image insertion escapes alt text and preserves surrounding content',
    () {
      final controller = TextEditingController(text: 'Before label After')
        ..selection = const TextSelection(baseOffset: 7, extentOffset: 12);
      MarkdownCommands.image(
        controller,
        'data:image/png;base64,AAAA',
        'unused',
      );
      expect(
        controller.text,
        'Before \n\n![label](data:image/png;base64,AAAA)\n\n After',
      );
      controller.value = const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
      MarkdownCommands.image(
        controller,
        'data:image/png;base64,AAAA',
        'name [1].png',
      );
      expect(controller.text, contains(r'![name \[1\].png]'));
      controller.dispose();
    },
  );
  test('legacy image data becomes short links and remains portable', () async {
    final bytes = await File('assets/icon/markbit.png').readAsBytes();
    final data = 'data:image/png;base64,${base64Encode(bytes)}';
    final old = Note(
      id: 'old',
      title: 'Photo',
      body: 'Text\n![photo]($data "width=50%")\nAfter',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final note = NoteImages.compact(old);
    expect(note.body.length, lessThan(150));
    expect(note.images.values.single, data);
    expect(NoteImages.expand(note), old.body);
    final restored = Note.fromJson(jsonDecode(jsonEncode(note.toJson())));
    expect(restored.images, note.images);
    expect(restored.body, note.body);
    final library = Library(
      notes: {note.id: note},
      notebooks: const [],
      tags: const [],
      templates: const [],
    );
    expect(ExportService.fileContent(note, library), contains(data));
    expect(NoteImages.width('width=50%'), 50);
    expect(NoteImages.width(null), 100);
    final root = await Directory.systemTemp.createTemp('markbit-old-image-');
    final repo = await FileLibraryRepository.open(root: root);
    await repo.saveNote(old);
    final loaded = (await repo.load()).notes.single;
    expect(loaded.body, isNot(contains('base64')));
    expect(loaded.images.values.single, data);
    await root.delete(recursive: true);
  });
  test('gallery formatting and image options stay portable in PDF', () async {
    final bytes = await File('assets/icon/markbit.png').readAsBytes();
    final data = 'data:image/png;base64,${base64Encode(bytes)}';
    final options = const ImageOptions(
      width: 50,
      align: 'right',
      rounded: true,
      caption: 'A [picture] | test',
    );
    final markdown = options.markdown('attachment:first', 'name');
    expect(markdown, contains(r'A \[picture\] &#124; test'));
    final parsed = ImageOptions.parse(options.title, alt: options.caption);
    expect(parsed.width, 50);
    expect(parsed.align, 'right');
    expect(parsed.rounded, true);
    final note = Note(
      id: 'gallery',
      title: 'Pictures',
      body:
          '| $markdown | ${const ImageOptions().markdown('attachment:second', 'Other')} |\n| --- | --- |',
      images: {'first': data, 'second': data},
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final pdf = await PdfExportService.generate(note);
    expect(latin1.decode(pdf), contains('/Image'));
    expect(NoteImages.expand(note), isNot(contains('attachment:')));
  });
  testWidgets(
    'image options stay usable in narrow light, dark and glass dialogs',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final theme in ['light', 'dark', 'zen-glass', 'glass-dark']) {
        tester.view.physicalSize = const Size(320, 560);
        ImageOptions? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(Palettes.byId(theme)),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showImageSizeDialog(context, editing: true);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final bounds = tester.getRect(find.byType(Dialog));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(320));
        expect(bounds.bottom, lessThanOrEqualTo(560));
        await tester.tap(find.text('50%'));
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(result!.width, 50);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets(
    'toolbar image action survives lost focus, renders and saves on disk',
    (tester) async {
      tester.view.physicalSize = const Size(1900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('markbit-image-'),
      ))!;
      final repo = (await tester.runAsync(
        () => FileLibraryRepository.open(root: root),
      ))!;
      var picker = Completer<NoteImage?>();
      final galleryPicker = Completer<List<NoteImage>>();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(repo),
          noteImagePickerProvider.overrideWithValue((_) => picker.future),
          noteImagesPickerProvider.overrideWithValue(
            (_) => galleryPicker.future,
          ),
          initialLibraryProvider.overrideWithValue(
            LibrarySnapshot(
              notes: [
                Note(
                  id: 'image-note',
                  title: 'Image note',
                  body: 'Before label After',
                  notebookId: 'inbox',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
              ],
              notebooks: const [
                Notebook(id: 'inbox', name: 'General', isInbox: true),
              ],
              tags: [],
              templates: [],
              isFresh: false,
            ),
          ),
        ],
      );
      container.read(openNoteProvider.notifier).open('image-note');
      container.read(notesOverviewProvider.notifier).set(false);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MarkbitApp(),
        ),
      );
      await tester.pumpAndSettle();
      final editableFinder = find.descendant(
        of: find.byType(CodeTextEditor),
        matching: find.byType(EditableText),
      );
      final editable = tester.widget<EditableText>(editableFinder);
      editable.focusNode.requestFocus();
      editable.controller.selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 12,
      );
      await tester.pumpAndSettle();
      await tapToolbarAction(tester, 'Insert image');
      picker.complete(null);
      await tester.pumpAndSettle();
      expect(
        container.read(noteProvider('image-note'))!.body,
        'Before label After',
      );
      picker = Completer<NoteImage?>();
      await tapToolbarAction(tester, 'Insert image');
      editable.focusNode.unfocus();
      await tester.pump();
      final bytes = await tester.runAsync(
        () => File('assets/icon/markbit.png').readAsBytes(),
      );
      final uri = 'data:image/png;base64,${base64Encode(bytes!)}';
      picker.complete(NoteImage('test.png', uri));
      await tester.pumpAndSettle();
      await tester.tap(find.text('50%'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      final note = container.read(noteProvider('image-note'))!;
      expect(note.body, contains('![label](attachment:'));
      expect(note.body, contains('width=50%'));
      expect(note.body.length, lessThan(150));
      expect(note.body, isNot(contains('base64')));
      expect(note.images.values.single, uri);
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect((await tester.runAsync(repo.load))!.notes.single.body, note.body);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.image is MemoryImage,
        ),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) => widget is Image && widget.image is MemoryImage,
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('25%'));
      await tester.tap(find.text('Center'));
      await tester.enterText(
        find.byKey(const ValueKey('image-caption')),
        'My image',
      );
      await tester.tap(find.byType(Switch));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        container.read(noteProvider('image-note'))!.body,
        contains('width=25%'),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('My image'), findsOneWidget);
      expect(
        container.read(noteProvider('image-note'))!.body,
        contains('align=center;rounded=1;caption=1'),
      );
      editable.focusNode.requestFocus();
      editable.controller.selection = TextSelection.collapsed(
        offset: editable.controller.text.length,
      );
      await tester.pumpAndSettle();
      await tapToolbarAction(tester, 'Add images side by side');
      galleryPicker.complete([
        NoteImage('First', uri),
        NoteImage('Second', uri),
      ]);
      await tester.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      final renderedImages = find.byWidgetPredicate(
        (w) => w is Image && w.image is MemoryImage,
      );
      expect(renderedImages, findsNWidgets(3));
      final first = tester.getTopLeft(renderedImages.at(1));
      final second = tester.getTopLeft(renderedImages.at(2));
      expect(second.dx, greaterThan(first.dx));
      expect(second.dy, closeTo(first.dy, 1));
      final withGallery = container.read(noteProvider('image-note'))!;
      expect(withGallery.images.length, 3);
      expect(withGallery.body, contains('| --- | --- |'));
      expect(withGallery.body, isNot(contains('base64')));
      expect(tester.takeException(), isNull);
      // Edit one gallery image without changing its neighbour.
      await tester.tap(renderedImages.at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('50%'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(
        container.read(noteProvider('image-note'))!.body,
        contains('![Second](attachment:'),
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1500, 1100);
      await tester.pumpAndSettle();
      final narrowFirst = tester.getTopLeft(renderedImages.at(1));
      final narrowSecond = tester.getTopLeft(renderedImages.at(2));
      expect(narrowSecond.dy, greaterThan(narrowFirst.dy));
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(renderedImages.at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove image'));
      await tester.pumpAndSettle();
      expect(renderedImages, findsNWidgets(2));
      expect(container.read(noteProvider('image-note'))!.images.length, 3);
      expect(tester.takeException(), isNull);
      var saved = false;
      container.read(persistenceProvider).flush().then((_) => saved = true);
      for (var i = 0; i < 200 && !saved; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(saved, isTrue);
      expect(
        (await tester.runAsync(repo.load))!.notes.single.body,
        container.read(noteProvider('image-note'))!.body,
      );
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.runAsync(() => root.delete(recursive: true));
    },
  );
}
