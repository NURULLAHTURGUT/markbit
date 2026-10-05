/// Markdown extensions the preview adds on top of GitHub Flavored Markdown:
/// `$$` math blocks and footnotes (`text[^1]` with `[^1]: note`).
library;

final RegExp _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final RegExp _footnoteDef = RegExp(r'^ {0,3}\[\^([^\]\s]+)\]:[ \t]?(.*)$');
final RegExp footnoteRef = RegExp(r'\[\^([^\]\s]+)\]');

class Footnote {
  const Footnote({
    required this.number,
    required this.label,
    required this.text,
    required this.refLine,
  });
  final int number;
  final String label;
  final String text;

  /// Line of the first reference, or -1 when the note is never referenced.
  final int refLine;
}

class PreparedMarkdown {
  const PreparedMarkdown(this.body, this.footnotes);

  /// The body with the same number of lines: `$$` blocks became ```math
  /// fences and footnote definitions became blank lines.
  final String body;
  final List<Footnote> footnotes;

  Map<String, int> get numbers => {
    for (final f in footnotes) f.label: f.number,
  };
}

/// Rewrites [body] for rendering without changing its line numbers, so task
/// toggles, image edits and headings still point at the right source line.
PreparedMarkdown prepareMarkdown(String body) {
  final lines = body.split('\n');
  final defs = <String, String>{};
  final order = <String>[];
  String? fence;
  var inMath = false;
  String? openDef;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (openDef != null) {
      // Indented lines continue the previous footnote definition.
      if (line.trim().isNotEmpty && RegExp(r'^(?: {2,}|\t)').hasMatch(line)) {
        defs[openDef] = '${defs[openDef]}\n${line.trim()}';
        lines[i] = '';
        continue;
      }
      openDef = null;
    }
    final f = _fence.firstMatch(line);
    if (fence != null) {
      if (f != null && f[1]![0] == fence[0] && f[1]!.length >= fence.length) {
        fence = null;
      }
      continue;
    }
    if (inMath) {
      if (line.trim() == r'$$') {
        lines[i] = '```';
        inMath = false;
      }
      continue;
    }
    if (f != null) {
      fence = f[1];
      continue;
    }
    if (line.trim() == r'$$') {
      lines[i] = '```math';
      inMath = true;
      continue;
    }
    final def = _footnoteDef.firstMatch(line);
    if (def != null) {
      final label = def[1]!;
      if (!defs.containsKey(label)) order.add(label);
      defs[label] = def[2]!.trim();
      openDef = label;
      lines[i] = '';
    }
  }
  if (inMath) lines.add('```');
  if (defs.isEmpty) return PreparedMarkdown(lines.join('\n'), const []);

  // Number footnotes in the order they are first referenced.
  final firstRef = <String, int>{};
  fence = null;
  for (var i = 0; i < lines.length; i++) {
    final f = _fence.firstMatch(lines[i]);
    if (f != null) {
      fence = fence == null ? f[1] : null;
      continue;
    }
    if (fence != null) continue;
    for (final m in footnoteRef.allMatches(lines[i])) {
      if (defs.containsKey(m[1]) && !firstRef.containsKey(m[1])) {
        firstRef[m[1]!] = i;
      }
    }
  }
  final labels = [
    ...firstRef.keys,
    ...order.where((l) => !firstRef.containsKey(l)),
  ];
  return PreparedMarkdown(lines.join('\n'), [
    for (var i = 0; i < labels.length; i++)
      Footnote(
        number: i + 1,
        label: labels[i],
        text: defs[labels[i]]!,
        refLine: firstRef[labels[i]] ?? -1,
      ),
  ]);
}

/// Inline math: `$x^2$` or `$$x^2$$` on one line. A `$` followed by a space
/// or digit-only prices like "$5 and $10" do not start math.
final RegExp inlineMath = RegExp(
  r'(?<![\\$])\$\$([^$\n]+?)\$\$(?!\$)|(?<![\\$\w])\$(?![\s$])([^$\n]*?[^\s\\$])\$(?![\w$])',
);
