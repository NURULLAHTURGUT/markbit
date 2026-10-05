import '../data/models/note.dart';
import 'package:markdown/markdown.dart' as md;

class Heading {
  const Heading(this.level, this.text, this.line);
  final int level;
  final String text;

  /// Zero-based line index in the source.
  final int line;
}

class TaskProgress {
  const TaskProgress(this.done, this.total);
  final int done;
  final int total;
  bool get isEmpty => total == 0;
  double get fraction => total == 0 ? 0 : done / total;
}

sealed class BodySegment {
  const BodySegment(this.startLine, this.endLine);

  /// First line (zero-based) covered by the segment.
  final int startLine;

  /// Last line (zero-based, inclusive) covered by the segment.
  final int endLine;
}

class TextSegment extends BodySegment {
  const TextSegment(this.text, super.startLine, super.endLine);
  final String text;
}

class CodeSegment extends BodySegment {
  const CodeSegment(this.info, this.code, super.startLine, super.endLine);

  /// Raw info string of the fence (first word), e.g. `dart`.
  final String info;
  final String code;
}

final RegExp _openFence = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*([^\s`]*)');
final RegExp _heading = RegExp(r'^ {0,3}(#{1,6})\s+(.+?)\s*#*\s*$');
final RegExp _task = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+\[([ xX])\]');
final RegExp _wiki = RegExp(r'\[\[([^\[\]\n|]+?)(?:\|[^\[\]\n]*)?\]\]');

/// Splits a markdown body into prose and top-level fenced code blocks.
List<BodySegment> splitSegments(String body) {
  final lines = body.split('\n');
  final out = <BodySegment>[];
  final prose = <String>[];
  var proseStart = 0;

  void flushProse(int endLine) {
    if (prose.isEmpty) return;
    out.add(TextSegment(prose.join('\n'), proseStart, endLine));
    prose.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final open = _openFence.firstMatch(lines[i]);
    if (open == null) {
      if (prose.isEmpty) proseStart = i;
      prose.add(lines[i]);
      i++;
      continue;
    }
    flushProse(i - 1);
    final fence = open.group(1)!;
    final info = open.group(2) ?? '';
    final codeLines = <String>[];
    var j = i + 1;
    var closed = false;
    while (j < lines.length) {
      final t = lines[j].trimLeft();
      if (t.startsWith(fence[0] * fence.length) &&
          t.replaceAll(fence[0], '').trim().isEmpty) {
        closed = true;
        break;
      }
      codeLines.add(lines[j]);
      j++;
    }
    final end = closed ? j : lines.length - 1;
    out.add(CodeSegment(info, codeLines.join('\n'), i, end));
    i = end + 1;
  }
  flushProse(lines.length - 1);
  return out;
}

/// Headings outside of fenced code.
List<Heading> extractHeadings(String body) {
  final out = <Heading>[];
  // Reuse the fence parser so nested examples inside four-backtick fences
  // cannot accidentally become navigation targets.
  for (final segment in splitSegments(body).whereType<TextSegment>()) {
    final lines = segment.text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final match = _heading.firstMatch(lines[i]);
      if (match != null) {
        out.add(Heading(match[1]!.length, match[2]!, segment.startLine + i));
        continue;
      }
      if (i == 0 ||
          !RegExp(r'^ {0,3}(=+|-+)\s*$').hasMatch(lines[i]) ||
          lines[i - 1].trim().isEmpty) {
        continue;
      }
      var start = i - 1;
      while (start > 0 &&
          lines[start - 1].trim().isNotEmpty &&
          !_heading.hasMatch(lines[start - 1])) {
        start--;
      }
      final nodes = md.Document().parseLines(lines.sublist(start, i + 1));
      if (nodes.length == 1 && nodes.single is md.Element) {
        final element = nodes.single as md.Element;
        if (element.tag == 'h1' || element.tag == 'h2') {
          out.add(
            Heading(
              element.tag == 'h1' ? 1 : 2,
              element.textContent,
              segment.startLine + start,
            ),
          );
        }
      }
    }
  }
  return out;
}

TaskProgress taskProgress(String body) {
  var done = 0;
  var total = 0;
  String? fence;
  for (final line in body.split('\n')) {
    final open = _openFence.firstMatch(line);
    if (fence == null && open != null) {
      fence = open.group(1)![0];
      continue;
    }
    if (fence != null) {
      if (line.trimLeft().startsWith(fence * 3)) fence = null;
      continue;
    }
    final m = _task.firstMatch(line);
    if (m != null) {
      total++;
      if (m.group(1) != ' ') done++;
    }
  }
  return TaskProgress(done, total);
}

String makeSnippet(String body, {int max = 160}) {
  final buf = StringBuffer();
  String? fence;
  String? firstCode;
  for (final raw in body.split('\n')) {
    final open = _openFence.firstMatch(raw);
    if (fence == null && open != null) {
      fence = open.group(1)![0];
      continue;
    }
    if (fence != null) {
      if (raw.trimLeft().startsWith(fence * 3)) {
        fence = null;
      } else if (firstCode == null && raw.trim().isNotEmpty) {
        firstCode = raw.trim();
      }
      continue;
    }
    var line = raw.trim();
    if (line.isEmpty) continue;
    line = line
        .replaceFirst(RegExp(r'^#{1,6}\s+'), '')
        .replaceFirst(RegExp(r'^>\s?'), '')
        .replaceFirst(RegExp(r'^(?:[-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?'), '')
        .replaceAll(RegExp(r'[*_`~]'), '');
    if (line.isEmpty) continue;
    if (buf.isNotEmpty) buf.write(' ');
    buf.write(line);
    if (buf.length >= max) break;
  }
  var s = buf.toString();
  if (s.isEmpty) s = firstCode ?? '';
  return s.length > max ? s.substring(0, max) : s;
}

int wordCount(String text) {
  final t = text.trim();
  if (t.isEmpty) return 0;
  return RegExp(r'\S+').allMatches(t).length;
}

List<String> extractWikiLinks(String body) =>
    _wiki.allMatches(body).map((m) => m.group(1)!.trim()).toList();

/// Replaces `[[Title]]` with markdown links understood by the app.
/// [resolve] maps a title to a note id (or null when it doesn't exist).
String linkifyWikiLinks(String text, String? Function(String title) resolve) {
  return text.replaceAllMapped(_wiki, (m) {
    final title = m.group(1)!.trim();
    final id = resolve(title);
    final label = m.group(0)!.contains('|')
        ? m
              .group(0)!
              .substring(m.group(0)!.indexOf('|') + 1, m.group(0)!.length - 2)
        : title;
    if (id == null && title.startsWith('id:')) return label;
    return id != null
        ? '[$label](markbit://note/$id)'
        : '[$label](markbit://create/${Uri.encodeComponent(title)})';
  });
}

/// Cached, derived display data for a note (list tiles).
class NoteDigest {
  NoteDigest._(this.snippet, this.progress);
  final String snippet;
  final TaskProgress progress;

  static final Expando<NoteDigest> _cache = Expando('NoteDigest');

  static NoteDigest of(Note note) => _cache[note] ??= NoteDigest._(
    note.kind == NoteKind.code
        ? makeSnippet('```\n${note.body}\n```')
        : makeSnippet(note.body),
    note.kind == NoteKind.code
        ? const TaskProgress(0, 0)
        : taskProgress(note.body),
  );
}

/// Bind links outside fenced/inline code. Existing IDs and unresolved titles stay intact.
String bindWikiLinks(String body, String? Function(String) resolve) {
  final lines = body.split('\n');
  final codeLines = <int>{};
  for (final segment in splitSegments(body).whereType<CodeSegment>()) {
    for (var i = segment.startLine; i <= segment.endLine; i++) {
      codeLines.add(i);
    }
  }
  String bind(String text) => text.replaceAllMapped(_wiki, (m) {
    final title = m[1]!.trim();
    if (title.startsWith('id:')) return m[0]!;
    final id = resolve(title);
    if (id == null) return m[0]!;
    final label = m[0]!.contains('|')
        ? m[0]!.substring(m[0]!.indexOf('|') + 1, m[0]!.length - 2)
        : title;
    return '[[id:$id|$label]]';
  });
  for (var i = 0; i < lines.length; i++) {
    if (codeLines.contains(i)) continue;
    final line = lines[i], out = StringBuffer();
    var start = 0;
    for (final m in RegExp(r'(`+).*?\1').allMatches(line)) {
      out.write(bind(line.substring(start, m.start)));
      out.write(m[0]);
      start = m.end;
    }
    out.write(bind(line.substring(start)));
    lines[i] = out.toString();
  }
  return lines.join('\n');
}
