import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../application/library_notifier.dart';
import '../core/util/ids.dart';
import '../domain/languages.dart';
import 'models/note.dart';

class ImportCandidate {
  ImportCandidate({
    required this.path,
    required this.note,
    required this.tags,
    required this.folders,
    this.duplicate = false,
    this.warnings = const [],
  });
  final String path;
  final Note note;
  final List<String> tags;
  final List<String> folders;
  final bool duplicate;
  final List<String> warnings;
}

class ImportPlan {
  const ImportPlan(this.files, this.skipped);
  final List<ImportCandidate> files;
  final List<String> skipped;
}

/// Rewrites a Markdown body during import (e.g. Obsidian `![[embeds]]`) and
/// may add tags. Runs before local images are embedded.
typedef ImportTransform =
    Future<String> Function(String body, String path, List<String> tags);

/// Scans without changing the library. Images are embedded for portable notes.
abstract final class NoteImportService {
  static Future<ImportPlan> prepare(
    List<String> paths,
    Library library, {
    String? root,
    ImportTransform? transform,
    String Function(String name)? cleanName,
  }) async {
    final files = <ImportCandidate>[];
    final skipped = <String>[];
    final seen = {
      for (final n in library.notes.values)
        '${n.kind.name}\u0000${n.title}\u0000${n.body}',
    };
    for (final path in paths) {
      final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
      final markdown = ['md', 'markdown', 'txt'].contains(ext);
      final language = Languages.all
          .where((l) => l.extension == ext)
          .firstOrNull;
      if (!markdown && language == null) {
        skipped.add(path);
        continue;
      }
      try {
        final file = File(path);
        if (await file.length() > 32 * 1024 * 1024) {
          skipped.add(path);
          continue;
        }
        final content = (await file.readAsString()).replaceFirst(
          RegExp(r'^\uFEFF'),
          '',
        );
        var title = markdown
            ? p.basenameWithoutExtension(path)
            : p.basename(path);
        if (cleanName != null) title = cleanName(title);
        var body = content;
        final tags = <String>[];
        var status = NoteStatus.none;
        final stat = await file.stat();
        var created = stat.changed;
        var updated = stat.modified;
        if (markdown && content.startsWith('---')) {
          final close = RegExp(
            r'^---\s*\r?$',
            multiLine: true,
          ).allMatches(content).skip(1).firstOrNull;
          if (close != null) {
            body = content
                .substring(close.end)
                .replaceFirst(RegExp(r'^\r?\n+'), '');
            String? listKey;
            for (final line in const LineSplitter().convert(
              content.substring(3, close.start),
            )) {
              // YAML block lists ("tags:" followed by "  - a" lines).
              final item = RegExp(r'^\s*-\s+(.+)$').firstMatch(line);
              if (item != null && listKey == 'tags') {
                tags.add(_unquote(item[1]!).replaceFirst('#', ''));
                continue;
              }
              final colon = line.indexOf(':');
              if (colon < 0) continue;
              final key = line.substring(0, colon).trim();
              final value = line.substring(colon + 1).trim();
              listKey = value.isEmpty ? key : null;
              switch (key) {
                case 'title':
                  title = _unquote(value);
                case 'status':
                  status = NoteStatus.parse(value);
                case 'created':
                  created = DateTime.tryParse(_unquote(value)) ?? created;
                case 'updated':
                  updated = DateTime.tryParse(_unquote(value)) ?? updated;
                case 'tags':
                  try {
                    tags.addAll(
                      (jsonDecode(value) as List).whereType<String>(),
                    );
                  } catch (_) {
                    tags.addAll(
                      value
                          .replaceAll(RegExp(r'^\[|\]$'), '')
                          .split(',')
                          .map((t) => _unquote(t).replaceFirst('#', ''))
                          .where((s) => s.isNotEmpty),
                    );
                  }
              }
            }
          }
        }
        final warnings = <String>[];
        if (markdown && transform != null) {
          body = await transform(body, path, tags);
        }
        if (markdown) body = await embedImages(body, p.dirname(path), warnings);
        final kind = markdown ? NoteKind.markdown : NoteKind.code;
        final fingerprint = '${kind.name}\u0000$title\u0000$body';
        final duplicate = !seen.add(fingerprint);
        final folders = root == null
            ? <String>[]
            : p
                  .split(p.relative(p.dirname(path), from: root))
                  .where((s) => s != '.')
                  .toList();
        files.add(
          ImportCandidate(
            path: path,
            note: Note(
              id: newId(),
              title: title,
              body: body,
              kind: kind,
              language: language?.id,
              status: status,
              createdAt: created,
              updatedAt: updated,
            ),
            tags: tags,
            folders: folders,
            duplicate: duplicate,
            warnings: warnings,
          ),
        );
      } catch (_) {
        skipped.add(path);
      }
    }
    return ImportPlan(files, skipped);
  }

  static Future<ImportPlan> folder(
    String path,
    Library library, {
    ImportTransform? transform,
    String Function(String name)? cleanName,
    bool markdownOnly = false,
  }) async {
    final paths = <String>[];
    await for (final entity in Directory(
      path,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      // Skip app folders such as .obsidian, .trash and .git.
      final parts = p.split(p.relative(entity.path, from: path));
      if (parts.any((s) => s.startsWith('.'))) continue;
      if (markdownOnly &&
          ![
            '.md',
            '.markdown',
          ].contains(p.extension(entity.path).toLowerCase())) {
        continue;
      }
      paths.add(entity.path);
    }
    paths.sort();
    final plan = await prepare(
      paths,
      library,
      root: path,
      transform: transform,
      cleanName: cleanName,
    );
    if (cleanName == null) return plan;
    return ImportPlan([
      for (final f in plan.files)
        ImportCandidate(
          path: f.path,
          note: f.note,
          tags: f.tags,
          folders: [for (final folder in f.folders) cleanName(folder)],
          duplicate: f.duplicate,
          warnings: f.warnings,
        ),
    ], plan.skipped);
  }

  static int apply(
    LibraryNotifier notifier,
    Library library,
    Iterable<ImportCandidate> files, {
    String? notebookId,
  }) {
    final notebooks = {
      for (final n in library.notebooks)
        library.notebookPath(n.id).toLowerCase(): n.id,
    };
    final tags = {for (final t in library.tags) t.name.toLowerCase(): t.id};
    final notes = <Note>[];
    for (final file in files) {
      var target = notebookId ?? library.inbox.id;
      if (notebookId == null && file.folders.isNotEmpty) {
        String? parent;
        final names = <String>[];
        for (final name in file.folders) {
          names.add(name);
          final key = names.join(' / ').toLowerCase();
          parent =
              names.length == 1 &&
                  ['general', 'genel', 'inbox', 'gelen kutusu'].contains(key)
              ? library.inbox.id
              : (notebooks[key] ??= notifier
                    .createNotebook(name, parentId: parent)
                    .id);
        }
        target = parent!;
      }
      notes.add(
        file.note.copyWith(
          notebookId: target,
          tagIds: [
            for (final tag in file.tags)
              tags[tag.toLowerCase()] ??= notifier.createTag(tag).id,
          ],
        ),
      );
    }
    notifier.importNotes(notes);
    return notes.length;
  }

  static Future<String> embedImages(
    String body,
    String directory,
    List<String> warnings,
  ) async {
    final cache = <String, String>{};
    var total = 0;
    Future<String> resolve(String source) async {
      if (source.startsWith('data:') ||
          source.startsWith('http:') ||
          source.startsWith('https:')) {
        return source;
      }
      if (cache.containsKey(source)) return cache[source]!;
      try {
        final uri = Uri.tryParse(source);
        final path = uri?.scheme == 'file'
            ? File.fromUri(uri!).path
            : p.normalize(p.join(directory, Uri.decodeComponent(source)));
        final mime = switch (p.extension(path).toLowerCase()) {
          '.png' => 'image/png',
          '.jpg' || '.jpeg' => 'image/jpeg',
          '.gif' => 'image/gif',
          '.webp' => 'image/webp',
          _ => throw const FormatException('Unsupported image'),
        };
        final image = File(path);
        final length = await image.length();
        if (length > 20 * 1024 * 1024 || total + length > 40 * 1024 * 1024) {
          throw const FormatException('Image size limit');
        }
        final bytes = await image.readAsBytes();
        total += length;
        return cache[source] = 'data:$mime;base64,${base64Encode(bytes)}';
      } catch (_) {
        warnings.add(source);
        return source;
      }
    }

    // Inline links, including balanced parentheses in local file names.
    final inline = RegExp(
      r'!\[([^\]]*)\]\(\s*(?:<([^>]+)>|((?:[^\s()]|\([^()]*\))+))(?:\s+"[^"]*")?\s*\)',
    );
    var result = '';
    var end = 0;
    for (final match in inline.allMatches(body)) {
      result += body.substring(end, match.start);
      result += '![${match[1]}](${await resolve(match[2] ?? match[3]!)})';
      end = match.end;
    }
    result += body.substring(end);
    // Reference-style images resolve through their definition, not file links.
    final references = RegExp(r'!\[([^\]]*)\](?:\[([^\]]*)\])?')
        .allMatches(result)
        .map((m) => (m[2]?.isNotEmpty == true ? m[2]! : m[1]!).toLowerCase())
        .toSet();
    final definitions = RegExp(
      r'^([ \t]*\[([^\]]+)\]:[ \t]*)(?:<([^>]+)>|(\S+))(.*)$',
      multiLine: true,
    );
    body = result;
    result = '';
    end = 0;
    for (final match in definitions.allMatches(body)) {
      result += body.substring(end, match.start);
      result += references.contains(match[2]!.toLowerCase())
          ? '${match[1]}${await resolve(match[3] ?? match[4]!)}${match[5]}'
          : match[0]!;
      end = match.end;
    }
    return result + body.substring(end);
  }

  static String _unquote(String value) {
    final t = value.trim();
    try {
      if (t.startsWith('"')) return jsonDecode(t) as String;
    } catch (_) {}
    return t.length >= 2 && t.startsWith("'") && t.endsWith("'")
        ? t.substring(1, t.length - 1)
        : t;
  }
}
