import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../application/library_notifier.dart';
import '../core/util/ids.dart';
import 'models/note.dart';
import 'note_import_service.dart';

/// Where notes are imported from.
enum ImportSource {
  files('Markdown or text files'),
  folder('Folder of Markdown files'),
  obsidian('Obsidian vault'),
  notion('Notion export (.zip)'),
  evernote('Evernote (.enex)'),
  joplin('Joplin (.jex)');

  const ImportSource(this.label);
  final String label;
}

const _imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp'};
String? _imageMime(String nameOrExt) =>
    switch (p.extension(nameOrExt).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      _ => null,
    };

/// `[name](markbit://attachment/<id>)` plus the attachment for a file.
(String, String, NoteAttachment)? _attachment(String name, Uint8List bytes) {
  if (bytes.length > 20 * 1024 * 1024) return null;
  final id = newId();
  return (
    id,
    '[${name.replaceAll(RegExp(r'[\[\]]'), '_')}](markbit://attachment/$id)',
    NoteAttachment(name: name, data: base64Encode(bytes), size: bytes.length),
  );
}

// ------------------------------------------------------------------ obsidian

/// An Obsidian vault: `[[links]]` are kept, `![[embeds]]` of images anywhere
/// in the vault are embedded, other embeds become links, `#tags` (including
/// `#nested/tags`) and front-matter tags become tags.
Future<ImportPlan> importObsidian(String vault, Library library) async {
  final files = <String, String>{}; // lower-case file name -> path
  await for (final e in Directory(vault).list(recursive: true)) {
    if (e is! File) continue;
    final parts = p.split(p.relative(e.path, from: vault));
    if (parts.any((s) => s.startsWith('.'))) continue;
    files.putIfAbsent(p.basename(e.path).toLowerCase(), () => e.path);
  }
  final embed = RegExp(r'!\[\[([^\]|#]+)(?:#[^\]|]*)?(?:\|[^\]]*)?\]\]');
  final link = RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]*)?(\|[^\]]*)?\]\]');
  final tag = RegExp(
    r'(?<![\w&#/`])#([\p{L}\p{N}_][\p{L}\p{N}_/-]*)',
    unicode: true,
  );

  Future<String> transform(String body, String path, List<String> tags) async {
    body = body.replaceAllMapped(embed, (m) {
      final target = m[1]!.trim();
      final file =
          files[p.basename(target).toLowerCase()] ??
          files['${p.basename(target).toLowerCase()}.md'];
      if (file == null) return '[[${p.basenameWithoutExtension(target)}]]';
      if (_imageExtensions.contains(p.extension(file).toLowerCase())) {
        final relative = p.relative(file, from: p.dirname(path));
        return '![${p.basenameWithoutExtension(file)}](<$relative>)';
      }
      if (file.toLowerCase().endsWith('.md')) {
        return '[[${p.basenameWithoutExtension(file)}]]';
      }
      return '\u{1F4CE} ${p.basename(file)}';
    });
    // [[folder/Note#Heading|alias]] -> [[Note|alias]]
    body = body.replaceAllMapped(
      link,
      (m) => '[[${p.basename(m[1]!.trim())}${m[2] ?? ''}]]',
    );
    var inCode = false;
    for (final line in body.split('\n')) {
      if (line.trimLeft().startsWith('```')) inCode = !inCode;
      if (inCode || RegExp(r'^\s*#{1,6}\s').hasMatch(line)) continue;
      for (final m in tag.allMatches(line.replaceAll(RegExp(r'`[^`]*`'), ''))) {
        if (!tags.contains(m[1])) tags.add(m[1]!);
      }
    }
    return body;
  }

  return NoteImportService.folder(
    vault,
    library,
    transform: transform,
    markdownOnly: true,
  );
}

// -------------------------------------------------------------------- notion

final _notionId = RegExp(r'\s+[0-9a-f]{32}$');
String _notionName(String name) => name.replaceFirst(_notionId, '').trim();

/// A Notion "Markdown & CSV" export, as the downloaded .zip or unpacked.
/// Page ids are removed from names, links between pages become `[[links]]`,
/// the page's own heading is dropped and a "Tags:" property becomes tags.
Future<ImportPlan> importNotion(String path, Library library) async {
  var root = path;
  Directory? temp;
  if (path.toLowerCase().endsWith('.zip')) {
    temp = await Directory.systemTemp.createTemp('markbit_notion_');
    await _extractZip(File(path), temp);
    root = temp.path;
  }
  try {
    final link = RegExp(r'\[([^\]]*)\]\(([^)\s]+\.md)\)');
    Future<String> transform(
      String body,
      String file,
      List<String> tags,
    ) async {
      final title = _notionName(p.basenameWithoutExtension(file));
      final lines = body.split('\n');
      // "# Title" duplicates the note title.
      if (lines.isNotEmpty &&
          lines.first.replaceFirst(RegExp(r'^#\s+'), '').trim() == title) {
        lines.removeAt(0);
        while (lines.isNotEmpty && lines.first.trim().isEmpty) {
          lines.removeAt(0);
        }
        // Page properties ("Tags: a, b") follow the title.
        while (lines.isNotEmpty) {
          final prop = RegExp(
            r'^([\p{L} ]{1,30}):\s+(.+)$',
            unicode: true,
          ).firstMatch(lines.first);
          if (prop == null) break;
          if (const {
            'tags',
            'tag',
            'etiketler',
            'etiket',
          }.contains(prop[1]!.trim().toLowerCase())) {
            tags.addAll(
              prop[2]!
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty),
            );
          }
          lines.removeAt(0);
        }
      }
      return lines.join('\n').replaceAllMapped(link, (m) {
        final target = _notionName(
          p.basenameWithoutExtension(Uri.decodeComponent(m[2]!)),
        );
        return m[1] == target || m[1]!.isEmpty
            ? '[[$target]]'
            : '[[$target|${m[1]}]]';
      });
    }

    return await NoteImportService.folder(
      root,
      library,
      transform: transform,
      cleanName: _notionName,
      markdownOnly: true,
    );
  } finally {
    // Images were embedded into the notes already.
    if (temp != null) await temp.delete(recursive: true);
  }
}

Future<void> _extractZip(File zip, Directory into, {int depth = 0}) async {
  final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
  for (final entry in archive.files) {
    if (!entry.isFile) continue;
    final target = p.normalize(p.join(into.path, entry.name));
    // Never write outside the target folder (zip slip).
    if (!p.isWithin(into.path, target)) continue;
    final out = File(target);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(entry.content);
    // Notion splits large exports into nested zips.
    if (depth < 2 && target.toLowerCase().endsWith('.zip')) {
      await _extractZip(
        out,
        Directory(p.withoutExtension(target)),
        depth: depth + 1,
      );
      await out.delete();
    }
  }
}

// ------------------------------------------------------------------ evernote

/// Evernote .enex files: notes with their tags, dates, images and
/// attachments; the formatted text is converted to Markdown.
Future<ImportPlan> importEvernote(List<String> paths, Library library) async {
  final files = <ImportCandidate>[];
  final skipped = <String>[];
  final seen = {
    for (final n in library.notes.values) '${n.title}\u0000${n.body}',
  };
  for (final path in paths) {
    try {
      final doc = XmlDocument.parse(await File(path).readAsString());
      final notebook = p.basenameWithoutExtension(path);
      for (final el in doc.findAllElements('note')) {
        final title = el.getElement('title')?.innerText.trim() ?? '';
        final resources =
            <String, (String mime, String name, Uint8List data)>{};
        for (final r in el.findElements('resource')) {
          final raw = r
              .getElement('data')
              ?.innerText
              .replaceAll(RegExp(r'\s'), '');
          if (raw == null || raw.isEmpty) continue;
          final bytes = base64Decode(raw);
          final mime = r.getElement('mime')?.innerText.trim() ?? '';
          final name =
              r
                  .getElement('resource-attributes')
                  ?.getElement('file-name')
                  ?.innerText
                  .trim() ??
              'file';
          resources[md5.convert(bytes).toString()] = (mime, name, bytes);
        }
        final attachments = <String, NoteAttachment>{};
        final content = el.getElement('content')?.innerText ?? '';
        final body = enmlToMarkdown(content, (hash) {
          final res = resources[hash];
          if (res == null) return '';
          final (mime, name, data) = res;
          if (mime.startsWith('image/')) {
            return '![${name.replaceAll(RegExp(r'[\[\]]'), '_')}](data:$mime;base64,${base64Encode(data)})';
          }
          final a = _attachment(name, data);
          if (a == null) return name;
          attachments[a.$1] = a.$3;
          return a.$2;
        });
        final created = _enexDate(el.getElement('created')?.innerText);
        final updated =
            _enexDate(el.getElement('updated')?.innerText) ?? created;
        final now = DateTime.now();
        files.add(
          ImportCandidate(
            path: '$path › $title',
            note: Note(
              id: newId(),
              title: title,
              body: body,
              attachments: attachments,
              createdAt: created ?? now,
              updatedAt: updated ?? now,
            ),
            tags: [for (final t in el.findElements('tag')) t.innerText.trim()],
            folders: [notebook],
            duplicate: !seen.add('$title\u0000$body'),
          ),
        );
      }
    } catch (_) {
      skipped.add(path);
    }
  }
  return ImportPlan(files, skipped);
}

DateTime? _enexDate(String? s) {
  final m = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$',
  ).firstMatch(s?.trim() ?? '');
  if (m == null) return null;
  return DateTime.utc(
    int.parse(m[1]!),
    int.parse(m[2]!),
    int.parse(m[3]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  ).toLocal();
}

/// Converts Evernote's ENML (XHTML) to Markdown. [media] returns the
/// Markdown for an `<en-media hash=…>` element.
String enmlToMarkdown(String enml, String Function(String hash) media) {
  XmlDocument doc;
  try {
    doc = XmlDocument.parse(
      enml.replaceFirst(RegExp(r'<!DOCTYPE[^>]*>'), ''),
      entityMapping: XmlDefaultEntityMapping.html5(),
    );
  } catch (_) {
    // Not well-formed: keep the text.
    return enml.replaceAll(RegExp(r'<[^>]+>'), ' ').trim();
  }
  final out = StringBuffer();
  _Enml(media, out).block(doc.rootElement, 0);
  return out
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class _Enml {
  _Enml(this.media, this.out);
  final String Function(String hash) media;
  final StringBuffer out;

  static const _blocks = {
    'div', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', //
    'blockquote', 'pre', 'table', 'hr', 'en-note', 'section', 'article',
  };

  void _newline() {
    final s = out.toString();
    if (s.isNotEmpty && !s.endsWith('\n')) out.write('\n');
  }

  void block(XmlElement el, int listDepth, {String? listMarker}) {
    final tag = el.name.local.toLowerCase();
    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _newline();
        out.write('\n${'#' * int.parse(tag[1])} ${inline(el).trim()}\n\n');
      case 'ul' || 'ol':
        _newline();
        var n = 1;
        for (final li in el.childElements) {
          block(li, listDepth + 1, listMarker: tag == 'ol' ? '${n++}.' : '-');
        }
        if (listDepth == 0) out.write('\n');
      case 'li':
        _newline();
        final indent = '  ' * (listDepth - 1);
        final text = StringBuffer();
        final nested = <XmlElement>[];
        for (final c in el.children) {
          if (c is XmlElement &&
              (c.name.local == 'ul' || c.name.local == 'ol')) {
            nested.add(c);
          } else {
            text.write(_inlineNode(c));
          }
        }
        out.write('$indent${listMarker ?? '-'} ${text.toString().trim()}\n');
        for (final n in nested) {
          block(n, listDepth);
        }
      case 'blockquote':
        _newline();
        final inner = StringBuffer();
        _Enml(media, inner).children(el, 0);
        out.write(
          '\n${inner.toString().trim().split('\n').map((l) => '> $l').join('\n')}\n\n',
        );
      case 'pre':
        _newline();
        out.write('\n```\n${el.innerText.trimRight()}\n```\n\n');
      case 'hr':
        _newline();
        out.write('\n---\n\n');
      case 'table':
        _newline();
        final rows = [
          for (final tr in el.findAllElements('tr'))
            [
              for (final cell in tr.childElements)
                if (cell.name.local == 'td' || cell.name.local == 'th')
                  inline(
                    cell,
                  ).trim().replaceAll('|', r'\|').replaceAll('\n', ' '),
            ],
        ];
        if (rows.isEmpty) return;
        final width = rows
            .map((r) => r.length)
            .fold<int>(0, (a, b) => a > b ? a : b);
        String row(List<String> r) =>
            '| ${[for (var i = 0; i < width; i++) i < r.length ? r[i] : ''].join(' | ')} |';
        out.write('\n${row(rows.first)}\n|${' --- |' * width}\n');
        for (final r in rows.skip(1)) {
          out.write('${row(r)}\n');
        }
        out.write('\n');
      case 'div' || 'p' || 'section' || 'article':
        // A div holding blocks is a container; otherwise it is a line.
        if (el.childElements.any(
          (c) => _blocks.contains(c.name.local.toLowerCase()),
        )) {
          children(el, listDepth);
        } else {
          _newline();
          final text = inline(el);
          out.write(text.trim().isEmpty ? '\n' : '${text.trimRight()}\n');
        }
      default:
        children(el, listDepth);
    }
  }

  void children(XmlElement el, int listDepth) {
    var inlineRun = StringBuffer();
    void flush() {
      final t = inlineRun.toString();
      if (t.trim().isNotEmpty) {
        _newline();
        out.write('${t.trim()}\n');
      }
      inlineRun = StringBuffer();
    }

    for (final c in el.children) {
      if (c is XmlElement && _blocks.contains(c.name.local.toLowerCase())) {
        flush();
        block(c, listDepth);
      } else {
        inlineRun.write(_inlineNode(c));
      }
    }
    flush();
  }

  String inline(XmlElement el) => el.children.map(_inlineNode).join();

  String _inlineNode(XmlNode node) {
    if (node is XmlText || node is XmlCDATA) {
      return node.value!.replaceAll(RegExp(r'\s+'), ' ');
    }
    if (node is! XmlElement) return '';
    final tag = node.name.local.toLowerCase();
    String wrap(String mark) {
      final t = inline(node);
      return t.trim().isEmpty ? t : '$mark${t.trim()}$mark ';
    }

    return switch (tag) {
      'br' => '\n',
      'b' || 'strong' => wrap('**'),
      'i' || 'em' => wrap('*'),
      's' || 'strike' || 'del' => wrap('~~'),
      'code' => '`${node.innerText}`',
      'a' => '[${inline(node).trim()}](${node.getAttribute('href') ?? ''})',
      'img' => '![](${node.getAttribute('src') ?? ''})',
      'en-todo' => node.getAttribute('checked') == 'true' ? '- [x] ' : '- [ ] ',
      'en-media' => media(node.getAttribute('hash') ?? ''),
      _ when _blocks.contains(tag) => '\n${inline(node)}\n',
      _ => inline(node),
    };
  }
}

// -------------------------------------------------------------------- joplin

/// A Joplin export (.jex): notes in their notebooks with tags, dates,
/// images and attachments; `:/id` links between notes become `[[links]]`.
Future<ImportPlan> importJoplin(String path, Library library) async {
  final archive = TarDecoder().decodeBytes(await File(path).readAsBytes());
  final items = <String, Map<String, String>>{}; // id -> metadata + body
  final resources = <String, Uint8List>{}; // resource id -> bytes
  for (final f in archive.files) {
    if (!f.isFile) continue;
    final name = f.name.replaceAll('\\', '/');
    if (name.startsWith('resources/')) {
      resources[p.basenameWithoutExtension(name)] = f.content;
      continue;
    }
    if (!name.endsWith('.md')) continue;
    final item = _joplinItem(utf8.decode(f.content, allowMalformed: true));
    if (item['id'] != null) items[item['id']!] = item;
  }
  String type(Map<String, String> i) => i['type_'] ?? '';
  final folders = {
    for (final i in items.values)
      if (type(i) == '2') i['id']!: i,
  };
  final tags = {
    for (final i in items.values)
      if (type(i) == '5') i['id']!: i['title'] ?? '',
  };
  final noteTags = <String, List<String>>{};
  for (final i in items.values.where((i) => type(i) == '6')) {
    final tag = tags[i['tag_id']];
    if (tag != null) {
      noteTags.putIfAbsent(i['note_id'] ?? '', () => []).add(tag);
    }
  }
  final notes = {
    for (final i in items.values)
      if (type(i) == '1') i['id']!: i,
  };
  List<String> folderPath(String? id) {
    final out = <String>[];
    var guard = 0;
    while (id != null && folders[id] != null && guard++ < 32) {
      out.insert(0, folders[id]!['title'] ?? '');
      id = folders[id]!['parent_id'];
    }
    return out;
  }

  final seen = {
    for (final n in library.notes.values) '${n.title}\u0000${n.body}',
  };
  final files = <ImportCandidate>[];
  for (final n in notes.values) {
    final attachments = <String, NoteAttachment>{};
    var body = (n['body'] ?? '').replaceAllMapped(
      RegExp(r'(!?)\[([^\]]*)\]\(:/([0-9a-f]{32})\)'),
      (m) {
        final id = m[3]!;
        final linked = notes[id];
        if (linked != null) return '[[${linked['title']}]]';
        final res = items[id];
        final bytes = resources[id];
        if (res == null || bytes == null) return m[0]!;
        final mime =
            res['mime'] ?? _imageMime('.${res['file_extension']}') ?? '';
        final name = res['title']?.isNotEmpty == true
            ? res['title']!
            : '$id.${res['file_extension'] ?? 'bin'}';
        if (mime.startsWith('image/')) {
          return '![${m[2]}](data:$mime;base64,${base64Encode(bytes)})';
        }
        final a = _attachment(name, bytes);
        if (a == null) return name;
        attachments[a.$1] = a.$3;
        return a.$2;
      },
    );
    body = body.trim();
    final title = n['title'] ?? '';
    final now = DateTime.now();
    files.add(
      ImportCandidate(
        path: '${p.basename(path)} › $title',
        note: Note(
          id: newId(),
          title: title,
          body: body,
          attachments: attachments,
          createdAt:
              DateTime.tryParse(n['created_time'] ?? '')?.toLocal() ?? now,
          updatedAt:
              DateTime.tryParse(n['updated_time'] ?? '')?.toLocal() ?? now,
        ),
        tags: noteTags[n['id']] ?? const [],
        folders: folderPath(n['parent_id']),
        duplicate: !seen.add('$title\u0000$body'),
      ),
    );
  }
  return ImportPlan(files, const []);
}

/// A Joplin item file: title line, body, then a block of `key: value` lines.
Map<String, String> _joplinItem(String text) {
  final lines = const LineSplitter().convert(text);
  var start = lines.length;
  final meta = RegExp(r'^([a-z_]+): ?(.*)$');
  while (start > 0 && meta.hasMatch(lines[start - 1])) {
    start--;
  }
  final out = <String, String>{
    for (final l in lines.sublist(start))
      meta.firstMatch(l)![1]!: meta.firstMatch(l)![2]!,
  };
  final content = lines.sublist(0, start);
  while (content.isNotEmpty && content.last.trim().isEmpty) {
    content.removeLast();
  }
  if (content.isNotEmpty) {
    out['title'] ??= content.first.trim();
    out['body'] = content.skip(1).join('\n').replaceFirst(RegExp(r'^\n'), '');
  }
  return out;
}
