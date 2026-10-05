import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../data/note_attachment_service.dart';
import 'attachment_panel.dart';
import '../../data/note_images.dart';
import '../../core/util/ids.dart';
import 'image_size_dialog.dart';
import 'note_tabs.dart';
import 'dart:async';
import 'package:scroll_to_index/scroll_to_index.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/ai_notifier.dart';
import '../../application/library_notifier.dart';
import '../../application/providers.dart';
import '../../application/persistence_coordinator.dart';
import '../../application/runner_notifier.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/platform_info.dart';
import '../../core/util/time_ago.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../core/widgets/resize_handle.dart';
import '../../data/note_image_service.dart';
import '../../data/pdf_export_service.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/note.dart';
import '../../domain/languages.dart';
import '../../domain/markdown_utils.dart';
import '../../domain/visual_block.dart';
import '../ai/ai_panel.dart';
import '../dialogs/dialogs.dart';
import '../runner/run_panel.dart';
import 'code_text_editor.dart';
import 'format_toolbar.dart';
import 'markdown_commands.dart';
import 'note_meta_bar.dart';
import 'note_cover_header.dart';
import 'visual_block_dialog.dart';
import 'outline_panel.dart';
import 'preview/markdown_preview.dart';
import 'syntax_controller.dart';
import 'find_replace_bar.dart';
import 'note_history_dialog.dart';
import 'note_lock.dart';
import 'share_dialog.dart';
import '../shell/note_window.dart';
import '../../domain/note_tasks.dart';
import '../dialogs/task_dashboard.dart' show dueLabel;
import '../../application/shortcuts.dart';
import '../graph/graph_view.dart';
import '../../application/note_vault.dart';
import '../../core/widgets/motion.dart';

/// The right-hand pane: shows the open note or an empty state.
class EditorPane extends ConsumerWidget {
  const EditorPane({super.key, this.mobile = false});

  /// Mobile layout shows a back button instead of the focus-mode toggle.
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(openNoteIdProvider);
    final exists = id != null && ref.watch(noteProvider(id)) != null;
    if (!exists) return const _EmptyEditor();
    final secondary = ref.watch(openNoteProvider.select((s) => s.secondaryId));
    final vault = ref.watch(noteVaultProvider);
    // A locked note shows its unlock screen until the password is entered;
    // keys include the lock state so the editor starts fresh after unlocking.
    Widget editorFor(String noteId, {bool second = false}) {
      final note = ref.read(noteProvider(noteId));
      if (note != null && note.isLocked && !vault.containsKey(noteId)) {
        return LockedNoteView(
          key: ValueKey('locked:$noteId'),
          noteId: noteId,
          onBack: mobile && !second
              ? () => Navigator.of(context).maybePop()
              : null,
        );
      }
      return FadeIn(
        key: ValueKey(second ? 'fade-second:$noteId' : 'fade:$noteId'),
        from: .25,
        child: NoteEditor(
          key: ValueKey(second ? 'second:$noteId' : noteId),
          noteId: noteId,
          mobile: second ? false : mobile,
          secondary: second,
        ),
      );
    }

    ref.watch(noteProvider(id).select((n) => n?.isLocked));
    if (secondary != null) {
      ref.watch(noteProvider(secondary).select((n) => n?.isLocked));
    }
    return Column(
      children: [
        const NoteTabs(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final main = editorFor(id);
              if (secondary == null ||
                  secondary == id ||
                  ref.watch(noteProvider(secondary)) == null) {
                return main;
              }
              if (c.maxWidth < 900 && c.maxHeight < 700) {
                return Column(
                  children: [
                    Container(
                      color: context.palette.sidebarBg,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr(
                                'Widen the window to compare both notes.',
                              ),
                              style: TextStyle(
                                color: context.palette.textMuted,
                                fontSize: Fs.small,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => ref
                                .read(openNoteProvider.notifier)
                                .open(secondary),
                            child: Text(context.tr('Open second note')),
                          ),
                          IconButton(
                            tooltip: context.tr('Close split'),
                            onPressed: () =>
                                ref.read(openNoteProvider.notifier).split(null),
                            icon: const Icon(Icons.close_rounded, size: 16),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: main),
                  ],
                );
              }
              final second = editorFor(secondary, second: true);
              return c.maxWidth >= 900
                  ? Row(
                      children: [
                        Expanded(child: main),
                        VerticalDivider(
                          width: 1,
                          color: context.palette.border,
                        ),
                        Expanded(child: second),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: main),
                        Divider(height: 1, color: context.palette.border),
                        Expanded(child: second),
                      ],
                    );
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyEditor extends ConsumerWidget {
  const _EmptyEditor();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    return ColoredBox(
      color: p.editorBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_note_rounded, size: 56, color: p.textFaint),
            const SizedBox(height: Sp.md),
            Text(
              context.tr('Select a note'),
              style: TextStyle(
                color: p.text,
                fontSize: Fs.title,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: Sp.xs),
            Text(
              context.tr('or create one with {key}+N', {
                'key': PlatformInfo.modKey,
              }),
              style: TextStyle(color: p.textMuted, fontSize: Fs.body),
            ),
            const SizedBox(height: Sp.lg),
            FilledButton.icon(
              onPressed: () {
                final n = ref.read(libraryProvider.notifier).createNote();
                ref.read(openNoteProvider.notifier).open(n.id);
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(context.tr('New note')),
            ),
          ],
        ),
      ),
    );
  }
}

class NoteEditor extends ConsumerStatefulWidget {
  const NoteEditor({
    super.key,
    required this.noteId,
    this.mobile = false,
    this.secondary = false,
  });
  final String noteId;
  final bool secondary;
  final bool mobile;

  @override
  ConsumerState<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends ConsumerState<NoteEditor> {
  late final TextEditingController _title;
  late final FocusNode _titleFocus = FocusNode();
  late final FocusNode _bodyFocus = FocusNode();
  final ScrollController _editScroll = ScrollController();
  final AutoScrollController _previewScroll = AutoScrollController();
  final EditorMetrics _metrics = EditorMetrics();
  final GlobalKey _mainPaneKey = GlobalKey();
  final GlobalKey _sourceEditorKey = GlobalKey();
  final GlobalKey _previewPaneKey = GlobalKey();
  late final ValueNotifier<String> _previewText;
  late final LibraryNotifier _library;
  late final PersistenceCoordinator _persistence;

  /// Read once: [_flush] also runs from dispose, when `ref` is unusable.
  late final UnsavedNotesNotifier _unsaved;

  SyntaxController? _body;
  Timer? _saveTimer;
  Timer? _previewTimer;
  String _lastSavedBody = '';
  String _lastSavedTitle = '';
  double _runPanelHeight = 240;
  bool _dirty = false;
  bool _disposing = false;

  /// Drives the status bar's save state without rebuilding the editor.
  final ValueNotifier<bool> _dirtyState = ValueNotifier(false);

  /// True once the editor or preview is scrolled; the cover then shrinks.
  final ValueNotifier<bool> _coverCollapsed = ValueNotifier(false);
  void _syncCoverCollapse() => _coverCollapsed.value =
      _scrolledPast(_editScroll) || _scrolledPast(_previewScroll);

  @override
  void initState() {
    super.initState();
    final note = NoteImages.compact(ref.read(noteProvider(widget.noteId))!);
    _library = ref.read(libraryProvider.notifier);
    _persistence = ref.read(persistenceProvider);
    _unsaved = ref.read(unsavedNotesProvider.notifier);
    _persistence.registerEditor(this, _flush);
    _title = TextEditingController(text: note.title);
    _lastSavedBody = note.body;
    _lastSavedTitle = note.title;
    _previewText = ValueNotifier(note.body);
    _editScroll.addListener(_syncCoverCollapse);
    _previewScroll.addListener(_syncCoverCollapse);
    _bodyFocus.addListener(() {
      if (_bodyFocus.hasFocus) _activate();
    });
    _titleFocus.addListener(() {
      if (_titleFocus.hasFocus) _activate();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = ref.read(noteProvider(widget.noteId));
      if (current != null && current.body != note.body) {
        _library.setImages(widget.noteId, note.images);
        _library.updateContent(widget.noteId, body: note.body);
      }
    });

    ref.listenManual(
      noteReloadProvider.select((m) => m[widget.noteId]),
      (_, _) => _reloadFromLibrary(),
    );

    ref.listenManual(noteProvider(widget.noteId), (prev, next) {
      if (next == null) return;
      // Apply changes that did not originate from this editor (AI insert,
      // sync, import...).
      if (next.body != _lastSavedBody && next.body != _body?.text) {
        final controller = _body;
        if (controller != null) {
          final old = controller.text, selection = controller.selection;
          var prefix = 0;
          while (prefix < old.length &&
              prefix < next.body.length &&
              old.codeUnitAt(prefix) == next.body.codeUnitAt(prefix)) {
            prefix++;
          }
          var suffix = 0;
          while (suffix < old.length - prefix &&
              suffix < next.body.length - prefix &&
              old.codeUnitAt(old.length - 1 - suffix) ==
                  next.body.codeUnitAt(next.body.length - 1 - suffix)) {
            suffix++;
          }
          int shift(int offset) => offset <= prefix
              ? offset.clamp(0, next.body.length)
              : offset >= old.length - suffix
              ? (offset + next.body.length - old.length).clamp(
                  0,
                  next.body.length,
                )
              : (next.body.length - suffix).clamp(0, next.body.length);
          controller.value = TextEditingValue(
            text: next.body,
            selection: selection.isValid
                ? TextSelection(
                    baseOffset: shift(selection.baseOffset),
                    extentOffset: shift(selection.extentOffset),
                  )
                : TextSelection.collapsed(offset: next.body.length),
          );
        }
        _lastSavedBody = next.body;
        _previewText.value = next.body;
      }
      if (next.title != _lastSavedTitle && next.title != _title.text) {
        _title.text = next.title;
        _lastSavedTitle = next.title;
      }
      _body?.language = next.kind == NoteKind.code ? _languageId(next) : null;
    });

    if (note.title.isEmpty && note.body.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocus.requestFocus();
      });
    }
    // A template's {{cursor}} decides where typing starts.
    final cursor = _library.pendingCursor.remove(widget.noteId);
    if (cursor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final body = _body;
        if (!mounted || body == null) return;
        body.selection = TextSelection.collapsed(
          offset: cursor.clamp(0, body.text.length),
        );
        _bodyFocus.requestFocus();
      });
    }
  }

  String? _languageId(Note note) => Languages.find(note.language)?.id ?? 'text';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = context.palette;
    final note = ref.read(noteProvider(widget.noteId))!;
    if (_body == null) {
      _body = SyntaxController(
        text: _lastSavedBody,
        palette: p,
        language: note.kind == NoteKind.code ? _languageId(note) : null,
      );
    } else {
      _body!.palette = p;
    }
  }

  @override
  void dispose() {
    _disposing = true;
    _persistence.unregisterEditor(this);
    _saveTimer?.cancel();
    _previewTimer?.cancel();
    if (_dirty) _flush();
    _title.dispose();
    _body?.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _editScroll.dispose();
    _previewScroll.dispose();
    _coverCollapsed.dispose();
    _dirtyState.dispose();
    _previewText.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- saving

  /// Drops unsaved edits and shows the library version of the note.
  void _reloadFromLibrary() {
    final note = ref.read(noteProvider(widget.noteId));
    final body = _body;
    if (note == null || body == null) return;
    _saveTimer?.cancel();
    _dirty = false;
    _dirtyState.value = false;
    _unsaved.mark(widget.noteId, false);
    _lastSavedBody = note.body;
    _lastSavedTitle = note.title;
    body.value = TextEditingValue(
      text: note.body,
      selection: TextSelection.collapsed(
        offset: body.selection.extentOffset.clamp(0, note.body.length),
      ),
    );
    _title.text = note.title;
    _previewText.value = note.body;
    if (mounted) setState(() {});
  }

  void _onChanged() {
    if (ref.read(noteProvider(widget.noteId))?.trashed != false) return;
    if (!_dirty) _unsaved.mark(widget.noteId, true);
    ref.read(noteVaultProvider.notifier).touch(widget.noteId);
    _dirty = true;
    _dirtyState.value = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), _flush);
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(milliseconds: 220), () {
      if (mounted) _previewText.value = _body!.text;
    });
    if (mounted) setState(() {});
  }

  void _flush() {
    final body = _body;
    if (body == null) return;
    _dirty = false;
    if (!_disposing) _dirtyState.value = false;
    _unsaved.mark(widget.noteId, false);
    _lastSavedBody = body.text;
    _lastSavedTitle = _title.text;
    _library.updateContent(widget.noteId, title: _title.text, body: body.text);
  }

  // ------------------------------------------------------------- running

  void _run(String? language, String code, {String? label}) {
    final note = ref.read(noteProvider(widget.noteId));
    ref
        .read(noteRunnerProvider(widget.noteId).notifier)
        .run(
          languageName: language,
          code: code,
          sourceLabel: label ?? note?.displayTitle ?? '',
        );
  }

  void _runAtCursor() {
    final note = ref.read(noteProvider(widget.noteId));
    final body = _body;
    if (note == null || body == null) return;

    if (note.kind == NoteKind.code) {
      _run(note.language, body.text);
      return;
    }
    final blocks = splitSegments(body.text)
        .whereType<CodeSegment>()
        .where((b) => b.info != VisualBlock.fence)
        .toList();
    if (blocks.isEmpty) {
      showToast(
        context,
        context.tr('No code block in this note. Add one with ```python'),
      );
      return;
    }
    final line = MarkdownCommands.caretLine(body);
    CodeSegment? target;
    for (final b in blocks) {
      if (line >= b.startLine && line <= b.endLine) target = b;
    }
    target ??= blocks.length == 1 ? blocks.first : null;
    if (target == null) {
      showToast(
        context,
        context.tr('Place the cursor inside a code block to run it'),
      );
      return;
    }
    _run(target.info, target.code);
  }

  void _askAiAboutOutput() {
    final state = ref.read(noteRunnerProvider(widget.noteId));
    final output = ref
        .read(noteRunnerProvider(widget.noteId).notifier)
        .outputText;
    final tail = output.length > 4000
        ? output.substring(output.length - 4000)
        : output;
    ref.read(noteUiProvider(widget.noteId).notifier).ai(true);
    ref
        .read(aiProvider(widget.noteId).notifier)
        .send(
          'I ran ${state.languageName} code and got this output. '
          'Explain what happened and fix it if it failed:\n\n```\n$tail\n```',
          noteContext: _contextForAi(),
        );
  }

  String _contextForAi() {
    final note = ref.read(noteProvider(widget.noteId));
    final t = note?.displayTitle ?? '';
    final lang = note?.kind == NoteKind.code
        ? ' (${note?.language ?? 'code'})'
        : '';
    final body = _body?.text ?? '';
    final selection = _body?.selection;
    if (body.length > 11000 &&
        selection != null &&
        selection.isValid &&
        !selection.isCollapsed) {
      final start = (selection.start - 1500).clamp(0, body.length);
      final end = (selection.end + 1500).clamp(start, body.length);
      return '# $t$lang\n[Excerpt around selected passage; the remaining note is omitted.]\n\n${body.substring(start, end)}';
    }
    return '# $t$lang\n\n$body';
  }

  bool _pickingImage = false;
  bool _dropping = false;
  Future<void> _paste() async {
    if (_body == null ||
        ref.read(noteProvider(widget.noteId))?.trashed != false) {
      return;
    }
    final original = _body!.text, selection = _body!.selection;
    try {
      final bytes = await Pasteboard.image;
      if (bytes != null) {
        if (ref.read(noteProvider(widget.noteId))?.kind == NoteKind.code) {
          if (mounted) {
            showToast(
              context,
              context.tr('Paste images into a Markdown note.'),
            );
          }
          return;
        }
        final uri = await NoteImageService.embed(bytes);
        if (!mounted ||
            _body!.text != original ||
            _body!.selection != selection) {
          return;
        }
        _addImage('Clipboard.png', uri);
        return;
      }
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted ||
          _body!.text != original ||
          _body!.selection != selection ||
          data?.text == null) {
        return;
      }
      MarkdownCommands.insert(_body!, data!.text!);
      _onChanged();
    } catch (e) {
      if (mounted) showToast(context, context.tr('Could not read clipboard.'));
    }
  }

  void _addImage(String name, String uri) {
    final n = ref.read(noteProvider(widget.noteId));
    if (n == null || n.trashed) return;
    final id = newId();
    MarkdownCommands.insert(
      _body!,
      '\n\n![${name.replaceAll(RegExp(r'[\[\]\r\n]'), '_')}](attachment:$id)\n\n',
    );
    _library.updateContent(
      n.id,
      body: _body!.text,
      images: {...n.images, id: uri},
    );
    _previewText.value = _body!.text;
    _onChanged();
    _flush();
  }

  Future<void> _attachFiles([List<String>? paths]) async {
    if (_pickingImage ||
        ref.read(noteProvider(widget.noteId))?.trashed != false) {
      return;
    }
    _pickingImage = true;
    final original = _body!.text, selection = _body!.selection;
    try {
      paths ??= (await FilePicker.pickFiles(
        allowMultiple: true,
      ))?.paths.whereType<String>().toList();
      if (paths == null || paths.isEmpty) return;
      if (paths.length > 6) {
        throw const FormatException('Choose up to 6 files at a time.');
      }
      final attachments = <String, NoteAttachment>{},
          images = <String, String>{};
      final snippets = <String>[];
      for (final path in paths) {
        final id = newId();
        final name = path
            .split(RegExp(r'[/\\]'))
            .last
            .replaceAll(RegExp(r'[\[\]\r\n]'), '_');
        if (ref.read(noteProvider(widget.noteId))?.kind != NoteKind.code &&
            RegExp(
              r'\.(png|jpg|jpeg|webp|gif)$',
              caseSensitive: false,
            ).hasMatch(path)) {
          final file = File(path);
          if (await file.length() > 10 * 1024 * 1024) {
            throw const FormatException('Choose an image smaller than 10 MB.');
          }
          images[id] = await NoteImageService.embed(await file.readAsBytes());
          snippets.add('![$name](attachment:$id)');
        } else {
          attachments[id] = await NoteAttachmentService.read(path);
          snippets.add('[$name](markbit://attachment/$id)');
        }
      }
      if (!mounted ||
          _body!.text != original ||
          _body!.selection != selection ||
          ref.read(noteProvider(widget.noteId))?.trashed != false) {
        return;
      }
      final n = ref.read(noteProvider(widget.noteId))!;
      if (n.attachments.values.fold<int>(0, (sum, a) => sum + a.size) +
              attachments.values.fold<int>(0, (sum, a) => sum + a.size) >
          50 * 1024 * 1024) {
        throw const FormatException(
          'Attachments in a note can total up to 50 MB.',
        );
      }
      if (n.kind != NoteKind.code) {
        MarkdownCommands.insert(_body!, '\n\n${snippets.join('\n\n')}\n\n');
      }
      _library.updateContent(
        n.id,
        body: _body!.text,
        images: {...n.images, ...images},
        attachments: {...n.attachments, ...attachments},
      );
      _previewText.value = _body!.text;
      _onChanged();
      _flush();
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          context.tr(
            e is FormatException ? e.message : 'Could not attach files.',
          ),
        );
      }
    } finally {
      _pickingImage = false;
    }
  }

  Future<void> _insertImage() async {
    if (_pickingImage ||
        _body == null ||
        ref.read(noteProvider(widget.noteId))?.trashed != false) {
      return;
    }
    _pickingImage = true;
    final controller = _body!;
    final original = controller.text;
    final selection = controller.selection;
    try {
      final image = await ref.read(noteImagePickerProvider)(
        context.tr('Choose image'),
      );
      if (image == null ||
          !mounted ||
          ref.read(noteProvider(widget.noteId))?.trashed != false) {
        return;
      }
      if (controller.text != original) {
        showToast(
          context,
          context.tr(
            'The note changed while choosing an image. Please try again.',
          ),
        );
        return;
      }
      final options = await showImageSizeDialog(context);
      if (options == null ||
          !mounted ||
          controller.text != original ||
          ref.read(noteProvider(widget.noteId))?.trashed != false) {
        return;
      }
      final id = newId();
      final note = ref.read(noteProvider(widget.noteId))!;
      controller.selection = selection;
      final label = selection.isValid && !selection.isCollapsed
          ? original.substring(selection.start, selection.end)
          : image.name;
      MarkdownCommands.insert(
        controller,
        '\n\n${options.markdown('attachment:$id', label)}\n\n',
      );
      _library.updateContent(
        widget.noteId,
        body: controller.text,
        images: {...note.images, id: image.uri},
      );
      _previewText.value = controller.text;
      _onChanged();
      _flush();
      _bodyFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          context.tr(
            e is FormatException ? e.message : 'Could not open this image.',
          ),
        );
      }
    } finally {
      _pickingImage = false;
    }
  }

  Future<void> _insertGallery() async {
    if (_pickingImage ||
        _body == null ||
        ref.read(noteProvider(widget.noteId))?.trashed != false) {
      return;
    }
    _pickingImage = true;
    final controller = _body!;
    final original = controller.text;
    final selection = controller.selection;
    try {
      final picked = await ref.read(noteImagesPickerProvider)(
        context.tr('Add images side by side'),
      );
      if (picked.isEmpty ||
          !mounted ||
          ref.read(noteProvider(widget.noteId))?.trashed != false) {
        return;
      }
      if (controller.text != original) {
        showToast(
          context,
          context.tr(
            'The note changed while choosing an image. Please try again.',
          ),
        );
        return;
      }
      final note = ref.read(noteProvider(widget.noteId))!;
      final images = Map<String, String>.of(note.images);
      final cells = <String>[];
      for (final image in picked) {
        final id = newId();
        images[id] = image.uri;
        cells.add(
          const ImageOptions(
            rounded: true,
          ).markdown('attachment:$id', image.name),
        );
      }
      final row = StringBuffer();
      if (cells.length == 1) {
        row.writeln(cells.single);
      } else {
        row.writeln('| ${cells.take(2).join(' | ')} |');
        row.writeln('| --- | --- |');
        for (var i = 2; i < cells.length; i += 2) {
          row.writeln(
            '| ${cells[i]} | ${i + 1 < cells.length ? cells[i + 1] : ''} |',
          );
        }
      }
      controller.selection = selection;
      MarkdownCommands.insert(controller, '\n\n$row\n');
      _library.updateContent(
        widget.noteId,
        body: controller.text,
        images: images,
      );
      _previewText.value = controller.text;
      _onChanged();
      _flush();
      _bodyFocus.requestFocus();
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          context.tr(
            e is FormatException ? e.message : 'Could not open this image.',
          ),
        );
      }
    } finally {
      _pickingImage = false;
    }
  }

  Future<void> _resizeImage(
    String uri,
    String? title,
    int line,
    int occurrence,
  ) async {
    final controller = _body!;
    final original = controller.text;
    final offset = original
        .split('\n')
        .take(line)
        .fold<int>(0, (n, s) => n + s.length + 1);
    final pattern = RegExp(
      r'!\[(?:\\.|[^\]])*\]\(' +
          RegExp.escape(uri) +
          (title == null || title.isEmpty ? '' : ' "${RegExp.escape(title)}"') +
          r'\)',
    );
    final match = pattern
        .allMatches(original, offset)
        .elementAtOrNull(occurrence);
    if (match == null) return;
    final image = match[0]!;
    final alt = image
        .substring(2, image.indexOf(']('))
        .replaceAll(r'\[', '[')
        .replaceAll(r'\]', ']')
        .replaceAll(r'\\', r'\')
        .replaceAll('&#124;', '|');
    final options = await showImageSizeDialog(
      context,
      initial: ImageOptions.parse(title, alt: alt),
      editing: true,
    );
    if (options == null ||
        !mounted ||
        controller.text != original ||
        ref.read(noteProvider(widget.noteId))?.trashed != false) {
      return;
    }
    final replacement = options.remove ? '' : options.markdown(uri, alt);
    controller.value = TextEditingValue(
      text: original.replaceRange(match.start, match.end, replacement),
      selection: TextSelection.collapsed(
        offset: match.start + replacement.length,
      ),
    );
    _previewText.value = controller.text;
    _onChanged();
    _flush();
  }

  void _insertFromAi(String text) {
    if (ref.read(noteProvider(widget.noteId))?.trashed != false) return;
    final c = _body!;
    final sel = c.selection;
    final at = sel.isValid ? sel.end : c.text.length;
    final prefix = at > 0 && c.text[at - 1] != '\n' ? '\n\n' : '';
    final snippet = '$prefix$text\n';
    c.value = TextEditingValue(
      text: c.text.replaceRange(at, at, snippet),
      selection: TextSelection.collapsed(offset: at + snippet.length),
    );
    _onChanged();
    showToast(context, context.tr('Inserted into note'));
  }

  Future<void> _insertVisual(VisualKind kind) async {
    final block = await showVisualBlockDialog(context, kind: kind);
    if (!mounted || block == null) return;
    _insertFromAi(block.markdown);
    _previewText.value = _body!.text;
    _flush();
    final mode = ref.read(noteUiProvider(widget.noteId)).mode;
    final canSplit = (context.size?.width ?? 0) >= _minSplitWidth;
    if (mode == ViewMode.edit || (mode == ViewMode.split && !canSplit)) {
      ref
          .read(noteUiProvider(widget.noteId).notifier)
          .mode(canSplit ? ViewMode.split : ViewMode.preview);
    }
  }

  Future<void> _editVisual(CodeSegment segment) async {
    final source = _body!.text;
    final initial = VisualBlock.parse(segment.code);
    if (initial == null) {
      showToast(context, context.tr('Check the block data in the editor.'));
      return;
    }
    final updated = await showVisualBlockDialog(context, initial: initial);
    if (!mounted || updated == null) return;
    if (_body!.text != source) {
      showToast(context, context.tr('The note changed. Open the block again.'));
      return;
    }
    final lines = source.split('\n');
    lines.replaceRange(
      segment.startLine,
      segment.endLine + 1,
      updated.markdown.split('\n'),
    );
    _body!.text = lines.join('\n');
    _previewText.value = _body!.text;
    _onChanged();
    _flush();
  }

  void _jumpToLine(int line) {
    if (!_editScroll.hasClients) return;
    final y = _metrics.offsetOfLine(line) - 24;
    _editScroll.animateTo(
      y.clamp(0, _editScroll.position.maxScrollExtent),
      duration: Motion.slow,
      curve: Motion.curve,
    );
    final mode = ref.read(noteUiProvider(widget.noteId)).mode;
    if (mode == ViewMode.preview) {
      ref.read(noteUiProvider(widget.noteId).notifier).mode(ViewMode.split);
    }
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final note = ref.watch(noteProvider(widget.noteId));
    if (note == null || _body == null) return const SizedBox.shrink();
    final settings = ref.watch(settingsProvider);
    final mode = ref.watch(noteUiProvider(widget.noteId)).mode;
    final runner = ref.watch(noteRunnerProvider(widget.noteId));
    final outlineOn = ref.watch(
      noteUiProvider(widget.noteId).select((s) => s.outline),
    );
    final aiOn = ref.watch(noteUiProvider(widget.noteId).select((s) => s.ai));
    final isCode = note.kind == NoteKind.code;
    final searching = ref.watch(
      noteUiProvider(widget.noteId).select((s) => s.search),
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _activate(),
      child: ColoredBox(
        color: p.editorBg,
        child: LayoutBuilder(
          builder: (context, cons) {
            final wide = cons.maxWidth >= 760;
            final aiWidth = ref
                .watch(noteUiProvider(widget.noteId).select((s) => s.aiWidth))
                .clamp(320.0, (cons.maxWidth - 327).clamp(320.0, 640.0));
            final mainWidth = wide && aiOn
                ? cons.maxWidth - aiWidth - 7
                : cons.maxWidth;

            final main = Column(
              key: _mainPaneKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  mobile: widget.mobile,
                  secondary: widget.secondary,
                  note: note,
                  isCode: isCode,
                  mode: mode,
                  canSplit: mainWidth >= _minSplitWidth,
                  onFlush: _flush,
                  onRun: _runAtCursor,
                  showRun: isCode
                      ? (Languages.find(note.language)?.runnable ?? false)
                      : splitSegments(_body!.text).whereType<CodeSegment>().any(
                          (b) => b.info != VisualBlock.fence,
                        ),
                  onExport: () => showShareDialog(
                    context,
                    ref.read(noteProvider(note.id)) ?? note,
                  ),
                  getBody: () => _body!.text,
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([_coverCollapsed, _titleFocus]),
                  builder: (context, _) => NoteCoverHeader(
                    note: note,
                    controller: _title,
                    focusNode: _titleFocus,
                    onChanged: _onChanged,
                    onSubmitted: () => _bodyFocus.requestFocus(),
                    onCoverChanged: (image) =>
                        _library.setCover(widget.noteId, image),
                    collapsed: _coverCollapsed.value,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Sp.lg,
                    Sp.xs,
                    Sp.xl,
                    Sp.sm,
                  ),
                  child: NoteMetaBar(noteId: widget.noteId),
                ),
                if (note.attachments.isNotEmpty) AttachmentPanel(note: note),
                if (note.trashed) _TrashBanner(noteId: widget.noteId),
                if (searching)
                  FindReplaceBar(
                    controller: _body!,
                    replace: ref.watch(
                      noteUiProvider(widget.noteId).select((s) => s.replace),
                    ),
                    readOnly: note.trashed,
                    onChanged: _onChanged,
                    onClose: () => ref
                        .read(noteUiProvider(widget.noteId).notifier)
                        .search(false),
                    onNavigate: (range) => _jumpToLine(
                      '\n'
                          .allMatches(_body!.text.substring(0, range.start))
                          .length,
                    ),
                  ),
                Expanded(
                  child: _buildBody(
                    context,
                    note,
                    settings,
                    mode,
                    isCode,
                    mainWidth,
                  ),
                ),
                if (runner.panelVisible) ...[
                  ResizeHandle(
                    axis: Axis.vertical,
                    onDrag: (dy) => setState(() {
                      _runPanelHeight = (_runPanelHeight - dy).clamp(
                        120.0,
                        cons.maxHeight * 0.7,
                      );
                    }),
                  ),
                  SizedBox(
                    height: _runPanelHeight,
                    child: RunPanel(
                      noteId: widget.noteId,
                      onRerun:
                          ref
                              .read(noteRunnerProvider(widget.noteId).notifier)
                              .canRerun
                          ? ref
                                .read(
                                  noteRunnerProvider(widget.noteId).notifier,
                                )
                                .rerun
                          : null,
                      onAskAi: _askAiAboutOutput,
                    ),
                  ),
                ],
                _StatusBar(
                  noteId: widget.noteId,
                  dirty: _dirtyState,
                  controller: _body!,
                  isCode: isCode,
                  language: Languages.find(note.language)?.name,
                ),
              ],
            );

            Widget? side;
            if (aiOn) {
              side = AiPanel(
                key: ValueKey(widget.noteId),
                noteId: widget.noteId,
                noteTitle: note.displayTitle,
                width: wide ? aiWidth : cons.maxWidth,
                expanded: aiWidth > 360,
                onToggleWidth: wide
                    ? () {
                        final sizing = ref.read(
                          noteUiProvider(widget.noteId).notifier,
                        );
                        sizing.aiWidth(aiWidth > 360 ? 360 : 640);
                        sizing.persistWidth();
                      }
                    : null,
                noteContext: _contextForAi,
                onInsert: _insertFromAi,
                noteBody: () => _body?.text ?? '',
                onApplyEdit: (expected, updated) {
                  if (!mounted ||
                      _body == null ||
                      _body!.text != expected ||
                      ref.read(noteProvider(widget.noteId))?.trashed != false) {
                    return false;
                  }
                  _body!.value = TextEditingValue(
                    text: updated,
                    selection: TextSelection.collapsed(offset: updated.length),
                  );
                  _previewText.value = updated;
                  _onChanged();
                  _flush();
                  return true;
                },
                onClose: () =>
                    ref.read(noteUiProvider(widget.noteId).notifier).ai(false),
              );
            } else if (outlineOn && !isCode) {
              side = ValueListenableBuilder<String>(
                valueListenable: _previewText,
                builder: (_, body, _) => OutlinePanel(
                  note: note,
                  body: body,
                  onJump: _jumpToLine,
                  onOpenNote: _openInPane,
                  onClose: () => ref
                      .read(noteUiProvider(widget.noteId).notifier)
                      .outline(false),
                ),
              );
            }

            if (side == null) return main;
            side = FadeIn(
              key: ValueKey(aiOn ? 'side-ai' : 'side-outline'),
              offset: const Offset(.04, 0),
              child: side,
            );
            if (wide) {
              return Row(
                children: [
                  Expanded(child: main),
                  if (aiOn)
                    ResizeHandle(
                      key: const ValueKey('ai-panel-resize'),
                      onDrag: (dx) => ref
                          .read(noteUiProvider(widget.noteId).notifier)
                          .aiWidth(
                            (aiWidth - dx).clamp(
                              320.0,
                              (cons.maxWidth - 327).clamp(320.0, 640.0),
                            ),
                          ),
                      onEnd: () => ref
                          .read(noteUiProvider(widget.noteId).notifier)
                          .persistWidth(),
                    ),
                  side,
                ],
              );
            }
            return Stack(
              children: [
                // A narrow assistant/outline is a separate full-width view.
                Positioned.fill(child: side),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _scrolledPast(ScrollController c) =>
      c.hasClients && c.positions.any((p) => p.pixels > 24);

  void _activate() => ref.read(editorFocusProvider.notifier).set(widget.noteId);
  void _openInPane(String id) {
    _flush();
    if (widget.secondary) {
      ref.read(openNoteProvider.notifier).split(id);
    } else {
      ref.read(openNoteProvider.notifier).open(id);
    }
  }

  Widget _buildBody(
    BuildContext context,
    Note note,
    AppSettings settings,
    ViewMode mode,
    bool isCode,
    double paneWidth,
  ) {
    final p = context.palette;
    final body = _body!;
    final canSplit = paneWidth >= _minSplitWidth;
    final effective = isCode
        ? ViewMode.edit
        : (mode == ViewMode.split && !canSplit ? ViewMode.edit : mode);

    final editor = DropTarget(
      onDragEntered: (_) => setState(() => _dropping = true),
      onDragExited: (_) => setState(() => _dropping = false),
      onDragDone: (details) {
        setState(() => _dropping = false);
        _attachFiles(details.files.map((f) => f.path).toList());
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: _dropping
              ? Border.all(color: context.palette.accent, width: 2)
              : null,
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                _paste,
            const SingleActivator(LogicalKeyboardKey.keyV, meta: true): _paste,
          },
          child: CodeTextEditor(
            key: _sourceEditorKey,
            controller: body,
            focusNode: _bodyFocus,
            scrollController: _editScroll,
            metrics: _metrics,
            fontSize: settings.editorFontSize,
            showLineNumbers: settings.lineNumbers,
            isCode: isCode,
            markdownSuggestions: settings.markdownSuggestions,
            completionNoteTitles: () => ref
                .read(libraryProvider)
                .notes
                .values
                .where((n) => !n.trashed && n.id != widget.noteId)
                .map((n) => n.displayTitle),
            completionImageUris: () =>
                note.images.keys.map((id) => 'attachment:$id'),
            readOnly: note.trashed,
            hint: isCode
                ? context.tr('Write code\u2026')
                : context.tr('Write in Markdown\u2026'),
            onChanged: (_) => _onChanged(),
            onRun: _runAtCursor,
            shortcuts: ref.watch(shortcutsProvider),
          ),
        ),
      ),
    );

    final editorArea = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isCode && !note.trashed)
          TextFieldTapRegion(
            child: FormatToolbar(
              controller: body,
              focusNode: _bodyFocus,
              onChanged: (_) => _onChanged(),
              onInsertImage: _insertImage,
              onAttachFile: _attachFiles,
              onInsertGallery: _insertGallery,
              onInsertVisual: _insertVisual,
            ),
          ),
        Expanded(child: editor),
      ],
    );

    final preview = ValueListenableBuilder<String>(
      valueListenable: _previewText,
      builder: (context, text, _) {
        final lib = ref.read(libraryProvider);
        return MarkdownPreview(
          key: _previewPaneKey,
          noteId: widget.noteId,
          body: text,
          images: note.images,
          attachments: note.attachments,
          onEditImage: note.trashed ? null : _resizeImage,
          scrollController: _previewScroll,
          resolveNoteId: lib.findNoteIdByTitle,
          onOpenNote: _openInPane,
          onCreateNote: (title) {
            final n = ref
                .read(libraryProvider.notifier)
                .createNote(title: title, notebookId: note.notebookId);
            _openInPane(n.id);
          },
          onRun: (lang, code) => _run(lang, code),
          onEditVisual: note.trashed ? null : _editVisual,
          onToggleTask: note.trashed
              ? null
              : (line, checked) {
                  // Repeating tasks move to their next date instead.
                  final (body, next) = toggleTaskLine(
                    note.copyWith(body: _body!.text),
                    line,
                    checked,
                  );
                  _body!.text = body;
                  _previewText.value = _body!.text;
                  _onChanged();
                  _flush();
                  if (next != null && context.mounted) {
                    showToast(
                      context,
                      context.tr('Repeats: next on {date}', {
                        'date': dueLabel(context, next),
                      }),
                    );
                  }
                },
        );
      },
    );

    return FadeIn(
      key: ValueKey(effective),
      from: .35,
      child: switch (effective) {
        ViewMode.edit => editorArea,
        ViewMode.preview => preview,
        ViewMode.split => Row(
          children: [
            Expanded(child: editorArea),
            VerticalDivider(width: 1, color: p.border),
            Expanded(child: preview),
          ],
        ),
      },
    );
  }
}

/// Narrowest editor pane that can show source and preview side by side.
const double _minSplitWidth = 640;

// ------------------------------------------------------------------ header

class _Header extends ConsumerWidget {
  const _Header({
    this.secondary = false,
    required this.mobile,
    required this.note,
    required this.isCode,
    required this.mode,
    required this.canSplit,
    required this.onFlush,
    required this.onRun,
    required this.showRun,
    required this.onExport,
    required this.getBody,
  });

  final bool mobile, secondary;
  final Note note;
  final bool isCode;
  final ViewMode mode;
  final bool canSplit;
  final VoidCallback onFlush;
  final VoidCallback onRun;
  final bool showRun;
  final VoidCallback onExport;
  final String Function() getBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final nav = ref.watch(openNoteProvider);
    final focus = ref.watch(focusModeProvider);
    final outline = ref.watch(noteUiProvider(note.id).select((s) => s.outline));
    final ai = ref.watch(noteUiProvider(note.id).select((s) => s.ai));
    final running = ref.watch(
      noteRunnerProvider(note.id).select((s) => s.isBusy),
    );
    final library = ref.read(libraryProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
            child: Row(
              children: [
                if (secondary)
                  AppIconButton(
                    icon: Icons.close_rounded,
                    tooltip: context.tr('Close split'),
                    onPressed: () {
                      onFlush();
                      ref.read(openNoteProvider.notifier).split(null);
                    },
                  )
                else if (mobile)
                  AppIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: context.tr('Back to notes'),
                    onPressed: () {
                      onFlush();
                      Navigator.of(context).maybePop();
                    },
                  )
                else
                  AppIconButton(
                    icon: focus
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded,
                    tooltip: focus
                        ? context.tr('Exit focus mode')
                        : context.tr('Focus mode'),
                    active: focus,
                    onPressed: () =>
                        ref.read(focusModeProvider.notifier).toggle(),
                  ),
                if (!mobile &&
                    !compact &&
                    !secondary &&
                    ref.watch(noteWindowProvider) == null) ...[
                  AppIconButton(
                    icon: Icons.view_list_outlined,
                    tooltip: context.tr(
                      ref.watch(noteListVisibleProvider)
                          ? 'Hide note list'
                          : 'Show note list',
                    ),
                    onPressed: () =>
                        ref.read(noteListVisibleProvider.notifier).toggle(),
                  ),
                  AppIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: context.tr('Previous note'),
                    onPressed: nav.canBack
                        ? ref.read(openNoteProvider.notifier).back
                        : null,
                  ),
                  AppIconButton(
                    icon: Icons.arrow_forward_rounded,
                    tooltip: context.tr('Next note'),
                    onPressed: nav.canForward
                        ? ref.read(openNoteProvider.notifier).forward
                        : null,
                  ),
                ],
                Expanded(
                  child: Center(
                    child: isCode
                        ? const SizedBox.shrink()
                        : FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _ModeSwitcher(
                              // Show what is actually on screen: a narrow
                              // pane renders "split" as the editor alone.
                              mode: mode == ViewMode.split && !canSplit
                                  ? ViewMode.edit
                                  : mode,
                              canSplit: canSplit,
                              noteId: note.id,
                            ),
                          ),
                  ),
                ),
                if (showRun && !compact)
                  Padding(
                    padding: const EdgeInsets.only(right: Sp.xs),
                    child: _RunChip(
                      running: running,
                      onPressed: running ? null : onRun,
                    ),
                  ),
                if (!mobile && !compact && !isCode)
                  AppIconButton(
                    icon: Icons.list_alt_rounded,
                    tooltip: context.tr('Outline & backlinks'),
                    active: outline,
                    onPressed: () => ref
                        .read(noteUiProvider(note.id).notifier)
                        .toggleOutline(),
                  ),
                if (!mobile)
                  AppIconButton(
                    icon: Icons.auto_awesome_rounded,
                    tooltip: context.tr('AI assistant'),
                    active: ai,
                    onPressed: () =>
                        ref.read(noteUiProvider(note.id).notifier).toggleAi(),
                  ),
                PopupMenuButton<String>(
                  borderRadius: BorderRadius.circular(Rad.md),
                  tooltip: context.tr('More'),
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: p.textMuted,
                    size: 20,
                  ),
                  onSelected: (v) async {
                    switch (v) {
                      case 'outline':
                        ref
                            .read(noteUiProvider(note.id).notifier)
                            .toggleOutline();
                      case 'list':
                        ref.read(noteListVisibleProvider.notifier).toggle();
                      case 'previous':
                        ref.read(openNoteProvider.notifier).back();
                      case 'next':
                        ref.read(openNoteProvider.notifier).forward();
                      case 'run':
                        onRun();
                      case 'ai':
                        ref.read(noteUiProvider(note.id).notifier).toggleAi();
                      case 'pin':
                        library.togglePin(note.id);
                      case 'star':
                        library.toggleStar(note.id);
                      case 'window':
                        await openNoteWindow(context, ref, note.id);
                      case 'graph':
                        onFlush();
                        await showGraphView(context, focusId: note.id);
                      case 'duplicate':
                        onFlush();
                        final copy = library.duplicate(note.id);
                        if (copy != null) {
                          if (secondary) {
                            ref.read(openNoteProvider.notifier).split(copy.id);
                          } else {
                            ref.read(openNoteProvider.notifier).open(copy.id);
                          }
                        }
                      case 'copy':
                        await Clipboard.setData(ClipboardData(text: getBody()));
                        if (context.mounted) {
                          showToast(context, context.tr('Copied to clipboard'));
                        }
                      case 'export':
                        onFlush();
                        onExport();
                      case 'find':
                      case 'replace':
                        ref.read(noteUiProvider(note.id).notifier).ai(false);
                        ref
                            .read(noteUiProvider(note.id).notifier)
                            .mode(ViewMode.edit);
                        ref
                            .read(noteUiProvider(note.id).notifier)
                            .search(true, replace: v == 'replace');
                      case 'history':
                        onFlush();
                        await showNoteHistory(context, ref, note.id);
                      case 'lock':
                        onFlush();
                        if (await showLockNoteDialog(context, note.id) &&
                            context.mounted) {
                          showToast(context, context.tr('Note locked'));
                        }
                      case 'relock':
                        ref.read(noteVaultProvider.notifier).lock(note.id);
                      case 'unlock':
                        await confirmRemoveLock(context, ref, note.id);
                      case 'pdf':
                      case 'print':
                        onFlush();
                        final current = ref.read(noteProvider(note.id));
                        if (current != null) {
                          await PdfExportService.export(
                            context,
                            current,
                            print: v == 'print',
                          );
                        }
                      case 'template':
                        final name = await promptText(
                          context,
                          title: context.tr('Save as template'),
                          initial: note.displayTitle,
                          hint: context.tr('Template name'),
                        );
                        if (name != null) {
                          library.saveTemplate(
                            name: name,
                            title: note.title,
                            body: getBody(),
                            notebookId: note.notebookId,
                            tagIds: note.tagIds,
                            images: note.images,
                            attachments: note.attachments,
                          );
                          if (context.mounted) {
                            showToast(context, context.tr('Template saved'));
                          }
                        }
                      case 'info':
                        if (context.mounted) _showInfo(context, getBody());
                      case 'trash':
                        onFlush();
                        library.trash(note.id);
                        if (mobile && context.mounted) {
                          Navigator.of(context).maybePop();
                        }
                        if (context.mounted) {
                          showToast(
                            context,
                            context.tr('Moved to trash'),
                            actionLabel: context.tr('Undo'),
                            onAction: () => library.restore(note.id),
                          );
                        }
                    }
                  },
                  itemBuilder: (ctx) => [
                    _item('find', Icons.search, ctx.tr('Find in note'), p),
                    if (!note.trashed)
                      _item(
                        'replace',
                        Icons.find_replace,
                        ctx.tr('Find and replace'),
                        p,
                      ),
                    if (!note.isLocked)
                      _item(
                        'history',
                        Icons.history,
                        ctx.tr('Version history'),
                        p,
                      ),
                    _item(
                      'pdf',
                      Icons.picture_as_pdf_outlined,
                      ctx.tr('Export PDF'),
                      p,
                    ),
                    _item('print', Icons.print_outlined, ctx.tr('Print'), p),
                    if (compact && !mobile && !secondary) ...[
                      _item(
                        'list',
                        Icons.view_list_outlined,
                        ctx.tr(
                          ref.read(noteListVisibleProvider)
                              ? 'Hide note list'
                              : 'Show note list',
                        ),
                        p,
                      ),
                      if (nav.canBack)
                        _item(
                          'previous',
                          Icons.arrow_back_rounded,
                          ctx.tr('Previous note'),
                          p,
                        ),
                      if (nav.canForward)
                        _item(
                          'next',
                          Icons.arrow_forward_rounded,
                          ctx.tr('Next note'),
                          p,
                        ),
                      if (showRun && !running)
                        _item(
                          'run',
                          Icons.play_arrow_rounded,
                          ctx.tr('Run'),
                          p,
                        ),
                    ],
                    if (mobile || compact) ...[
                      if (!isCode)
                        _item(
                          'outline',
                          Icons.list_alt_rounded,
                          ctx.tr('Outline & backlinks'),
                          p,
                        ),
                      _item(
                        'ai',
                        Icons.auto_awesome_rounded,
                        ctx.tr('AI assistant'),
                        p,
                      ),
                      const PopupMenuDivider(),
                    ],
                    _item(
                      'pin',
                      note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      note.pinned ? ctx.tr('Unpin') : ctx.tr('Pin to top'),
                      p,
                    ),
                    _item(
                      'star',
                      note.starred
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      note.starred
                          ? ctx.tr('Remove from starred')
                          : ctx.tr('Add to starred'),
                      p,
                    ),
                    _item(
                      'duplicate',
                      Icons.copy_all_rounded,
                      ctx.tr('Duplicate'),
                      p,
                    ),
                    if (canOpenNoteWindows &&
                        ref.read(noteWindowProvider) == null)
                      _item(
                        'window',
                        Icons.open_in_new_rounded,
                        ctx.tr('Open in new window'),
                        p,
                      ),
                    if (!isCode)
                      _item(
                        'graph',
                        Icons.hub_outlined,
                        ctx.tr('Show in link graph'),
                        p,
                      ),
                    _item(
                      'copy',
                      Icons.content_copy_rounded,
                      ctx.tr('Copy contents'),
                      p,
                    ),
                    _item(
                      'export',
                      Icons.ios_share_rounded,
                      ctx.tr('Export and share…'),
                      p,
                    ),
                    _item(
                      'template',
                      Icons.dashboard_customize_outlined,
                      ctx.tr('Save as template'),
                      p,
                    ),
                    _item(
                      'info',
                      Icons.info_outline_rounded,
                      ctx.tr('Note info'),
                      p,
                    ),
                    const PopupMenuDivider(),
                    if (!note.trashed && !note.isLocked)
                      _item(
                        'lock',
                        Icons.lock_outline_rounded,
                        ctx.tr('Lock with password\u2026'),
                        p,
                      ),
                    if (note.isLocked) ...[
                      _item(
                        'relock',
                        Icons.lock_rounded,
                        ctx.tr('Lock now'),
                        p,
                      ),
                      _item(
                        'unlock',
                        Icons.lock_open_rounded,
                        ctx.tr('Remove lock\u2026'),
                        p,
                      ),
                    ],
                    _item(
                      'trash',
                      Icons.delete_outline_rounded,
                      ctx.tr('Move to trash'),
                      p,
                      color: p.danger,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PopupMenuItem<String> _item(
    String v,
    IconData icon,
    String label,
    AppPalette p, {
    Color? color,
  }) => PopupMenuItem<String>(
    value: v,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color ?? p.textMuted),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color)),
      ],
    ),
  );

  void _showInfo(BuildContext context, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: Icons.info_outline_rounded,
        title: ctx.tr('Note info'),
        subtitle: note.displayTitle,
        width: 440,
        content: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.md,
            vertical: Sp.xs,
          ),
          decoration: BoxDecoration(
            color: ctx.palette.codeBg,
            borderRadius: BorderRadius.circular(Rad.lg),
            border: Border.all(color: ctx.palette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(
                ctx,
                ctx.tr('Created'),
                '${note.createdAt.toLocal()}'.split('.').first,
              ),
              _infoRow(
                ctx,
                ctx.tr('Updated'),
                '${timeAgo(note.updatedAt)} (${note.updatedAt.toLocal()})'
                    .replaceAll(RegExp(r'\.\d+'), ''),
              ),
              _infoRow(ctx, ctx.tr('Words'), '${wordCount(body)}'),
              _infoRow(ctx, ctx.tr('Characters'), '${body.length}'),
              _infoRow(
                ctx,
                ctx.tr('Lines'),
                '${'\n'.allMatches(body).length + 1}',
              ),
              _infoRow(ctx, 'ID', note.id),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('Close')),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Sp.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            k,
            style: TextStyle(
              color: context.palette.textMuted,
              fontSize: Fs.small,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: TextStyle(
              color: context.palette.text,
              fontSize: Fs.small,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RunChip extends StatelessWidget {
  const _RunChip({required this.running, required this.onPressed});
  final bool running;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: context.tr('Run ({key}+Enter)', {'key': PlatformInfo.modKey}),
      child: Material(
        color: p.success.withValues(alpha: onPressed == null ? 0.10 : 0.18),
        borderRadius: BorderRadius.circular(Rad.md),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Rad.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (running)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.success,
                    ),
                  )
                else
                  Icon(Icons.play_arrow_rounded, size: 18, color: p.success),
                const SizedBox(width: 4),
                Text(
                  context.tr('Run'),
                  style: TextStyle(
                    color: p.success,
                    fontWeight: FontWeight.w700,
                    fontSize: Fs.small,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSwitcher extends ConsumerWidget {
  const _ModeSwitcher({
    required this.mode,
    required this.noteId,
    this.canSplit = true,
  });
  final ViewMode mode;
  final String noteId;
  final bool canSplit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    Widget seg(ViewMode m, IconData icon, String tip, {bool enabled = true}) {
      final selected = mode == m;
      return Tooltip(
        message: tip,
        child: Semantics(
          button: true,
          enabled: enabled,
          selected: selected,
          label: tip,
          child: InkWell(
            borderRadius: BorderRadius.circular(Rad.sm),
            onTap: enabled
                ? () => ref.read(noteUiProvider(noteId).notifier).mode(m)
                : null,
            child: AnimatedContainer(
              duration: Motion.fast,
              width: 44,
              height: 34,
              decoration: BoxDecoration(
                color: selected
                    ? p.accent.withValues(alpha: 0.16)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
              child: Icon(
                icon,
                size: 19,
                color: selected
                    ? p.accent
                    : enabled
                    ? p.textMuted
                    : p.textFaint.withValues(alpha: .45),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(ViewMode.edit, Icons.edit_outlined, context.tr('Editor')),
          seg(
            ViewMode.split,
            Icons.vertical_split_outlined,
            canSplit
                ? context.tr('Split view')
                : context.tr('Split view needs a wider pane'),
            enabled: canSplit,
          ),
          seg(
            ViewMode.preview,
            Icons.visibility_outlined,
            context.tr('Preview'),
          ),
        ],
      ),
    );
  }
}

class _TrashBanner extends ConsumerWidget {
  const _TrashBanner({required this.noteId});
  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final lib = ref.read(libraryProvider.notifier);
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: p.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: p.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.delete_outline_rounded, size: 18, color: p.danger),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              context.tr('This note is in the trash and is read-only.'),
              style: TextStyle(color: p.text, fontSize: Fs.small),
            ),
          ),
          TextButton(
            onPressed: () => lib.restore(noteId),
            child: Text(context.tr('Restore')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: p.danger),
            onPressed: () async {
              final ok = await confirmAction(
                context,
                title: context.tr('Delete permanently?'),
                message: context.tr('This note will be removed for good.'),
              );
              if (ok) {
                ref.read(openNoteProvider.notifier).close();
                lib.deleteForever(noteId);
              }
            },
            child: Text(context.tr('Delete forever')),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatefulWidget {
  const _StatusBar({
    required this.noteId,
    required this.dirty,
    required this.controller,
    required this.isCode,
    required this.language,
  });

  final String noteId;
  final ValueListenable<bool> dirty;
  final SyntaxController controller;
  final bool isCode;
  final String? language;

  @override
  State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> {
  String? _countedText;
  int _words = 0;
  List<int> _starts = [0];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(color: p.textFaint, fontSize: Fs.caption);
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final text = widget.controller.text;
          if (_countedText != text) {
            _words = wordCount(text);
            _starts = [0, for (final m in '\n'.allMatches(text)) m.end];
            _countedText = text;
          }
          final selection = widget.controller.selection;
          final offset = selection.isValid
              ? selection.extentOffset.clamp(0, text.length)
              : 0;
          var lo = 0;
          var hi = _starts.length;
          while (lo + 1 < hi) {
            final mid = (lo + hi) ~/ 2;
            if (_starts[mid] <= offset) {
              lo = mid;
            } else {
              hi = mid;
            }
          }
          final line = lo + 1;
          final col = offset - _starts[lo] + 1;
          return LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                _SaveState(noteId: widget.noteId, dirty: widget.dirty),
                const SizedBox(width: Sp.md),
                if (constraints.maxWidth >= 300) ...[
                  Text(context.tr('{n} words', {'n': _words}), style: style),
                  const SizedBox(width: Sp.sm),
                ],
                if (constraints.maxWidth >= 440)
                  Text(
                    context.tr('{n} chars', {'n': text.length}),
                    style: style,
                  ),
                const Spacer(),
                if (widget.language != null && constraints.maxWidth >= 400) ...[
                  Text(widget.language!, style: style),
                  const SizedBox(width: Sp.lg),
                ],
                Flexible(
                  child: Text(
                    context.tr('Ln {line}, Col {col}', {
                      'line': line,
                      'col': col,
                    }),
                    style: style,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Save status of a note: unsaved edits, saving, saved or failed (retry).
class _SaveState extends ConsumerWidget {
  const _SaveState({required this.noteId, required this.dirty});
  final String noteId;
  final ValueListenable<bool> dirty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final persistence = ref.watch(persistenceProvider);
    final locked = ref.watch(noteProvider(noteId).select((n) => n?.isLocked));
    return ListenableBuilder(
      listenable: Listenable.merge([persistence, dirty]),
      builder: (context, _) {
        final key = 'note:$noteId';
        final (IconData icon, Color color, String label) state =
            persistence.hasFailed(key)
            ? (Icons.error_outline_rounded, p.danger, context.tr('Not saved'))
            : persistence.isPending(key)
            ? (Icons.sync_rounded, p.textFaint, context.tr('Saving\u2026'))
            : dirty.value
            ? (Icons.circle, p.warning, context.tr('Unsaved changes'))
            : (Icons.check_rounded, p.textFaint, context.tr('Saved'));
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (locked == true) ...[
              Icon(Icons.lock_rounded, size: 12, color: p.textFaint),
              const SizedBox(width: Sp.xs),
            ],
            Icon(
              state.$1,
              size: state.$1 == Icons.circle ? 8 : 13,
              color: state.$2,
            ),
            const SizedBox(width: Sp.xs),
            Text(
              state.$3,
              style: TextStyle(color: state.$2, fontSize: Fs.caption),
            ),
          ],
        );
        if (!persistence.hasFailed(key)) {
          return Semantics(liveRegion: true, child: content);
        }
        return Tooltip(
          message: context.tr('Retry saving'),
          child: InkWell(
            borderRadius: BorderRadius.circular(Rad.sm),
            onTap: () async {
              try {
                await persistence.flush();
              } catch (_) {
                // The status stays "Not saved" and the error banner explains.
              }
            },
            child: content,
          ),
        );
      },
    );
  }
}
