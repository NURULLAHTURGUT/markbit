import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/widgets/bare_decoration.dart';
import 'markdown_commands.dart';
import 'table_commands.dart';
import '../../application/shortcuts.dart';
import 'markdown_completion.dart';
import '../../core/theme/tokens.dart';

/// Layout information the outside world (outline panel, status bar) needs.
class EditorMetrics {
  List<int> visualLines = const [1];
  double lineHeight = 22;
  double topPadding = 16;
  List<int> _prefix = const [0];
  List<int>? _prefixFor;

  double offsetOfLine(int line) {
    if (!identical(_prefixFor, visualLines)) {
      _prefix = [0];
      for (final count in visualLines) {
        _prefix.add(_prefix.last + count);
      }
      _prefixFor = visualLines;
    }
    return topPadding + _prefix[line.clamp(0, visualLines.length)] * lineHeight;
  }
}

/// Plain-text editor with line numbers, current-line highlight, smart Enter
/// and Tab handling. Works for markdown (wrapped prose) and source code.
class CodeTextEditor extends StatefulWidget {
  const CodeTextEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.metrics,
    required this.fontSize,
    required this.showLineNumbers,
    required this.isCode,
    this.onChanged,
    this.onRun,
    this.shortcuts = const {},
    this.readOnly = false,
    this.hint = '',
    this.onCaretRectChanged,
    this.markdownSuggestions = true,
    this.completionNoteTitles,
    this.completionImageUris,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final EditorMetrics metrics;
  final double fontSize;
  final bool showLineNumbers;
  final bool isCode;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onRun;

  /// Rebound editor shortcuts; missing actions use their defaults.
  final Map<AppShortcut, KeyCombo> shortcuts;
  final bool readOnly;
  final String hint;
  final ValueChanged<Rect>? onCaretRectChanged;
  final bool markdownSuggestions;
  final Iterable<String> Function()? completionNoteTitles, completionImageUris;

  @override
  State<CodeTextEditor> createState() => _CodeTextEditorState();
}

class _CodeTextEditorState extends State<CodeTextEditor> {
  final _fieldKey = GlobalKey();
  bool _caretScheduled = false;
  final _completionEngine = MarkdownCompletionEngine();
  final _ghostAnchor = ValueNotifier<(Rect, double)?>(null);
  Timer? _completionTimer;
  List<MarkdownCompletion> _suggestions = [];
  TextEditingValue? _suggestedFor, _dismissed;
  late TextEditingValue _previousValue;
  MarkdownSnippetSession? _snippet;
  bool _applyingCompletion = false;
  bool get _completionEnabled =>
      widget.markdownSuggestions && !widget.isCode && !widget.readOnly;
  bool get _ghostVisible {
    final anchor = _ghostAnchor.value;
    final size = context.size;
    return anchor != null &&
        size != null &&
        anchor.$1.top >= 0 &&
        anchor.$1.bottom <= size.height &&
        anchor.$2 - anchor.$1.left > 4;
  }

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_scheduleCaret);
    _previousValue = widget.controller.value;
    widget.controller.addListener(_onCompletionChanged);
    widget.focusNode.addListener(_onCompletionFocus);
    _refreshCompletion();
  }

  @override
  void didUpdateWidget(CodeTextEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onCompletionChanged);
      widget.controller.addListener(_onCompletionChanged);
      _previousValue = widget.controller.value;
      _snippet = null;
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onCompletionFocus);
      widget.focusNode.addListener(_onCompletionFocus);
    }
    if (oldWidget.markdownSuggestions != widget.markdownSuggestions ||
        oldWidget.isCode != widget.isCode ||
        oldWidget.readOnly != widget.readOnly ||
        oldWidget.controller != widget.controller) {
      if (!_completionEnabled) _snippet = null;
      _refreshCompletion();
    }
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_scheduleCaret);
      widget.scrollController.addListener(_scheduleCaret);
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_scheduleCaret);
    widget.controller.removeListener(_onCompletionChanged);
    widget.focusNode.removeListener(_onCompletionFocus);
    _completionTimer?.cancel();
    _ghostAnchor.dispose();
    super.dispose();
  }

  void _scheduleCaret() {
    if (_caretScheduled ||
        (widget.onCaretRectChanged == null && _suggestions.isEmpty)) {
      return;
    }
    _caretScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _caretScheduled = false;
      if (!mounted || !widget.controller.selection.isValid) return;
      RenderEditable? editable;
      void find(RenderObject object) {
        if (object is RenderEditable) {
          editable = object;
        } else {
          object.visitChildren(find);
        }
      }

      final field = _fieldKey.currentContext?.findRenderObject();
      final viewport = context.findRenderObject();
      if (field == null || viewport is! RenderBox) return;
      find(field);
      final render = editable;
      if (render == null || !render.hasSize) return;
      final caret = render.getLocalRectForCaret(
        widget.controller.selection.extent,
      );
      final top = viewport.globalToLocal(render.localToGlobal(caret.topLeft));
      widget.onCaretRectChanged?.call(top & caret.size);
      if (_suggestions.isNotEmpty) {
        final right = viewport
            .globalToLocal(render.localToGlobal(Offset(render.size.width, 0)))
            .dx;
        _ghostAnchor.value = (top & caret.size, right);
      }
    });
  }

  void _onCompletionFocus() {
    if (!widget.focusNode.hasFocus) _snippet = null;
    _refreshCompletion();
  }

  void _onCompletionChanged() {
    final next = widget.controller.value;
    if (!_applyingCompletion &&
        _snippet != null &&
        !_snippet!.update(_previousValue, next)) {
      _snippet = null;
    }
    _previousValue = next;
    _refreshCompletion();
  }

  void _refreshCompletion() {
    _completionTimer?.cancel();
    if (_suggestions.isNotEmpty && mounted) setState(() => _suggestions = []);
    if (!_completionEnabled || !widget.focusNode.hasFocus) return;
    final value = widget.controller.value;
    if (value == _dismissed || !value.selection.isCollapsed) return;
    _completionTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted ||
          !_completionEnabled ||
          !widget.focusNode.hasFocus ||
          widget.controller.value != value) {
        return;
      }
      final suggestions = _proposals(value);
      if (suggestions.isEmpty) return;
      _ghostAnchor.value = null;
      setState(() {
        _suggestions = suggestions;
        _suggestedFor = value;
      });
      _scheduleCaret();
    });
  }

  List<MarkdownCompletion> _proposals(TextEditingValue value) =>
      _completionEngine.suggest(
        value,
        noteTitles: widget.completionNoteTitles,
        imageUris: widget.completionImageUris,
        translate: (s) => context.tr(s),
      );

  void _acceptCompletion(
    MarkdownCompletion proposal,
    TextEditingValue expected,
  ) {
    final c = widget.controller;
    if (!_completionEnabled || c.value != expected) return;
    final start = proposal.range.start;
    final text = c.text.replaceRange(
      start,
      proposal.range.end,
      proposal.insertText,
    );
    final stops = proposal.stops
        .where((s) => s.end > expected.selection.end - start || s.isCollapsed)
        .map((s) => TextRange(start: s.start + start, end: s.end + start))
        .toList();
    _snippet = stops.isEmpty
        ? null
        : MarkdownSnippetSession(stops, start + proposal.insertText.length);
    _applyingCompletion = true;
    c.value = TextEditingValue(
      text: text,
      selection:
          _snippet?.selection ??
          TextSelection.collapsed(offset: start + proposal.insertText.length),
    );
    _applyingCompletion = false;
    widget.focusNode.requestFocus();
    widget.onChanged?.call(c.text);
    _completionTimer?.cancel();
  }

  void _advanceSnippet(bool backwards) {
    final snippet = _snippet!;
    snippet.index = backwards
        ? math.max(0, snippet.index - 1)
        : snippet.index + 1;
    _applyingCompletion = true;
    if (snippet.index >= snippet.ranges.length) {
      _snippet = null;
      widget.controller.selection = TextSelection.collapsed(
        offset: snippet.end,
      );
    } else {
      widget.controller.selection = snippet.selection;
    }
    _applyingCompletion = false;
  }

  Future<void> _showCompletions() async {
    final snapshot = widget.controller.value;
    final proposals = _proposals(snapshot);
    if (proposals.isEmpty) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final anchor = _ghostAnchor.value?.$1 ?? const Rect.fromLTWH(20, 20, 1, 22);
    final box = context.findRenderObject()! as RenderBox;
    final top = overlay.globalToLocal(box.localToGlobal(anchor.bottomLeft));
    final p = context.palette;
    final chosen = await showMenu<MarkdownCompletion>(
      context: context,
      color: p.surface.withValues(alpha: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Rad.lg),
        side: BorderSide(color: p.border),
      ),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(top.dx, top.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final proposal in proposals)
          PopupMenuItem(
            value: proposal,
            child: Text(
              proposal.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
    if (!mounted) return;
    if (chosen != null) {
      _acceptCompletion(chosen, snapshot);
    } else {
      widget.focusNode.requestFocus();
    }
  }

  static const double _lineHeightFactor = 1.6;
  static const double _hPadLeft = 12;
  static const double _hPadRight = 28;
  static const double _topPad = 16;

  String? _cacheText;
  double? _cacheWidth;
  double? _cacheFont;
  String? _cacheFamily;
  double? _wideW;
  double? _wideWFont;
  List<int> _counts = const [1];
  double? _charW;
  double? _charWFont;
  final Map<String, int> _lineMeasurements = {};
  List<int> _lineStarts = const [0];

  int _lineAt(int offset) {
    var lo = 0;
    var hi = _lineStarts.length;
    while (lo + 1 < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  double _charWidth(TextStyle style) {
    if (_charW != null && _charWFont == style.fontSize) return _charW!;
    final tp = TextPainter(
      text: TextSpan(text: 'M' * 24, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    _charW = tp.width / 24;
    _charWFont = style.fontSize;
    tp.dispose();
    return _charW!;
  }

  static bool _simple(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c >= 128 || c == 9) return false;
    }
    return true;
  }

  /// Width of the widest common glyph (bold "W") in a proportional font;
  /// an ASCII line shorter than width / this cannot wrap.
  double _widestGlyph(TextStyle style) {
    if (_wideW != null && _wideWFont == style.fontSize) return _wideW!;
    final tp = TextPainter(
      text: TextSpan(
        text: 'W' * 24,
        style: style.copyWith(fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _wideW = math.max(tp.width / 24, _charWidth(_monoOf(style))) * 1.02;
    _wideWFont = style.fontSize;
    tp.dispose();
    return _wideW!;
  }

  static TextStyle _monoOf(TextStyle style) => style.copyWith(
    fontFamily: AppTheme.monoFallback.first,
    fontFamilyFallback: AppTheme.monoFallback.sublist(1),
  );

  /// Splits [span] into one list of styled runs per source line, so wrapped
  /// line counts can be measured with the fonts and weights actually drawn.
  static List<List<TextSpan>> _spanLines(TextSpan span, TextStyle base) {
    final lines = <List<TextSpan>>[<TextSpan>[]];
    void visit(TextSpan current, TextStyle inherited) {
      final style = inherited.merge(current.style);
      final value = current.text;
      if (value != null && value.isNotEmpty) {
        var start = 0;
        while (true) {
          final nl = value.indexOf('\n', start);
          final end = nl == -1 ? value.length : nl;
          if (end > start) {
            lines.last.add(
              TextSpan(text: value.substring(start, end), style: style),
            );
          }
          if (nl == -1) break;
          lines.add(<TextSpan>[]);
          start = nl + 1;
        }
      }
      for (final child in current.children ?? const <InlineSpan>[]) {
        if (child is TextSpan) visit(child, style);
      }
    }

    visit(span, base);
    return lines;
  }

  List<int> _visualCounts(
    String text,
    double width,
    TextStyle style,
    StrutStyle strut,
  ) {
    final family = style.fontFamily;
    if (_cacheText == text &&
        _cacheWidth == width &&
        _cacheFont == style.fontSize &&
        _cacheFamily == family) {
      return _counts;
    }
    if (_cacheWidth != width ||
        _cacheFont != style.fontSize ||
        _cacheFamily != family) {
      _lineMeasurements.clear();
    }
    final monospace = family == AppTheme.monoFallback.first;
    final cols = math.max(
      1,
      (width / (monospace ? _charWidth(style) : _widestGlyph(style))).floor(),
    );
    final lines = text.split('\n');
    final counts = List<int>.filled(lines.length, 1);
    final starts = <int>[];
    // Proportional text mixes fonts (monospace code) and weights (bold,
    // headings), so lines are measured from the highlighted span itself.
    List<List<TextSpan>>? styled;
    var offset = 0;
    TextPainter? tp;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      starts.add(offset);
      offset += l.length + 1;
      if (l.length <= cols && _simple(l)) continue;
      List<TextSpan>? runs;
      var key = l;
      if (!monospace) {
        styled ??= _spanLines(
          widget.controller.buildTextSpan(
            context: context,
            style: style,
            withComposing: false,
          ),
          style,
        );
        if (styled.length == lines.length) {
          runs = styled[i];
          key =
              '$l\u0000${runs.map((r) => '${r.text!.length}:${r.style.hashCode}').join(',')}';
        }
      }
      final cached = _lineMeasurements[key];
      if (cached != null) {
        counts[i] = cached;
        continue;
      }
      tp ??= TextPainter(textDirection: TextDirection.ltr, strutStyle: strut);
      tp.text = runs == null || runs.isEmpty
          ? TextSpan(text: l.isEmpty ? ' ' : l, style: style)
          : TextSpan(style: style, children: runs);
      tp.layout(maxWidth: width);
      counts[i] = math.max(1, tp.computeLineMetrics().length);
      if (_lineMeasurements.length >= 4000) _lineMeasurements.clear();
      _lineMeasurements[key] = counts[i];
    }
    tp?.dispose();
    _cacheText = text;
    _cacheWidth = width;
    _cacheFont = style.fontSize;
    _cacheFamily = family;
    _lineStarts = starts;
    return _counts = counts;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.readOnly) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final kb = HardwareKeyboard.instance;
    final mod = kb.isControlPressed || kb.isMetaPressed;
    final key = event.logicalKey;
    final c = widget.controller;
    final unit = widget.isCode ? '    ' : '  ';
    if (c.value.composing.isValid && !c.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }

    if (_completionEnabled &&
        key == LogicalKeyboardKey.escape &&
        (_suggestions.isNotEmpty ||
            _snippet != null ||
            _completionTimer?.isActive == true)) {
      _completionTimer?.cancel();
      _dismissed = c.value;
      _snippet = null;
      setState(() => _suggestions = []);
      return KeyEventResult.handled;
    }
    bool pressed(AppShortcut action) =>
        (widget.shortcuts[action] ?? action.defaultCombo).accepts(event, kb);
    if (_completionEnabled && pressed(AppShortcut.suggestions)) {
      _showCompletions();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab && !mod) {
      if (_completionEnabled && _snippet != null) {
        _advanceSnippet(kb.isShiftPressed);
        return KeyEventResult.handled;
      }
      if (_completionEnabled &&
          !kb.isShiftPressed &&
          _suggestions.isNotEmpty &&
          _ghostVisible &&
          c.value == _suggestedFor) {
        _acceptCompletion(_suggestions.first, _suggestedFor!);
        return KeyEventResult.handled;
      }
      // In a Markdown table Tab moves between cells (and tidies the table).
      if (!widget.isCode &&
          c.selection.isCollapsed &&
          TableCommands.moveCell(c, backwards: kb.isShiftPressed)) {
        widget.onChanged?.call(c.text);
        return KeyEventResult.handled;
      }
      MarkdownCommands.indent(c, outdent: kb.isShiftPressed, unit: unit);
      widget.onChanged?.call(c.text);
      return KeyEventResult.handled;
    }
    if (pressed(AppShortcut.runCode)) {
      widget.onRun?.call();
      return KeyEventResult.handled;
    }
    if (!widget.isCode) {
      if (pressed(AppShortcut.bold)) {
        MarkdownCommands.bold(c);
      } else if (pressed(AppShortcut.italic)) {
        MarkdownCommands.italic(c);
      } else if (pressed(AppShortcut.inlineCode)) {
        MarkdownCommands.inlineCode(c);
      } else {
        return KeyEventResult.ignored;
      }
      widget.onChanged?.call(c.text);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fs = widget.fontSize;
    // Explicit letter spacing: TextField otherwise inherits bodyLarge's 0.5,
    // which spreads the text and is not part of the wrap measurements.
    final mono = AppTheme.mono(
      size: fs,
      color: p.text,
      height: _lineHeightFactor,
    ).copyWith(letterSpacing: 0);
    // Markdown prose reads better in the UI font; the highlighter switches
    // fenced and inline code back to monospace. Source files stay monospace.
    final style = widget.isCode
        ? mono
        : TextStyle(
            fontFamily: AppTheme.uiFont,
            fontSize: fs,
            height: _lineHeightFactor,
            letterSpacing: 0,
            color: p.text,
          );
    final strut = StrutStyle(
      fontFamily: AppTheme.monoFallback.first,
      fontFamilyFallback: AppTheme.monoFallback.sublist(1),
      fontSize: fs,
      height: _lineHeightFactor,
      forceStrutHeight: true,
    );
    final lineHeight = fs * _lineHeightFactor;

    return LayoutBuilder(
      builder: (context, cons) {
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            _scheduleCaret();
            final text = widget.controller.text;
            final lineCount = _cacheText == text
                ? _counts.length
                : '\n'.allMatches(text).length + 1;
            final digits = math.max(2, lineCount.toString().length);
            final gutterW = widget.showLineNumbers
                ? digits * _charWidth(mono) + 26
                : 0.0;
            final textWidth = math.max(
              40.0,
              cons.maxWidth - gutterW - _hPadLeft - _hPadRight,
            );
            final counts = _visualCounts(text, textWidth, style, strut);

            widget.metrics
              ..visualLines = counts
              ..lineHeight = lineHeight
              ..topPadding = _topPad;

            final sel = widget.controller.selection;
            final caretOffset = sel.isValid
                ? sel.extentOffset.clamp(0, text.length)
                : 0;
            final caretLine = _lineAt(caretOffset);

            final totalVisual = counts.fold<int>(0, (a, b) => a + b);
            final contentH = totalVisual * lineHeight;
            final bandTop = widget.metrics.offsetOfLine(caretLine);
            final bandH =
                counts[math.min(caretLine, counts.length - 1)] * lineHeight;
            final filler = math.max(
              160.0,
              cons.maxHeight - contentH - _topPad * 2,
            );

            final editor = ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: Scrollbar(
                thumbVisibility: true,
                notificationPredicate: (n) => n.depth == 0,
                controller: widget.scrollController,
                child: SingleChildScrollView(
                  controller: widget.scrollController,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Stack(
                        children: [
                          if (widget.focusNode.hasFocus)
                            Positioned(
                              top: bandTop,
                              left: 0,
                              right: 0,
                              height: bandH,
                              child: ColoredBox(
                                color: p.accent.withValues(alpha: 0.08),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(top: _topPad),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.showLineNumbers)
                                  ExcludeSemantics(
                                    child: SizedBox(
                                      width: gutterW,
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 14,
                                        ),
                                        child: _Gutter(
                                          counts: counts,
                                          fieldKey: _fieldKey,
                                          lineStarts: _lineStarts,
                                          source: text,
                                          caretLine: caretLine,
                                          style: mono.copyWith(
                                            color: p.textFaint,
                                          ),
                                          activeColor: p.textMuted,
                                          strut: strut,
                                          metrics: widget.metrics,
                                          scrollController:
                                              widget.scrollController,
                                          viewportHeight: cons.maxHeight,
                                        ),
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      left: widget.showLineNumbers
                                          ? 0
                                          : _hPadLeft + 8,
                                      right: _hPadRight,
                                    ),
                                    child: Focus(
                                      canRequestFocus: false,
                                      skipTraversal: true,
                                      onKeyEvent: _onKey,
                                      child: TextField(
                                        key: _fieldKey,
                                        controller: widget.controller,
                                        focusNode: widget.focusNode,
                                        maxLines: null,
                                        readOnly: widget.readOnly,
                                        style: style,
                                        strutStyle: strut,
                                        cursorColor: p.accent,
                                        cursorWidth: 2,
                                        keyboardType: TextInputType.multiline,
                                        textCapitalization:
                                            TextCapitalization.none,
                                        autocorrect: false,
                                        enableSuggestions: false,
                                        smartDashesType:
                                            SmartDashesType.disabled,
                                        smartQuotesType:
                                            SmartQuotesType.disabled,
                                        inputFormatters: [
                                          SmartEnterFormatter(
                                            isCode: widget.isCode,
                                            indentUnit: widget.isCode
                                                ? '    '
                                                : '  ',
                                          ),
                                        ],
                                        decoration: bareDecoration(
                                          hint: widget.hint,
                                          hintStyle: style.copyWith(
                                            color: p.textFaint,
                                          ),
                                        ),
                                        onChanged: widget.onChanged,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.focusNode.requestFocus();
                          widget.controller.selection = TextSelection.collapsed(
                            offset: widget.controller.text.length,
                          );
                        },
                        child: SizedBox(height: filler),
                      ),
                    ],
                  ),
                ),
              ),
            );
            return Stack(
              children: [
                editor,
                if (_suggestions.isNotEmpty &&
                    widget.controller.value == _suggestedFor)
                  ValueListenableBuilder<(Rect, double)?>(
                    valueListenable: _ghostAnchor,
                    builder: (context, anchor, _) {
                      if (anchor == null ||
                          anchor.$1.top < 0 ||
                          anchor.$1.bottom > cons.maxHeight) {
                        return const SizedBox.shrink();
                      }
                      final rect = anchor.$1;
                      final width = math.max(0.0, anchor.$2 - rect.left - 4);
                      final suffix = _suggestions.first.suffix;
                      return Positioned(
                        key: const ValueKey('markdown-ghost-text'),
                        left: rect.left + 2,
                        top: rect.top,
                        width: width,
                        height: lineHeight + 2,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: Text(
                              '${suffix.split('\n').first}${suffix.contains('\n') ? ' ↵' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: style.copyWith(
                                color: p.textMuted.withValues(alpha: 0.58),
                              ),
                              strutStyle: strut,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _Gutter extends StatelessWidget {
  _Gutter({
    required this.counts,
    required this.fieldKey,
    required this.lineStarts,
    required this.source,
    required this.caretLine,
    required this.style,
    required this.activeColor,
    required this.strut,
    required this.metrics,
    required this.scrollController,
    required this.viewportHeight,
  });

  final List<int> counts;
  final GlobalKey fieldKey;
  final List<int> lineStarts;
  final String source;
  final _paintKey = GlobalKey();
  final int caretLine;
  final TextStyle style;
  final Color activeColor;
  final StrutStyle strut;
  final EditorMetrics metrics;
  final ScrollController scrollController;
  final double viewportHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: metrics.offsetOfLine(counts.length) - metrics.topPadding,
      child: CustomPaint(
        key: _paintKey,
        painter: _GutterPainter(
          metrics: metrics,
          fieldKey: fieldKey,
          paintKey: _paintKey,
          lineStarts: lineStarts,
          source: source,
          caretLine: caretLine,
          style: style,
          activeColor: activeColor,
          strut: strut,
          controller: scrollController,
          viewportHeight: viewportHeight,
        ),
      ),
    );
  }
}

class _GutterPainter extends CustomPainter {
  _GutterPainter({
    required this.metrics,
    required this.fieldKey,
    required this.paintKey,
    required this.lineStarts,
    required this.source,
    required this.caretLine,
    required this.style,
    required this.activeColor,
    required this.controller,
    required this.viewportHeight,
    required this.strut,
  }) : super(repaint: controller);
  final EditorMetrics metrics;
  final GlobalKey fieldKey, paintKey;
  final List<int> lineStarts;
  final String source;
  final int caretLine;
  final TextStyle style;
  final Color activeColor;
  final ScrollController controller;
  final double viewportHeight;
  final StrutStyle strut;
  @override
  void paint(Canvas canvas, Size size) {
    final start = controller.hasClients ? controller.offset : 0.0;
    var lo = 0;
    var hi = metrics.visualLines.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (metrics.offsetOfLine(mid + 1) < start) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    RenderEditable? editable;
    void findEditable(RenderObject object) {
      if (object is RenderEditable) {
        editable = object;
      } else {
        object.visitChildren(findEditable);
      }
    }

    final field = fieldKey.currentContext?.findRenderObject();
    final gutter = paintKey.currentContext?.findRenderObject();
    if (field != null) findEditable(field);
    final render = editable;
    double? caretToGlyph;
    if (render != null && gutter is RenderBox) {
      for (final offset in lineStarts) {
        if (offset >= source.length || source.codeUnitAt(offset) == 10) {
          continue;
        }
        final glyph = render.getRectForComposingRange(
          TextRange(start: offset, end: offset + 1),
        );
        if (glyph != null) {
          caretToGlyph =
              glyph.top -
              render.getLocalRectForCaret(TextPosition(offset: offset)).top;
          break;
        }
      }
    }
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      strutStyle: strut,
    );
    for (var i = lo; i < metrics.visualLines.length; i++) {
      final top = metrics.offsetOfLine(i) - metrics.topPadding;
      if (top > start + viewportHeight + metrics.lineHeight) break;
      painter.text = TextSpan(
        text: '${i + 1}',
        style: i == caretLine ? style.copyWith(color: activeColor) : style,
      );
      painter.layout();
      var actualTop = top;
      if (render != null && gutter is RenderBox && i < lineStarts.length) {
        final offset = lineStarts[i];
        final rect = offset < source.length && source.codeUnitAt(offset) != 10
            ? render.getRectForComposingRange(
                TextRange(start: offset, end: offset + 1),
              )
            : null;
        final glyphTop =
            rect?.top ??
            render.getLocalRectForCaret(TextPosition(offset: offset)).top +
                (caretToGlyph ?? 0);
        final numberBox = painter.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: '${i + 1}'.length),
        );
        if (numberBox.isNotEmpty) {
          actualTop =
              gutter
                  .globalToLocal(render.localToGlobal(Offset(0, glyphTop)))
                  .dy -
              numberBox.first.top;
        }
      }
      painter.paint(canvas, Offset(size.width - painter.width, actualTop));
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _GutterPainter old) => true;
}
