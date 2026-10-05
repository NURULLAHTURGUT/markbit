import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// Image-only Markdown tables remain portable while previewing as a gallery.
class ImageGallerySyntax extends md.BlockSyntax {
  static final image = RegExp(r'!\[(?:\\.|[^\]])*\]\([^\n]+?\)');
  @override
  RegExp get pattern => RegExp(r'^\s*\|');
  static bool imageRow(String line) {
    final values = line
        .trim()
        .split('|')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    return values.isNotEmpty &&
        values.every((s) => image.stringMatch(s.trim()) == s.trim());
  }

  @override
  bool canParse(md.BlockParser parser) =>
      imageRow(parser.current.content) &&
      parser.next != null &&
      RegExp(r'^\s*\|(?:\s*:?-+:?\s*\|)+\s*$').hasMatch(parser.next!.content);
  @override
  md.Node parse(md.BlockParser parser) {
    final rows = <String>[parser.current.content];
    parser.advance();
    parser.advance();
    while (!parser.isDone && imageRow(parser.current.content)) {
      rows.add(parser.current.content);
      parser.advance();
    }
    final nodes = <md.Node>[];
    for (final row in rows) {
      for (final cell
          in row.trim().split('|').where((s) => s.trim().isNotEmpty)) {
        nodes.addAll(
          md.Document()
              .parseInline(cell.trim())
              .whereType<md.Element>()
              .where((n) => n.tag == 'img'),
        );
      }
    }
    return md.Element.empty('markbit-gallery')
      ..attributes['images'] = jsonEncode(
        nodes.whereType<md.Element>().map((node) => node.attributes).toList(),
      );
  }
}

class ImageGalleryBuilder extends MarkdownElementBuilder {
  ImageGalleryBuilder(this.image);
  final Widget Function(Uri, String?, String?) image;
  @override
  bool isBlockElement() => true;
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final items = (jsonDecode(element.attributes['images'] ?? '[]') as List)
        .map((raw) {
          final node = Map<String, dynamic>.from(raw as Map);
          return image(
            Uri.parse(node['src'] as String? ?? ''),
            node['title'] as String?,
            node['alt'] as String?,
          );
        })
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 480 ? 2 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final item in items) SizedBox(width: width, child: item),
            ],
          ),
        );
      },
    );
  }
}
