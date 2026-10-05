import 'package:markdown/markdown.dart' as md;

/// Portable, restricted HTML spans; no arbitrary HTML or executable attributes.
final coloredTextPattern = RegExp(
  r'<span style="color:\s*#([0-9a-fA-F]{6});?">([\s\S]*?)</span>',
);
final styledTextPattern = RegExp(r'<span style="([^"<>]+)">([\s\S]*?)</span>');
const textFontFamilies = ['Inter', 'Segoe UI', 'Arial', 'Georgia', 'Consolas'];

Map<String, String>? parseTextStyle(String source) {
  final result = <String, String>{};
  for (final part in source.split(';')) {
    if (part.trim().isEmpty) continue;
    final split = part.indexOf(':');
    if (split < 0) return null;
    final key = part.substring(0, split).trim();
    final value = part.substring(split + 1).trim();
    if (result.containsKey(key)) return null;
    switch (key) {
      case 'color':
        if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return null;
      case 'font-size':
        if (!value.endsWith('pt')) return null;
        final size = double.tryParse(value.substring(0, value.length - 2));
        if (size == null || size < 8 || size > 48) return null;
      case 'font-family':
        if (!textFontFamilies.contains(value)) return null;
      default:
        return null;
    }
    result[key] = value;
  }
  return result.isEmpty ? null : result;
}

String styledText(String content, Map<String, String> styles) {
  if (styles.isEmpty) return content;
  final source = [
    'color',
    'font-size',
    'font-family',
  ].where(styles.containsKey).map((key) => '$key: ${styles[key]};').join(' ');
  return '<span style="$source">$content</span>';
}

class ColoredTextSyntax extends md.InlineSyntax {
  ColoredTextSyntax() : super(styledTextPattern.pattern);
  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final styles = parseTextStyle(match[1]!);
    if (styles == null) {
      // Returning false leaves this matched text unconsumed. Partial values
      // are normal while editing, so consume them as literal text instead.
      parser.addNode(md.Text(match[0]!));
      return true;
    }
    final element = md.Element(
      'markbit-color',
      parser.document.parseInline(match[2]!),
    );
    if (styles['color'] != null) {
      element.attributes['color'] = styles['color']!.substring(1);
    }
    if (styles['font-size'] != null) {
      element.attributes['font-size'] = styles['font-size']!.replaceAll(
        'pt',
        '',
      );
    }
    if (styles['font-family'] != null) {
      element.attributes['font-family'] = styles['font-family']!;
    }
    parser.addNode(element);
    return true;
  }
}

class ColoredTextBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern =>
      RegExp(r'^\s*<span style="(?:color|font-size|font-family):');
  @override
  bool canEndBlock(md.BlockParser parser) => false;
  @override
  md.Node? parse(md.BlockParser parser) =>
      const md.ParagraphSyntax().parse(parser);
}
