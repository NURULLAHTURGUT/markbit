import '../../core/l10n/app_strings.dart';
import '../markdown_utils.dart';
import '../visual_block.dart';

/// Converts only losslessly representable diagrams. Unknown syntax stays intact.
VisualBlock? aiVisual(String info, String code) {
  if (info == VisualBlock.fence) return VisualBlock.parse(code);
  if (info.toLowerCase() != 'mermaid') return null;
  try {
    final lines = code
        .replaceAll('\r', '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('%%'))
        .toList();
    if (lines.isEmpty) return null;
    final type = lines.removeAt(0).trim();
    if (type == 'mindmap') {
      final stack = <int>[];
      final entries = <String>[];
      for (final line in lines) {
        if (line.contains('\t') ||
            RegExp(r'^(::|icon|class)').hasMatch(line.trim())) {
          return null;
        }
        final indent = line.length - line.trimLeft().length;
        while (stack.isNotEmpty && indent <= stack.last) {
          stack.removeLast();
        }
        final depth = stack.length;
        stack.add(indent);
        var label = line.trim();
        final shaped = RegExp(
          r'^(?:[\w-]+)?(?:\(\((.+)\)\)|\((.+)\)|\[\[(.+)\]\]|\[(.+)\]|\{\{(.+)\}\})$',
        ).firstMatch(label);
        if (shaped != null) {
          label = [
            for (var i = 1; i <= 5; i++) shaped.group(i),
          ].whereType<String>().first;
        }
        label = _unquote(label);
        entries.add('${'  ' * depth}$label');
      }
      return VisualBlock.fromInput(
        kind: VisualKind.mindmap,
        title: entries.isEmpty ? trs('Mind map') : entries.first.trim(),
        input: entries.join('\n'),
      );
    }
    if (type == 'pie' || type == 'pie showData') {
      var title = trs('Donut chart');
      final entries = <String>[];
      for (final line in lines) {
        final t = line.trim();
        if (t.startsWith('title ')) {
          title = _unquote(t.substring(6));
          continue;
        }
        final match = RegExp(r'^"(.+)"\s*:\s*([+-]?[\d.]+)$').firstMatch(t);
        if (match == null) return null;
        entries.add('${match.group(1)}; ${match.group(2)}');
      }
      return VisualBlock.fromInput(
        kind: VisualKind.chart,
        title: title,
        input: entries.join('\n'),
        style: ChartStyle.donut,
      );
    }
    if (type == 'xychart-beta' || type == 'xychart-beta vertical') {
      var title = trs('Chart');
      List<String>? labels;
      List<double>? values;
      var style = ChartStyle.bar;
      for (final line in lines) {
        final t = line.trim();
        if (t.startsWith('title ')) {
          title = _unquote(t.substring(6));
          continue;
        }
        if (t.startsWith('y-axis ')) continue;
        final x = RegExp(r'^x-axis\s+(?:"[^"]*"\s+)?\[(.*)\]$').firstMatch(t);
        if (x != null) {
          labels = RegExp(r'"([^"]*)"|([^,]+)')
              .allMatches(x.group(1)!)
              .map((m) => (m.group(1) ?? m.group(2)!).trim())
              .toList();
          continue;
        }
        final data = RegExp(r'^(bar|line)\s+\[(.*)\]$').firstMatch(t);
        if (data == null || values != null) {
          return null; // Multiple series are not representable.
        }
        style = data.group(1) == 'line' ? ChartStyle.line : ChartStyle.bar;
        values = data
            .group(2)!
            .split(',')
            .map((s) => double.parse(s.trim()))
            .toList();
      }
      if (labels == null || values == null || labels.length != values.length) {
        return null;
      }
      return VisualBlock.fromInput(
        kind: VisualKind.chart,
        title: title,
        style: style,
        input: [
          for (var i = 0; i < labels.length; i++) '${labels[i]}; ${values[i]}',
        ].join('\n'),
      );
    }
  } catch (_) {
    /* Preserve unsupported or malformed input as source. */
  }
  return null;
}

String _unquote(String s) =>
    s.length >= 2 && s.startsWith('"') && s.endsWith('"')
    ? s.substring(1, s.length - 1)
    : s;

String prepareAiNote(String text) {
  final lines = text.split('\n');
  for (final segment in splitSegments(text).reversed.whereType<CodeSegment>()) {
    final visual = aiVisual(segment.info, segment.code);
    final closing = lines[segment.endLine].trim();
    if (visual == null || !RegExp(r'^(`{3,}|~{3,})$').hasMatch(closing)) {
      continue;
    }
    lines.replaceRange(
      segment.startLine,
      segment.endLine + 1,
      visual.markdown.split('\n'),
    );
  }
  return lines.join('\n');
}

const aiVisualInstructions =
    '''When asked for a mind map or chart, use a markbit-visual fenced JSON block:
{"version":1,"kind":"mindmap","title":"Title","style":"bar","items":[{"label":"Root","depth":0,"value":0},{"label":"Child","depth":1,"value":0}]}
For charts use kind="chart", style="bar", "line" or "donut", depth=0 and numeric value per item.
Use 1-24 items, title up to 120 characters, labels up to 80 characters, mindmap depths 0-4 (no skipped levels), and positive donut values. Use multiple blocks for larger diagrams. Preserve the user's data. These blocks render as editable visuals in the notebook.''';
