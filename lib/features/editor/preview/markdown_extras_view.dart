import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/markdown_extras.dart';
import '../../dialogs/dialogs.dart';

/// `$x$` and one-line `$$x$$` become `markbit-math` elements.
class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(inlineMath.pattern, startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final display = match[1] != null;
    parser.addNode(
      md.Element('markbit-math', [md.Text(match[1] ?? match[2]!)])
        ..attributes['display'] = display ? '1' : '0',
    );
    return true;
  }
}

/// Renders inline math as a widget span so it flows with the paragraph.
class MathInlineBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent;
    final display = element.attributes['display'] == '1';
    final style = parentStyle ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: display ? 4 : 1),
              child: Math.tex(
                tex,
                mathStyle: display ? MathStyle.display : MathStyle.text,
                textStyle: style.copyWith(
                  fontSize: (style.fontSize ?? 15) * 1.05,
                ),
                onErrorFallback: (error) =>
                    _MathError(source: '\$$tex\$', message: error.message),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ```math block or a `$$` block: display math, centered and scrollable.
class MathBlockView extends StatelessWidget {
  const MathBlockView({super.key, required this.tex});
  final String tex;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lines = tex.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Tooltip(
        message: context.tr('Double-click to copy the LaTeX source'),
        waitDuration: const Duration(seconds: 1),
        child: GestureDetector(
          onDoubleTap: () {
            Clipboard.setData(ClipboardData(text: lines));
            showToast(context, context.tr('Copied to clipboard'));
          },
          // Centered when it fits, scrollable when the formula is wider.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Center(
                  child: Math.tex(
                    lines,
                    mathStyle: MathStyle.display,
                    textStyle: TextStyle(color: p.text, fontSize: 17),
                    onErrorFallback: (error) =>
                        _MathError(source: lines, message: error.message),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MathError extends StatelessWidget {
  const _MathError({required this.source, required this.message});
  final String source;
  final String message;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: message,
      child: Text(source, style: AppTheme.mono(size: 12.5, color: p.danger)),
    );
  }
}

/// `[^label]` references with a known definition become superscript numbers.
class FootnoteRefSyntax extends md.InlineSyntax {
  FootnoteRefSyntax(this.numbers)
    : super(
        r'\[\^(' + numbers.keys.map(RegExp.escape).join('|') + r')\]',
        startCharacter: 0x5B,
      );

  final Map<String, int> numbers;

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element('markbit-fnref', [md.Text('${numbers[match[1]]}')]),
    );
    return true;
  }
}

class FootnoteRefBuilder extends MarkdownElementBuilder {
  FootnoteRefBuilder(this.onTap);
  final ValueChanged<int> onTap;

  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final p = context.palette;
    final n = int.tryParse(element.textContent) ?? 0;
    final size = (parentStyle?.fontSize ?? 15) * .72;
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onTap(n),
                child: Padding(
                  padding: const EdgeInsets.only(left: 1, right: 2),
                  child: Text(
                    '$n',
                    style: TextStyle(
                      color: p.accent,
                      fontSize: size,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The numbered footnotes at the end of the preview.
class FootnotesSection extends StatelessWidget {
  const FootnotesSection({
    super.key,
    required this.footnotes,
    required this.buildText,
    required this.onBack,
  });

  final List<Footnote> footnotes;
  final Widget Function(String text) buildText;
  final ValueChanged<Footnote> onBack;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(color: p.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.sm),
            child: Text(
              context.tr('Footnotes'),
              style: TextStyle(
                color: p.textMuted,
                fontSize: Fs.small,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
              ),
            ),
          ),
          for (final f in footnotes)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${f.number}.',
                      style: TextStyle(
                        color: p.accent,
                        fontWeight: FontWeight.w700,
                        height: 1.65,
                      ),
                    ),
                  ),
                  Expanded(child: buildText(f.text)),
                  if (f.refLine >= 0)
                    IconButton(
                      tooltip: context.tr('Back to the reference'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: Icon(
                        Icons.keyboard_return_rounded,
                        color: p.textFaint,
                      ),
                      onPressed: () => onBack(f),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
