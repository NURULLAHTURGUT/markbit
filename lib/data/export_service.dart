import 'note_attachment_service.dart';
import 'note_images.dart';
import '../core/l10n/app_strings.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../application/library_notifier.dart';
import 'note_import_service.dart';
import 'html_export.dart';
import '../core/util/platform_info.dart';
import '../domain/languages.dart';
import '../features/dialogs/dialogs.dart';
import 'models/note.dart';

/// Import/export of notes as plain files.
abstract final class ExportService {
  static final RegExp _unsafe = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  static String safeName(String name) {
    var cleaned = name
        .replaceAll(_unsafe, '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (cleaned.isEmpty) return 'Untitled';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(cleaned)) {
      cleaned = '_$cleaned';
    }
    return cleaned.characters.take(100).toString();
  }

  static String fileContent(
    Note note,
    Library lib, {
    bool frontMatter = false,
  }) {
    if (note.kind == NoteKind.code) return note.body;
    final buf = StringBuffer();
    if (frontMatter) {
      buf.writeln('---');
      buf.writeln('title: ${jsonEncode(note.title)}');
      final tags = [
        for (final id in note.tagIds) lib.tag(id)?.name,
      ].whereType<String>();
      if (tags.isNotEmpty) {
        buf.writeln('tags: [${tags.map(jsonEncode).join(', ')}]');
      }
      if (note.status != NoteStatus.none) {
        buf.writeln('status: ${note.status.name}');
      }
      buf.writeln('created: ${note.createdAt.toIso8601String()}');
      buf.writeln('updated: ${note.updatedAt.toIso8601String()}');
      buf.writeln('---');
      buf.writeln();
      buf.write(NoteImages.expand(note));
    } else {
      if (note.title.trim().isNotEmpty) buf.writeln('# ${note.title.trim()}\n');
      buf.write(NoteImages.expand(note));
    }
    return buf.toString();
  }

  static String extensionFor(Note note) => note.kind == NoteKind.code
      ? (Languages.find(note.language)?.extension ?? 'txt')
      : 'md';

  /// Asks for a location and writes a single note.
  static Future<void> exportNote(BuildContext context, Note note) async {
    final bytes = Uint8List.fromList(utf8.encode(_contentFor(note)));
    final name = '${safeName(note.displayTitle)}.${extensionFor(note)}';
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: context.tr('Export note'),
        fileName: name,
        bytes: bytes,
      );
      if (path == null) return;
      if (PlatformInfo.isDesktop) {
        final target = File(path);
        final body = await NoteAttachmentService.exportBody(note, target);
        await target.writeAsString(_contentFor(note.copyWith(body: body)));
      }
      if (context.mounted) {
        showToast(context, context.tr('Exported to {path}', {'path': path}));
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          context.tr('Export failed: {error}', {'error': '$e'}),
        );
      }
    }
  }

  static String _contentFor(Note note) {
    // Library is not needed for a single-note export without front matter.
    return note.kind == NoteKind.code
        ? note.body
        : '${note.title.trim().isEmpty ? '' : '# ${note.title.trim()}\n\n'}${NoteImages.expand(note)}';
  }

  /// Writes every non-trashed note into [dir], one sub-folder per notebook.
  ///
  /// With [html], notes become web pages that link to each other.
  static Future<int> exportAll(
    Library lib,
    String dir, {
    Set<String>? selectedIds,
    bool html = false,
  }) async {
    final root = p.normalize(p.absolute(dir));
    final used = <String>{};
    var count = 0;
    final written = <String, String>{}; // note id -> file path
    final pending = <(Note, String)>[];
    for (final note in lib.notes.values) {
      if (selectedIds != null ? !selectedIds.contains(note.id) : note.trashed) {
        continue;
      }
      // Locked notes hold only ciphertext here; exporting them would write
      // empty files. They stay in the encrypted backup instead.
      if (note.isLocked) continue;
      final notebookPath = lib
          .notebookPath(note.notebookId)
          .split(' / ')
          .map(safeName)
          .join(p.separator);
      final folder = Directory(p.join(root, notebookPath));
      if (folder.path != root && !p.isWithin(root, folder.path)) {
        throw const FormatException('Invalid export path');
      }
      await folder.create(recursive: true);
      final resolvedRoot = await Directory(root).resolveSymbolicLinks();
      final resolvedFolder = await folder.resolveSymbolicLinks();
      if (resolvedFolder != resolvedRoot &&
          !p.isWithin(resolvedRoot, resolvedFolder)) {
        throw const FormatException(
          'Export folder points outside the selected directory',
        );
      }

      final base = safeName(note.displayTitle);
      final ext = html ? 'html' : extensionFor(note);
      var candidate = p.join(folder.path, '$base.$ext');
      var n = 2;
      while (used.contains(candidate.toLowerCase()) ||
          await FileSystemEntity.type(candidate, followLinks: false) !=
              FileSystemEntityType.notFound) {
        candidate = p.join(folder.path, '$base ($n).$ext');
        n++;
      }
      used.add(candidate.toLowerCase());
      if (html) {
        // Written after all paths are known, so links can point at them.
        written[note.id] = candidate;
        pending.add((note, candidate));
        count++;
        continue;
      }
      await File(candidate).writeAsString(
        fileContent(
          note.copyWith(
            body: await NoteAttachmentService.exportBody(note, File(candidate)),
          ),
          lib,
          frontMatter: note.kind == NoteKind.markdown,
        ),
      );
      count++;
    }
    for (final (note, path) in pending) {
      await File(path).writeAsString(
        HtmlExport.page(
          note,
          resolveNoteId: lib.findNoteIdByTitle,
          noteHref: (id) {
            final target = written[id];
            return target == null
                ? null
                : p.posix.joinAll(
                    p.split(p.relative(target, from: p.dirname(path))),
                  );
          },
          language: AppStrings.current.locale.languageCode,
        ),
      );
    }
    return count;
  }

  /// Imports `.md`/`.txt` files and source files from [dir] (recursively).
  /// Top-level sub-folders become notebooks. Returns the number of notes.
  static Future<int> importFolder(
    LibraryNotifier notifier,
    Library lib,
    String dir,
  ) async {
    final plan = await NoteImportService.folder(dir, lib);
    return NoteImportService.apply(
      notifier,
      lib,
      plan.files.where((file) => !file.duplicate),
    );
  }
}
