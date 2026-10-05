import 'package:flutter/material.dart';

import '../../domain/search_query.dart';
import '../theme/app_palette.dart';

/// Text with the parts that match a search marked. [words] are folded search
/// words (see [foldSearch]); without matches this is a plain [Text].
class HighlightedText extends StatelessWidget {
  const HighlightedText(
    this.text, {
    super.key,
    required this.words,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  final String text;
  final Iterable<String> words;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final ranges = highlightRanges(text, words);
    if (ranges.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    final p = context.palette;
    final mark = TextStyle(
      backgroundColor: p.accent.withValues(alpha: p.isDark ? .28 : .18),
      color: p.text,
      fontWeight: FontWeight.w600,
    );
    final spans = <TextSpan>[];
    var at = 0;
    for (final (start, end) in ranges) {
      if (start > at) spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(TextSpan(text: text.substring(start, end), style: mark));
      at = end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
