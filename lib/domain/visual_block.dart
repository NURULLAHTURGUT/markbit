import 'dart:convert';

enum VisualKind { mindmap, chart }

enum ChartStyle { bar, line, donut, pie, horizontalBar, area }

class VisualItem {
  const VisualItem(this.label, {this.depth = 0, this.value = 0});
  final String label;
  final int depth;
  final double value;
}

/// Stored inside Markdown so diagrams survive saves, duplicates and exports.
class VisualBlock {
  const VisualBlock({
    required this.kind,
    required this.title,
    required this.items,
    this.style = ChartStyle.bar,
  });
  static const fence = 'markbit-visual';
  final VisualKind kind;
  final String title;
  final List<VisualItem> items;
  final ChartStyle style;

  factory VisualBlock.fromInput({
    required VisualKind kind,
    required String title,
    required String input,
    ChartStyle style = ChartStyle.bar,
  }) {
    final lines = input.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (title.trim().isEmpty ||
        title.trim().length > 120 ||
        lines.isEmpty ||
        lines.length > 24) {
      throw const FormatException('Use a title and 1–24 entries.');
    }
    final items = <VisualItem>[];
    for (final line in lines) {
      if (kind == VisualKind.mindmap) {
        final indent = line.length - line.trimLeft().length;
        final depth = indent ~/ 2;
        if (indent.isOdd ||
            depth > 4 ||
            (items.isEmpty && depth != 0) ||
            (items.isNotEmpty && depth > items.last.depth + 1)) {
          throw const FormatException(
            'Indent child topics with two spaces, up to five levels.',
          );
        }
        final label = line.trim();
        if (label.length > 80) {
          throw const FormatException('Keep labels under 80 characters.');
        }
        items.add(VisualItem(label, depth: depth));
      } else {
        final separator = line.lastIndexOf(';');
        if (separator < 1) {
          throw const FormatException('Enter one label; value pair per line.');
        }
        final label = line.substring(0, separator).trim();
        final value = double.tryParse(
          line.substring(separator + 1).trim().replaceAll(',', '.'),
        );
        if (label.isEmpty ||
            label.length > 80 ||
            value == null ||
            !value.isFinite ||
            ((style == ChartStyle.donut || style == ChartStyle.pie) &&
                value <= 0)) {
          throw const FormatException(
            'Use valid numbers. Pie and donut values must be positive.',
          );
        }
        items.add(VisualItem(label, value: value));
      }
    }
    return VisualBlock(
      kind: kind,
      title: title.trim(),
      items: items,
      style: style,
    );
  }

  String get input => items
      .map(
        (i) => kind == VisualKind.mindmap
            ? '${'  ' * i.depth}${i.label}'
            : '${i.label}; ${i.value}',
      )
      .join('\n');

  String get json => jsonEncode({
    'version': 1,
    'kind': kind.name,
    'title': title,
    'style': style.name,
    'items': [
      for (final i in items)
        {'label': i.label, 'depth': i.depth, 'value': i.value},
    ],
  });
  String get markdown => '```$fence\n$json\n```';

  static VisualBlock? parse(String source) {
    try {
      final j = jsonDecode(source) as Map<String, dynamic>;
      if (j['version'] != 1) return null;
      final kind = VisualKind.values.byName(j['kind'] as String);
      final style = ChartStyle.values.byName(j['style'] as String);
      final items = (j['items'] as List).cast<Map<String, dynamic>>();
      if (items.isEmpty || items.length > 24) return null;
      if (kind == VisualKind.mindmap &&
          items.any(
            (i) =>
                i['depth'] is! int ||
                (i['depth'] as int) < 0 ||
                (i['depth'] as int) > 4,
          )) {
        return null;
      }
      final input = items
          .map(
            (i) => kind == VisualKind.mindmap
                ? '${'  ' * (i['depth'] as int)}${i['label'] as String}'
                : '${i['label'] as String}; ${i['value'] as num}',
          )
          .join('\n');
      return VisualBlock.fromInput(
        kind: kind,
        title: j['title'] as String,
        input: input,
        style: style,
      );
    } catch (_) {
      return null;
    }
  }
}
