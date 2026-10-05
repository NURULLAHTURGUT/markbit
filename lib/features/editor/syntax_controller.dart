import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import 'highlight/highlighter.dart';
import '../../domain/colored_text.dart';

/// A [TextEditingController] that paints syntax highlighting directly into
/// the text field. [language] `null` means markdown (with highlighted fenced
/// code blocks); otherwise the text is treated as source code.
class SyntaxController extends TextEditingController {
  SyntaxController({super.text, required AppPalette palette, String? language})
    : _palette = palette,
      _language = language;

  AppPalette _palette;
  String? _language;

  String? _cachedText;
  TextStyle? _cachedStyle;
  TextSpan? _cachedSpan;
  String? _cachedPaletteId;
  String? _cachedLanguage;
  String _searchQuery = '';
  bool _searchCase = false;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  set searchQuery(String value) {
    if (_disposed) return;
    if (_searchQuery != value) {
      _searchQuery = value;
      notifyListeners();
    }
  }

  set searchCaseSensitive(bool value) {
    if (_disposed) return;
    if (_searchCase != value) {
      _searchCase = value;
      notifyListeners();
    }
  }

  AppPalette get palette => _palette;
  String? get language => _language;

  set palette(AppPalette value) {
    if (value.id == _palette.id) return;
    _palette = value;
    notifyListeners();
  }

  set language(String? value) {
    if (value == _language) return;
    _language = value;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // Keep the platform's composing underline for IME input.
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final base = style ?? const TextStyle();
    if (_searchQuery.isNotEmpty) {
      final spans = <TextSpan>[];
      var end = 0;
      for (final match in RegExp(
        RegExp.escape(_searchQuery),
        caseSensitive: _searchCase,
      ).allMatches(text)) {
        spans.add(TextSpan(text: text.substring(end, match.start)));
        spans.add(
          TextSpan(
            text: text.substring(match.start, match.end),
            style: const TextStyle(
              backgroundColor: Color(0xffffd54f),
              color: Colors.black,
            ),
          ),
        );
        end = match.end;
      }
      spans.add(TextSpan(text: text.substring(end)));
      return TextSpan(style: base, children: spans);
    }
    if (_cachedSpan != null &&
        _cachedText == text &&
        _cachedStyle == base &&
        _cachedPaletteId == _palette.id &&
        _cachedLanguage == _language) {
      return _cachedSpan!;
    }
    // Large documents remain editable without building a span per token.
    if (text.length > 100000) return TextSpan(text: text, style: base);
    final tokens = _language == null
        ? tokenizeMarkdown(text)
        : tokenizeCode(text, _language);
    final span = _language == null
        ? _applyCodeFont(
            _applyTextColors(
              buildHighlightedSpan(text, tokens, base, _palette),
              base,
            ),
            base,
          )
        : buildHighlightedSpan(text, tokens, base, _palette);
    _cachedText = text;
    _cachedStyle = base;
    _cachedPaletteId = _palette.id;
    _cachedLanguage = _language;
    return _cachedSpan = span;
  }

  /// With a proportional base font, code (fences and inline code) is drawn
  /// in the monospace font.
  TextSpan _applyCodeFont(TextSpan span, TextStyle base) {
    if (base.fontFamily == null ||
        base.fontFamily == AppTheme.monoFallback.first) {
      return span;
    }
    final ranges = markdownCodeRanges(text);
    if (ranges.isEmpty) return span;
    return _restyle(span, base, [
      for (final r in ranges)
        (
          start: r.$1,
          end: r.$2,
          apply: (TextStyle s) => s.copyWith(
            fontFamily: AppTheme.monoFallback.first,
            fontFamilyFallback: AppTheme.monoFallback.sublist(1),
          ),
        ),
    ]);
  }

  TextSpan _applyTextColors(TextSpan span, TextStyle base) {
    final matches = styledTextPattern
        .allMatches(text)
        .where((m) => parseTextStyle(m[1]!)?['color'] != null)
        .toList();
    if (matches.isEmpty) return span;
    return _restyle(span, base, [
      for (final m in matches)
        (
          start: m.start + m[0]!.indexOf('>') + 1,
          end: m.end - '</span>'.length,
          apply: (TextStyle s) => s.copyWith(
            color: Color(
              int.parse(
                'FF${parseTextStyle(m[1]!)!['color']!.substring(1)}',
                radix: 16,
              ),
            ),
          ),
        ),
    ]);
  }

  /// Flattens [span] and applies each range's style change to the text it
  /// covers. Ranges are sorted and do not overlap.
  TextSpan _restyle(
    TextSpan span,
    TextStyle base,
    List<({int start, int end, TextStyle Function(TextStyle) apply})> ranges,
  ) {
    final leaves = <TextSpan>[];
    var offset = 0;
    void visit(TextSpan current, TextStyle inherited) {
      final style = inherited.merge(current.style);
      if (current.text case final value?) {
        var start = 0;
        for (final range in ranges) {
          final left = (range.start - offset).clamp(0, value.length);
          final right = (range.end - offset).clamp(0, value.length);
          if (right <= left) continue;
          if (left > start) {
            leaves.add(
              TextSpan(text: value.substring(start, left), style: style),
            );
          }
          leaves.add(
            TextSpan(
              text: value.substring(left, right),
              style: range.apply(style),
            ),
          );
          start = right;
        }
        if (start < value.length) {
          leaves.add(TextSpan(text: value.substring(start), style: style));
        }
        offset += value.length;
      }
      for (final child in current.children ?? <InlineSpan>[]) {
        if (child is TextSpan) visit(child, style);
      }
    }

    visit(span, base);
    return TextSpan(style: base, children: leaves);
  }
}
