import 'note_images.dart';
import '../domain/colored_text.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/l10n/app_strings.dart';
import '../domain/markdown_utils.dart';
import '../domain/visual_block.dart';
import '../domain/ai/ai_visuals.dart';
import '../features/dialogs/dialogs.dart';
import 'models/note.dart';
import 'export_service.dart';

abstract final class PdfExportService {
  static Future<Uint8List> generate(
    Note note, {
    PdfPageFormat format = PdfPageFormat.a4,
  }) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final typefaces = <String, pw.Font>{
      'Inter': pw.Font.ttf(
        await rootBundle.load('assets/fonts/Inter-Regular.ttf'),
      ),
    };
    if (Platform.isWindows) {
      final folder = '${Platform.environment['WINDIR'] ?? 'C:/Windows'}/Fonts';
      for (final entry in {
        'Segoe UI': 'segoeui.ttf',
        'Arial': 'arial.ttf',
        'Georgia': 'georgia.ttf',
        'Consolas': 'consola.ttf',
      }.entries) {
        try {
          final bytes = await File('$folder/${entry.value}').readAsBytes();
          typefaces[entry.key] = pw.Font.ttf(ByteData.sublistView(bytes));
        } catch (_) {
          /* Use the document font when a system font is absent. */
        }
      }
    }
    final document = pw.Document(
      title: note.displayTitle,
      author: 'Markbit',
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        italic: font,
        boldItalic: font,
      ),
    );
    final widgets = <pw.Widget>[
      pw.Text(
        note.displayTitle,
        style: pw.TextStyle(fontSize: 23, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 16),
    ];
    if (note.coverImage != null) {
      final bytes = note.coverImage!.startsWith('file:')
          ? await File.fromUri(Uri.parse(note.coverImage!)).readAsBytes()
          : base64Decode(note.coverImage!);
      widgets.add(
        pw.SizedBox(
          height: 150,
          child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
        ),
      );
      widgets.add(pw.SizedBox(height: 14));
    }
    if (note.kind == NoteKind.code) {
      for (final line in note.body.split('\n')) {
        widgets.add(
          pw.Text(
            line.isEmpty ? ' ' : line,
            style: const pw.TextStyle(fontSize: 9),
          ),
        );
      }
    } else {
      for (final segment in splitSegments(NoteImages.expand(note))) {
        if (segment is CodeSegment) {
          final visual = aiVisual(segment.info, segment.code);
          if (visual != null) {
            widgets.addAll(_visual(visual));
          } else {
            for (final line in segment.code.split('\n')) {
              widgets.add(
                pw.Container(
                  width: double.infinity,
                  color: PdfColors.grey100,
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: pw.Text(
                    line.isEmpty ? ' ' : line,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
              );
            }
          }
        } else if (segment is TextSegment) {
          final nodes = md.Document(
            extensionSet: md.ExtensionSet.gitHubFlavored,
            inlineSyntaxes: [ColoredTextSyntax()],
            blockSyntaxes: [ColoredTextBlockSyntax()],
          ).parseLines(segment.text.split('\n'));
          for (final node in nodes) {
            widgets.addAll(_node(node, typefaces));
          }
        }
        widgets.add(pw.SizedBox(height: 8));
      }
    }
    document.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(36),
        maxPages: 1000,
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (_) => widgets,
      ),
    );
    return document.save();
  }

  static List<pw.Widget> _node(md.Node node, Map<String, pw.Font> typefaces) {
    if (node is! md.Element) return [pw.Paragraph(text: node.textContent)];
    final children = node.children ?? [];
    if (node.tag == 'img') {
      try {
        final source = Uri.parse(node.attributes['src'] ?? '');
        if (source.scheme == 'data') {
          return [
            pw.SizedBox(
              height: 220 * NoteImages.width(node.attributes['title']) / 100,
              width: 480 * NoteImages.width(node.attributes['title']) / 100,
              child: pw.Image(
                pw.MemoryImage(source.data!.contentAsBytes()),
                fit: pw.BoxFit.contain,
              ),
            ),
            if ((node.attributes['title'] ?? '').contains('caption=1'))
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text(
                  node.attributes['alt'] ?? '',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
          ];
        }
      } catch (_) {}
      return [pw.Paragraph(text: node.attributes['alt'] ?? '')];
    }
    if (node.tag == 'table') {
      bool hasImage(md.Node n) =>
          n is md.Element &&
          (n.tag == 'img' || (n.children ?? []).any(hasImage));
      if (hasImage(node)) {
        final rows = <md.Element>[];
        void imageRows(md.Node n) {
          if (n is! md.Element) return;
          if (n.tag == 'tr') {
            rows.add(n);
          } else {
            for (final child in n.children ?? <md.Node>[]) {
              imageRows(child);
            }
          }
        }

        imageRows(node);
        return [
          pw.Table(
            children: [
              for (final row in rows)
                pw.TableRow(
                  children: [
                    for (final cell in row.children ?? <md.Node>[])
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Column(
                          children: [
                            for (final child
                                in (cell as md.Element).children ?? <md.Node>[])
                              ..._node(child, typefaces),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ];
      }

      final rows = <List<String>>[];
      void visit(md.Node item) {
        if (item is! md.Element) return;
        if (item.tag == 'tr') {
          rows.add((item.children ?? []).map((c) => c.textContent).toList());
        } else {
          for (final child in item.children ?? <md.Node>[]) {
            visit(child);
          }
        }
      }

      visit(node);
      return [
        if (rows.isNotEmpty)
          pw.TableHelper.fromTextArray(
            headers: rows.first,
            data: rows.skip(1).toList(),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
      ];
    }
    if (node.tag == 'ul' || node.tag == 'ol') {
      var index = 0;
      return [
        for (final child in children)
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 12, bottom: 5),
            child: pw.Paragraph(
              text:
                  '${node.tag == 'ol' ? '${++index}.' : '•'} ${child.textContent}',
            ),
          ),
      ];
    }
    if (node.tag == 'hr') return [pw.Divider()];
    if (node.tag == 'blockquote') {
      return [
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey100,
            border: pw.Border(left: pw.BorderSide(color: PdfColors.blue)),
          ),
          child: pw.Paragraph(text: node.textContent),
        ),
      ];
    }
    final images = <md.Element>[];
    void imageNodes(md.Node item) {
      if (item is md.Element) {
        if (item.tag == 'img') images.add(item);
        for (final c in item.children ?? <md.Node>[]) {
          imageNodes(c);
        }
      }
    }

    imageNodes(node);
    final heading = RegExp(r'^h([1-6])$').firstMatch(node.tag);
    return [
      pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 7, top: heading == null ? 0 : 8),
        child: pw.RichText(
          text: pw.TextSpan(
            children: children.map((c) => _inline(c, typefaces)).toList(),
            style: pw.TextStyle(
              fontSize: heading == null ? 11 : 23 - int.parse(heading[1]!) * 2,
              fontWeight: heading == null
                  ? pw.FontWeight.normal
                  : pw.FontWeight.bold,
            ),
          ),
        ),
      ),
      for (final image in images) ..._node(image, typefaces),
    ];
  }

  static pw.TextSpan _inline(md.Node node, Map<String, pw.Font> typefaces) {
    if (node is! md.Element) return pw.TextSpan(text: node.textContent);
    if (node.tag == 'br') return const pw.TextSpan(text: '\n');
    if (node.tag == 'input') {
      return pw.TextSpan(
        text: node.attributes.containsKey('checked') ? '[x] ' : '[ ] ',
      );
    }
    if (node.tag == 'img') return const pw.TextSpan(text: '');
    return pw.TextSpan(
      children: (node.children ?? [])
          .map((child) => _inline(child, typefaces))
          .toList(),
      style: pw.TextStyle(
        font: typefaces[node.attributes['font-family']],
        fontWeight: node.tag == 'strong' ? pw.FontWeight.bold : null,
        fontStyle: node.tag == 'em' ? pw.FontStyle.italic : null,
        fontSize: node.tag == 'markbit-color'
            ? double.tryParse(node.attributes['font-size'] ?? '')
            : null,
        color: node.tag == 'markbit-color' && node.attributes['color'] != null
            ? PdfColor.fromHex('#${node.attributes['color']}')
            : node.tag == 'a'
            ? PdfColors.blue
            : null,
        background: node.tag == 'code'
            ? pw.BoxDecoration(color: PdfColors.grey100)
            : null,
      ),
    );
  }

  static List<pw.Widget> _visual(VisualBlock block) {
    const colors = [
      PdfColors.blue,
      PdfColors.teal,
      PdfColors.orange,
      PdfColors.purple,
      PdfColors.red,
      PdfColors.green,
    ];
    final result = <pw.Widget>[
      pw.Text(
        block.title,
        style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 10),
    ];
    if (block.kind == VisualKind.mindmap) {
      for (final item in block.items) {
        result.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(left: item.depth * 24.0, bottom: 6),
            child: pw.Row(
              children: [
                if (item.depth > 0)
                  pw.Container(width: 20, height: 1, color: PdfColors.blue),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: pw.BorderRadius.circular(6),
                      border: pw.Border.all(color: PdfColors.blue200),
                    ),
                    child: pw.Text(item.label),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      return _keepVisualHeading(result);
    }
    if (block.style == ChartStyle.donut || block.style == ChartStyle.pie) {
      result.add(
        pw.SizedBox(
          height: 240,
          child: pw.Chart(
            grid: pw.PieGrid(),
            datasets: [
              for (var i = 0; i < block.items.length; i++)
                pw.PieDataSet(
                  value: block.items[i].value,
                  color: colors[i % colors.length],
                  innerRadius: block.style == ChartStyle.pie ? 0 : .55,
                ),
            ],
          ),
        ),
      );
    } else {
      final values = block.items.map((i) => i.value);
      final low = math.min(0.0, values.reduce(math.min));
      var high = math.max(0.0, values.reduce(math.max));
      if (high == low) high = low + 1;
      final horizontal = block.style == ChartStyle.horizontalBar;
      final points = [
        for (var i = 0; i < block.items.length; i++)
          horizontal
              ? pw.PointChartValue(block.items[i].value, i + 1)
              : pw.PointChartValue(i + 1, block.items[i].value),
      ];
      final categories = pw.FixedAxis(
        [
          0,
          ...List.generate(block.items.length, (i) => i + 1),
          block.items.length + 1,
        ],
        format: (n) => n == 0 || n == block.items.length + 1 ? '' : '$n',
        textStyle: const pw.TextStyle(fontSize: 8),
      );
      final amounts = pw.FixedAxis(
        List.generate(5, (i) => low + (high - low) * i / 4),
        divisions: true,
        textStyle: const pw.TextStyle(fontSize: 8),
      );
      result.add(
        pw.SizedBox(
          height: 240,
          child: pw.Chart(
            grid: pw.CartesianGrid(
              xAxis: horizontal ? amounts : categories,
              yAxis: horizontal ? categories : amounts,
            ),
            datasets: [
              (block.style == ChartStyle.line || block.style == ChartStyle.area)
                  ? pw.LineDataSet(
                      data: points,
                      color: PdfColors.blue,
                      drawPoints: true,
                      drawSurface: block.style == ChartStyle.area,
                    )
                  : pw.BarDataSet(
                      data: points,
                      color: PdfColors.blue,
                      axis: horizontal ? pw.Axis.vertical : pw.Axis.horizontal,
                      width: math.min(14.0, 260 / block.items.length),
                    ),
            ],
          ),
        ),
      );
    }
    result.add(pw.SizedBox(height: 10));
    for (var i = 0; i < block.items.length; i++) {
      result.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            children: [
              pw.Container(
                width: 8,
                height: 8,
                color:
                    (block.style == ChartStyle.donut ||
                        block.style == ChartStyle.pie)
                    ? colors[i % colors.length]
                    : PdfColors.blue,
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(child: pw.Text('${i + 1}. ${block.items[i].label}')),
              pw.Text('${block.items[i].value}'),
            ],
          ),
        ),
      );
    }
    return _keepVisualHeading(result);
  }

  static List<pw.Widget> _keepVisualHeading(List<pw.Widget> widgets) => [
    pw.Inseparable(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: widgets.take(3).toList(),
      ),
    ),
    ...widgets.skip(3),
  ];

  static Future<void> export(
    BuildContext context,
    Note note, {
    bool print = false,
  }) async {
    try {
      if (print) {
        await Printing.layoutPdf(
          name: note.displayTitle,
          onLayout: (format) => generate(note, format: format),
        );
        return;
      }
      final path = await FilePicker.saveFile(
        fileName: '${ExportService.safeName(note.displayTitle)}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path == null) return;
      final bytes = await generate(note);
      await File(path).writeAsBytes(bytes, flush: true);
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
}
