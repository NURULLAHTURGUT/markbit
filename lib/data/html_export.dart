import 'dart:convert';

import 'package:markdown/markdown.dart' as md;

import '../domain/markdown_extras.dart';
import '../domain/markdown_utils.dart';
import 'models/note.dart';
import 'note_images.dart';

/// A standalone HTML page for a note: styles inline, images embedded, math
/// rendered by KaTeX and Mermaid diagrams by Mermaid (both from a CDN, only
/// when the note uses them).
abstract final class HtmlExport {
  /// [noteHref] maps a linked note id to a link target (for exporting a whole
  /// library); without it wiki links become plain text.
  static String page(
    Note note, {
    String? Function(String title)? resolveNoteId,
    String? Function(String noteId)? noteHref,
    String language = 'en',
  }) {
    final title = _escape(note.displayTitle);
    if (note.kind == NoteKind.code) {
      return _shell(
        title,
        '<h1>$title</h1>\n<pre><code>${_escape(note.body)}</code></pre>',
        language: language,
      );
    }
    final body = bodyHtml(
      note,
      resolveNoteId: resolveNoteId,
      noteHref: noteHref,
    );
    return _shell(
      title,
      '${note.title.trim().isEmpty ? '' : '<h1 class="title">$title</h1>\n'}$body',
      language: language,
      math: body.contains('class="math'),
      mermaid: body.contains('class="mermaid"'),
    );
  }

  /// The note body as HTML (no page around it).
  static String bodyHtml(
    Note note, {
    String? Function(String title)? resolveNoteId,
    String? Function(String noteId)? noteHref,
  }) {
    final prepared = prepareMarkdown(NoteImages.expand(note));
    var text = linkifyWikiLinks(prepared.body, resolveNoteId ?? (_) => null);
    // App-internal links: other exported notes, or plain text.
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\(markbit://(note|create)/([^)]+)\)'),
      (m) {
        final href = m[2] == 'note' ? noteHref?.call(m[3]!) : null;
        return href == null ? m[1]! : '[${m[1]}](${Uri.encodeFull(href)})';
      },
    );
    text = text.replaceAll(RegExp(r'\s*<!-- task:.*? -->'), '');
    final numbers = prepared.numbers;
    var html = md.markdownToHtml(
      text,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [
        _MathHtmlSyntax(),
        if (numbers.isNotEmpty) _FootnoteHtmlSyntax(numbers),
      ],
    );
    // Fenced math and Mermaid blocks.
    html = html.replaceAllMapped(
      RegExp(
        r'<pre><code class="language-(math|latex|mermaid)">([\s\S]*?)</code></pre>',
      ),
      (m) => m[1] == 'mermaid'
          ? '<pre class="mermaid">${m[2]}</pre>'
          : '<div class="math display">\\[${m[2]}\\]</div>',
    );
    if (prepared.footnotes.isNotEmpty) {
      final items = prepared.footnotes
          .map(
            (f) =>
                '<li id="fn-${f.number}">${_inline(f.text)}'
                '${f.refLine >= 0 ? ' <a href="#fnref-${f.number}" class="back">&#8617;</a>' : ''}</li>',
          )
          .join('\n');
      html += '\n<section class="footnotes"><ol>\n$items\n</ol></section>';
    }
    return html;
  }

  static String _inline(String markdown) {
    final html = md
        .markdownToHtml(
          markdown,
          extensionSet: md.ExtensionSet.gitHubFlavored,
          inlineSyntaxes: [_MathHtmlSyntax()],
        )
        .trim();
    // A single paragraph renders inline in a list item.
    final single = RegExp(r'^<p>([\s\S]*)</p>$').firstMatch(html);
    return single != null && !single[1]!.contains('<p>') ? single[1]! : html;
  }

  static String _escape(String s) => const HtmlEscape().convert(s);

  static String _shell(
    String title,
    String content, {
    required String language,
    bool math = false,
    bool mermaid = false,
  }) {
    final scripts = StringBuffer();
    if (math) {
      scripts.writeln(
        '<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">\n'
        '<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>\n'
        '<script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js" '
        'onload="renderMathInElement(document.body,{delimiters:[{left:\'\\\\[\',right:\'\\\\]\',display:true},'
        '{left:\'\\\\(\',right:\'\\\\)\',display:false}]})"></script>',
      );
    }
    if (mermaid) {
      scripts.writeln(
        '<script type="module">import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";'
        'mermaid.initialize({startOnLoad:true,theme:matchMedia("(prefers-color-scheme: dark)").matches?"dark":"default"});</script>',
      );
    }
    return '''<!DOCTYPE html>
<html lang="$language">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="generator" content="Markbit">
<title>$title</title>
<style>
:root { color-scheme: light dark; --text:#1f2328; --muted:#5f6670; --border:#dad7d5; --code:#f1f1ef; --accent:#2a6bdb; --bg:#fcfcfb; }
@media (prefers-color-scheme: dark) { :root { --text:#e6e8eb; --muted:#a0a6b0; --border:#30323a; --code:#191a1e; --accent:#6ea8fe; --bg:#212227; } }
body { margin:0; background:var(--bg); color:var(--text); font:16px/1.65 -apple-system, "Segoe UI", Inter, Roboto, sans-serif; }
main { max-width:820px; margin:0 auto; padding:40px 24px 80px; }
h1,h2,h3,h4,h5,h6 { line-height:1.3; margin:1.4em 0 .5em; }
h1.title { margin-top:0; font-size:2.1em; }
a { color:var(--accent); }
code, pre { font-family:"Cascadia Code","JetBrains Mono",Consolas,monospace; font-size:.9em; }
code { background:var(--code); padding:.1em .35em; border-radius:4px; }
pre { background:var(--code); border:1px solid var(--border); border-radius:8px; padding:12px 14px; overflow:auto; }
pre code { background:none; padding:0; }
blockquote { margin:1em 0; padding:.4em 1em; border-left:3px solid var(--accent); color:var(--muted); }
table { border-collapse:collapse; margin:1em 0; }
th, td { border:1px solid var(--border); padding:6px 12px; }
th { background:var(--code); }
img { max-width:100%; height:auto; border-radius:6px; }
hr { border:none; border-top:1.5px solid var(--border); margin:2em 0; }
.math.display { text-align:center; overflow-x:auto; margin:1em 0; }
pre.mermaid { background:none; border:none; text-align:center; }
.footnotes { margin-top:3em; border-top:1px solid var(--border); font-size:.9em; color:var(--muted); }
.footnotes .back { text-decoration:none; }
li > input[type=checkbox] { margin-right:.4em; }
</style>
$scripts</head>
<body>
<main>
$content
</main>
</body>
</html>
''';
  }
}

/// `$x$` becomes `\(x\)` for KaTeX's auto-render.
class _MathHtmlSyntax extends md.InlineSyntax {
  _MathHtmlSyntax() : super(inlineMath.pattern, startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    final tex = match[1] ?? match[2]!;
    parser.addNode(
      // Text nodes added here are written as-is, so escape them.
      md.Element('span', [
        md.Text(
          const HtmlEscape(
            HtmlEscapeMode.element,
          ).convert(display ? '\\[$tex\\]' : '\\($tex\\)'),
        ),
      ])..attributes['class'] = display ? 'math display' : 'math',
    );
    return true;
  }
}

class _FootnoteHtmlSyntax extends md.InlineSyntax {
  _FootnoteHtmlSyntax(this.numbers)
    : super(
        r'\[\^(' + numbers.keys.map(RegExp.escape).join('|') + r')\]',
        startCharacter: 0x5B,
      );
  final Map<String, int> numbers;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final n = numbers[match[1]]!;
    parser.addNode(
      md.Element('sup', [
        md.Element('a', [md.Text('$n')])
          ..attributes['href'] = '#fn-$n'
          ..attributes['id'] = 'fnref-$n',
      ]),
    );
    return true;
  }
}
