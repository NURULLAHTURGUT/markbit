import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/persistence_coordinator.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/util/platform_info.dart';
import '../dialogs/dialogs.dart';
import '../editor/note_editor.dart';
import 'library_host.dart';

/// Separate note windows are separate processes on desktop platforms.
bool get canOpenNoteWindows => PlatformInfo.isDesktop;

/// Opens [noteId] in its own window. The windows stay in sync through the
/// library folder: each one notices the other's saves.
Future<void> openNoteWindow(
  BuildContext context,
  WidgetRef ref,
  String noteId,
) async {
  final persistence = ref.read(persistenceProvider);
  persistence.flushEditors();
  try {
    // The new window loads the note from disk, so save first.
    await persistence.flush();
    await Process.start(Platform.resolvedExecutable, [
      '--note=$noteId',
    ], mode: ProcessStartMode.detached);
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        context.tr('Could not open a new window: {error}', {'error': '$e'}),
      );
    }
  }
}

/// The whole UI of a note window: one editor, no sidebar or tabs.
class NoteWindowPage extends ConsumerStatefulWidget {
  const NoteWindowPage({super.key, required this.noteId});
  final String noteId;

  @override
  ConsumerState<NoteWindowPage> createState() => _NoteWindowPageState();
}

class _NoteWindowPageState extends ConsumerState<NoteWindowPage> {
  static const _window = MethodChannel('markbit/window_theme');
  String? _title;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(libraryProvider).notes.containsKey(widget.noteId)) {
        ref.read(openNoteProvider.notifier).open(widget.noteId);
      }
    });
  }

  void _syncTitle(String? title) {
    if (title == null || title == _title) return;
    _title = title;
    _window
        .invokeMethod<void>('setTitle', '$title — Markbit')
        .catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final note = ref.watch(noteProvider(widget.noteId));
    _syncTitle(note?.displayTitle);
    return Scaffold(
      backgroundColor: p.isGlass ? Colors.transparent : p.editorBg,
      body: LibraryHost(
        child: note == null
            ? Center(
                child: Text(
                  context.tr('This note no longer exists.'),
                  style: TextStyle(color: p.textMuted),
                ),
              )
            : const EditorPane(),
      ),
    );
  }
}
