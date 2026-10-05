import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:markdown/markdown.dart' as md;

import '../domain/markdown_extras.dart';
import '../domain/markdown_utils.dart';
import 'models/note.dart';
import 'note_images.dart';

/// Word (.docx) export of a note, built from its Markdown: headings,
/// paragraphs with bold/italic/strike/code/links, nested lists and task
/// lists, quotes, code blocks, tables, images, math (as TeX) and footnotes.
abstract final class DocxExport {
  static Uint8List build(Note note) => _DocxWriter(note).build();
}

class _Media {
  _Media(this.id, this.name, this.bytes, this.width, this.height);
  final String id, name;
  final Uint8List bytes;
  final int width, height;
}

class _Run {
  const _Run(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
    this.link,
    this.superscript = false,
    this.math = false,
  });
  final String text;
  final bool bold, italic, strike, code, superscript, math;
  final String? link;
}

class _DocxWriter {
  _DocxWriter(this.note);
  final Note note;
  final _body = StringBuffer();
  final _rels = <String, String>{}; // id -> hyperlink target
  final _media = <_Media>[];
  final _numbering = <String>[]; // extra <w:num> entries
  var _nextNum = 3; // 1 = bullets, 2 = first ordered list
  var _relId = 10;
  late Map<String, int> _footnotes;

  static String _x(String s) => const HtmlEscape(
    HtmlEscapeMode.element,
  ).convert(s).replaceAll('"', '&quot;');

  Uint8List build() {
    final prepared = prepareMarkdown(NoteImages.expand(note));
    _footnotes = prepared.numbers;
    if (note.title.trim().isNotEmpty) {
      _paragraph([_Run(note.title.trim())], style: 'Title');
    }
    if (note.kind == NoteKind.code) {
      for (final line in note.body.split('\n')) {
        _paragraph([_Run(line, code: true)], style: 'Code');
      }
    } else {
      final text = linkifyWikiLinks(prepared.body, (_) => null)
          .replaceAllMapped(
            RegExp(r'\[([^\]]*)\]\(markbit://[^)]*\)'),
            (m) => m[1]!,
          )
          .replaceAll(RegExp(r'\s*<!-- task:.*? -->'), '')
          // Coloured text keeps its words; Word styling is not mapped.
          .replaceAll(RegExp(r'</?span[^>]*>'), '');
      final doc = md.Document(
        extensionSet: md.ExtensionSet.gitHubFlavored,
        encodeHtml: false,
        inlineSyntaxes: [
          _TexSyntax(),
          if (_footnotes.isNotEmpty) _RefSyntax(_footnotes),
        ],
      );
      _blocks(doc.parse(text), 0);
      if (prepared.footnotes.isNotEmpty) {
        _paragraph([const _Run('Notes', bold: true)], style: 'Heading3');
        for (final f in prepared.footnotes) {
          _paragraph([
            _Run('${f.number}. ', bold: true),
            ..._inlines(
              md.Document(
                extensionSet: md.ExtensionSet.gitHubFlavored,
                encodeHtml: false,
              ).parseInline(f.text),
              const _Run(''),
            ),
          ], style: 'Footnote');
        }
      }
    }
    return _zip();
  }

  // ------------------------------------------------------------------ blocks

  void _blocks(List<md.Node> nodes, int depth) {
    for (final node in nodes) {
      if (node is md.Text) {
        if (node.text.trim().isNotEmpty) _paragraph([_Run(node.text)]);
        continue;
      }
      if (node is! md.Element) continue;
      switch (node.tag) {
        case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
          _paragraph(
            _inlines(node.children ?? [], const _Run('')),
            style: 'Heading${node.tag.substring(1)}',
          );
        case 'p':
          _paragraphWithImages(node.children ?? []);
        case 'blockquote':
          for (final child in node.children ?? <md.Node>[]) {
            if (child is md.Element && child.tag == 'p') {
              _paragraph(
                _inlines(child.children ?? [], const _Run('')),
                style: 'Quote',
              );
            } else {
              _blocks([child], depth);
            }
          }
        case 'pre':
          final code = node.children?.firstOrNull;
          final lang = code is md.Element
              ? (code.attributes['class'] ?? '').replaceFirst('language-', '')
              : '';
          final text = (code ?? node).textContent.replaceFirst(
            RegExp(r'\n$'),
            '',
          );
          if (lang == 'math' || lang == 'latex') {
            _paragraph([_Run(text, math: true)], style: 'MathBlock');
          } else {
            for (final line in text.split('\n')) {
              _paragraph([_Run(line, code: true)], style: 'Code');
            }
          }
        case 'ul' || 'ol':
          _list(node, depth);
        case 'table':
          _table(node);
        case 'hr':
          _body.write(
            '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="BBBBBB"/></w:pBdr></w:pPr></w:p>',
          );
        default:
          _blocks(node.children ?? [], depth);
      }
    }
  }

  void _list(md.Element list, int depth) {
    final ordered = list.tag == 'ol';
    var numId = 1;
    if (ordered) {
      // Each ordered list restarts at its own start number.
      numId = _nextNum++;
      final start = int.tryParse(list.attributes['start'] ?? '') ?? 1;
      _numbering.add(
        '<w:num w:numId="$numId"><w:abstractNumId w:val="1"/>'
        '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="$start"/></w:lvlOverride></w:num>',
      );
    }
    for (final item in list.children ?? <md.Node>[]) {
      if (item is! md.Element || item.tag != 'li') continue;
      final runs = <_Run>[];
      final nested = <md.Element>[];
      void collect(List<md.Node> nodes) {
        for (final c in nodes) {
          if (c is md.Element && (c.tag == 'ul' || c.tag == 'ol')) {
            nested.add(c);
          } else if (c is md.Element && c.tag == 'p') {
            if (runs.isNotEmpty) runs.add(const _Run(' '));
            collect(c.children ?? []);
          } else if (c is md.Element && c.tag == 'input') {
            runs.add(_Run(c.attributes['checked'] != null ? '☑ ' : '☐ '));
          } else {
            runs.addAll(_inlines([c], const _Run('')));
          }
        }
      }

      collect(item.children ?? []);
      final level = math.min(depth, 8);
      _paragraph(
        runs,
        style: 'ListParagraph',
        extra:
            '<w:numPr><w:ilvl w:val="$level"/><w:numId w:val="$numId"/></w:numPr>',
      );
      for (final n in nested) {
        _list(n, depth + 1);
      }
    }
  }

  void _table(md.Element table) {
    final rows = <(bool, List<md.Element>)>[];
    void walk(md.Element e, bool head) {
      for (final c in e.children ?? <md.Node>[]) {
        if (c is! md.Element) continue;
        if (c.tag == 'thead') walk(c, true);
        if (c.tag == 'tbody') walk(c, false);
        if (c.tag == 'tr') {
          rows.add((
            head,
            [
              for (final cell in c.children ?? <md.Node>[])
                if (cell is md.Element) cell,
            ],
          ));
        }
      }
    }

    walk(table, false);
    if (rows.isEmpty) return;
    final columns = rows.map((r) => r.$2.length).reduce(math.max);
    const width = 9000; // twentieths of a point across the text area
    final cellWidth = width ~/ math.max(1, columns);
    _body.write(
      '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="$width" w:type="dxa"/>'
      '<w:tblBorders>'
      '<w:top w:val="single" w:sz="4" w:color="BFBFBF"/><w:left w:val="single" w:sz="4" w:color="BFBFBF"/>'
      '<w:bottom w:val="single" w:sz="4" w:color="BFBFBF"/><w:right w:val="single" w:sz="4" w:color="BFBFBF"/>'
      '<w:insideH w:val="single" w:sz="4" w:color="BFBFBF"/><w:insideV w:val="single" w:sz="4" w:color="BFBFBF"/>'
      '</w:tblBorders></w:tblPr><w:tblGrid>',
    );
    for (var i = 0; i < columns; i++) {
      _body.write('<w:gridCol w:w="$cellWidth"/>');
    }
    _body.write('</w:tblGrid>');
    for (final (head, cells) in rows) {
      _body.write('<w:tr>${head ? '<w:trPr><w:tblHeader/></w:trPr>' : ''}');
      for (var i = 0; i < columns; i++) {
        final cell = i < cells.length ? cells[i] : null;
        final align = switch (cell?.attributes['align'] ??
            cell?.attributes['style'] ??
            '') {
          final s when s.contains('center') => 'center',
          final s when s.contains('right') => 'right',
          _ => 'left',
        };
        _body.write(
          '<w:tc><w:tcPr><w:tcW w:w="$cellWidth" w:type="dxa"/>'
          '${head ? '<w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>' : ''}</w:tcPr>',
        );
        _paragraph(
          cell == null
              ? const []
              : _inlines(cell.children ?? [], _Run('', bold: head)),
          extra:
              '<w:jc w:val="$align"/><w:spacing w:before="40" w:after="40"/>',
        );
        _body.write('</w:tc>');
      }
      _body.write('</w:tr>');
    }
    _body.write('</w:tbl>');
    _paragraph(const []);
  }

  /// A paragraph; images inside it become their own paragraphs.
  void _paragraphWithImages(List<md.Node> children) {
    var pending = <md.Node>[];
    void flush() {
      if (pending.any((n) => n.textContent.trim().isNotEmpty)) {
        _paragraph(_inlines(pending, const _Run('')));
      }
      pending = [];
    }

    for (final c in children) {
      if (c is md.Element && c.tag == 'img') {
        flush();
        _image(c.attributes['src'] ?? '', c.attributes['alt'] ?? '');
      } else {
        pending.add(c);
      }
    }
    flush();
  }

  // ----------------------------------------------------------------- inlines

  List<_Run> _inlines(List<md.Node> nodes, _Run style) {
    final runs = <_Run>[];
    for (final node in nodes) {
      if (node is md.Text) {
        runs.add(
          _Run(
            _decode(node.text),
            bold: style.bold,
            italic: style.italic,
            strike: style.strike,
            code: style.code,
            link: style.link,
          ),
        );
        continue;
      }
      if (node is! md.Element) continue;
      _Run next(bool b, bool i, bool s, bool c, String? link) => _Run(
        '',
        bold: style.bold || b,
        italic: style.italic || i,
        strike: style.strike || s,
        code: style.code || c,
        link: link ?? style.link,
      );
      switch (node.tag) {
        case 'strong':
          runs.addAll(
            _inlines(
              node.children ?? [],
              next(true, false, false, false, null),
            ),
          );
        case 'em':
          runs.addAll(
            _inlines(
              node.children ?? [],
              next(false, true, false, false, null),
            ),
          );
        case 'del':
          runs.addAll(
            _inlines(
              node.children ?? [],
              next(false, false, true, false, null),
            ),
          );
        case 'code':
          runs.add(
            _Run(_decode(node.textContent), code: true, link: style.link),
          );
        case 'a':
          runs.addAll(
            _inlines(
              node.children ?? [],
              next(false, false, false, false, node.attributes['href']),
            ),
          );
        case 'br':
          runs.add(const _Run('\n'));
        case 'img':
          runs.add(
            _Run('[${node.attributes['alt'] ?? 'image'}]', italic: true),
          );
        case 'markbit-tex':
          runs.add(_Run(node.textContent, math: true));
        case 'markbit-ref':
          runs.add(_Run(node.textContent, superscript: true));
        default:
          runs.addAll(_inlines(node.children ?? [], style));
      }
    }
    return runs;
  }

  static String _decode(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  void _paragraph(List<_Run> runs, {String? style, String extra = ''}) {
    _body.write('<w:p>');
    if (style != null || extra.isNotEmpty) {
      _body.write(
        '<w:pPr>${style == null ? '' : '<w:pStyle w:val="$style"/>'}$extra</w:pPr>',
      );
    }
    for (final run in runs) {
      _run(run);
    }
    _body.write('</w:p>');
  }

  void _run(_Run run) {
    if (run.text.isEmpty) return;
    final props = StringBuffer();
    if (run.link != null) props.write('<w:rStyle w:val="Hyperlink"/>');
    if (run.code) {
      props.write(
        '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>'
        '<w:shd w:val="clear" w:color="auto" w:fill="F1F1EF"/>',
      );
    }
    if (run.math) {
      props.write(
        '<w:rFonts w:ascii="Cambria Math" w:hAnsi="Cambria Math"/><w:i/>',
      );
    }
    if (run.bold) props.write('<w:b/>');
    if (run.italic) props.write('<w:i/>');
    if (run.strike) props.write('<w:strike/>');
    if (run.superscript) props.write('<w:vertAlign w:val="superscript"/>');
    final parts = run.text.split('\n');
    final xml = StringBuffer('<w:r>');
    if (props.isNotEmpty) xml.write('<w:rPr>$props</w:rPr>');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) xml.write('<w:br/>');
      xml.write('<w:t xml:space="preserve">${_x(parts[i])}</w:t>');
    }
    xml.write('</w:r>');
    final link = run.link;
    if (link != null && Uri.tryParse(link)?.hasScheme == true) {
      final id = 'rId${_relId++}';
      _rels[id] = link;
      _body.write('<w:hyperlink r:id="$id">$xml</w:hyperlink>');
    } else {
      _body.write(xml);
    }
  }

  // ------------------------------------------------------------------ images

  void _image(String src, String alt) {
    final data = Uri.tryParse(src)?.data;
    if (data == null) {
      _paragraph([_Run('[$alt]', italic: true)]);
      return;
    }
    final bytes = data.contentAsBytes();
    final size = _imageSize(bytes);
    final ext = switch (data.mimeType) {
      'image/png' => 'png',
      'image/jpeg' => 'jpeg',
      'image/gif' => 'gif',
      _ => null,
    };
    if (size == null || ext == null) {
      _paragraph([_Run('[$alt]', italic: true)]);
      return;
    }
    final id = 'rId${_relId++}';
    final name = 'image${_media.length + 1}.$ext';
    _media.add(_Media(id, name, bytes, size.$1, size.$2));
    // At most the text width (6 in), keeping the aspect ratio.
    const emuPerPx = 9525, maxWidth = 5486400;
    var cx = size.$1 * emuPerPx, cy = size.$2 * emuPerPx;
    if (cx > maxWidth) {
      cy = cy * maxWidth ~/ cx;
      cx = maxWidth;
    }
    final n = _media.length;
    _body.write(
      '<w:p><w:pPr><w:jc w:val="center"/></w:pPr><w:r><w:drawing>'
      '<wp:inline distT="0" distB="0" distL="0" distR="0">'
      '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="$n" name="${_x(alt.isEmpty ? name : alt)}"/>'
      '<a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
      '<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<pic:nvPicPr><pic:cNvPr id="$n" name="$name"/><pic:cNvPicPr/></pic:nvPicPr>'
      '<pic:blipFill><a:blip r:embed="$id"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
      '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
      '</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>',
    );
  }

  /// Pixel size of a PNG, GIF or JPEG from its header.
  static (int, int)? _imageSize(Uint8List b) {
    if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50) {
      final v = ByteData.sublistView(b);
      return (v.getUint32(16), v.getUint32(20));
    }
    if (b.length > 10 && b[0] == 0x47 && b[1] == 0x49) {
      return (b[6] | b[7] << 8, b[8] | b[9] << 8);
    }
    if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
      var i = 2;
      while (i + 9 < b.length) {
        if (b[i] != 0xFF) return null;
        final marker = b[i + 1];
        final length = b[i + 2] << 8 | b[i + 3];
        if (marker >= 0xC0 &&
            marker <= 0xCF &&
            marker != 0xC4 &&
            marker != 0xC8 &&
            marker != 0xCC) {
          return (b[i + 7] << 8 | b[i + 8], b[i + 5] << 8 | b[i + 6]);
        }
        i += 2 + length;
      }
    }
    return null;
  }

  // --------------------------------------------------------------- packaging

  Uint8List _zip() {
    final archive = Archive();
    void add(String path, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add(
      '[Content_Types].xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="png" ContentType="image/png"/>
<Default Extension="jpeg" ContentType="image/jpeg"/>
<Default Extension="gif" ContentType="image/gif"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
</Types>''',
    );
    add(
      '_rels/.rels',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
</Relationships>''',
    );
    add(
      'docProps/core.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<dc:title>${_x(note.displayTitle)}</dc:title>
<dc:creator>Markbit</dc:creator>
<dcterms:created xsi:type="dcterms:W3CDTF">${note.createdAt.toUtc().toIso8601String()}</dcterms:created>
<dcterms:modified xsi:type="dcterms:W3CDTF">${note.updatedAt.toUtc().toIso8601String()}</dcterms:modified>
</cp:coreProperties>''',
    );
    final rels = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>',
    );
    for (final e in _rels.entries) {
      rels.write(
        '<Relationship Id="${e.key}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" '
        'Target="${_x(e.value)}" TargetMode="External"/>',
      );
    }
    for (final m in _media) {
      rels.write(
        '<Relationship Id="${m.id}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${m.name}"/>',
      );
      archive.addFile(
        ArchiveFile('word/media/${m.name}', m.bytes.length, m.bytes),
      );
    }
    rels.write('</Relationships>');
    add('word/_rels/document.xml.rels', rels.toString());
    add(
      'word/document.xml',
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
<w:body>$_body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1418" w:right="1418" w:bottom="1418" w:left="1418" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body>
</w:document>''',
    );
    add('word/styles.xml', _styles);
    add('word/numbering.xml', _numberingXml());
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  String _numberingXml() {
    String levels(bool bullet) => [
      for (var l = 0; l < 9; l++)
        '<w:lvl w:ilvl="$l"><w:start w:val="1"/>'
            '<w:numFmt w:val="${bullet ? 'bullet' : const ['decimal', 'lowerLetter', 'lowerRoman'][l % 3]}"/>'
            '<w:lvlText w:val="${bullet ? const ['•', '◦', '▪'][l % 3] : '%${l + 1}.'}"/>'
            '<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="${720 + l * 360}" w:hanging="360"/></w:pPr></w:lvl>',
    ].join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>${levels(true)}</w:abstractNum>'
        '<w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>${levels(false)}</w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
        '${_numbering.join()}'
        '</w:numbering>';
  }

  static const _styles =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="120" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="240"/></w:pPr><w:rPr><w:b/><w:sz w:val="48"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="300" w:after="100"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="3"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading5"><w:name w:val="heading 5"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="4"/></w:pPr><w:rPr><w:b/><w:sz w:val="22"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading6"><w:name w:val="heading 6"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:outlineLvl w:val="5"/></w:pPr><w:rPr><w:b/><w:i/><w:sz w:val="22"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="40"/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:pPr><w:ind w:left="567"/><w:pBdr><w:left w:val="single" w:sz="18" w:space="8" w:color="2A6BDB"/></w:pBdr></w:pPr><w:rPr><w:color w:val="5F6670"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:shd w:val="clear" w:color="auto" w:fill="F1F1EF"/></w:pPr><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/><w:sz w:val="19"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="MathBlock"><w:name w:val="Math Block"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="center"/></w:pPr><w:rPr><w:rFonts w:ascii="Cambria Math" w:hAnsi="Cambria Math"/><w:i/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Footnote"><w:name w:val="Footnote"/><w:basedOn w:val="Normal"/><w:rPr><w:sz w:val="18"/><w:color w:val="5F6670"/></w:rPr></w:style>
<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="2A6BDB"/><w:u w:val="single"/></w:rPr></w:style>
<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:tblPr><w:tblCellMar><w:left w:w="108" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>
</w:styles>''';
}

/// `$x$` in DOCX: kept as TeX text in a math font.
class _TexSyntax extends md.InlineSyntax {
  _TexSyntax() : super(inlineMath.pattern, startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element('markbit-tex', [md.Text(match[1] ?? match[2]!)]));
    return true;
  }
}

class _RefSyntax extends md.InlineSyntax {
  _RefSyntax(this.numbers)
    : super(
        r'\[\^(' + numbers.keys.map(RegExp.escape).join('|') + r')\]',
        startCharacter: 0x5B,
      );
  final Map<String, int> numbers;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element('markbit-ref', [md.Text('${numbers[match[1]]}')]),
    );
    return true;
  }
}
