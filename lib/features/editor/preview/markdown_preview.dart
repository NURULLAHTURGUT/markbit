import '../../../data/models/note.dart';
import '../../../data/note_attachment_service.dart';
import '../../dialogs/dialogs.dart';
import 'dart:typed_data';
import 'image_gallery.dart';
import '../../../data/note_images.dart';
import '../../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'preview_contents.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/markdown_utils.dart';
import 'code_block_view.dart';
import '../../../domain/visual_block.dart';
import '../../../domain/ai/ai_visuals.dart';
import 'visual_block_view.dart';
import '../../../domain/colored_text.dart';
import '../../../domain/markdown_extras.dart';
import '../../../domain/mermaid.dart';
import 'markdown_extras_view.dart';
import 'mermaid_view.dart';

/// Rendered markdown. Prose is delegated to `flutter_markdown_plus`; fenced
/// code blocks are rendered by [CodeBlockView] so they can be run.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({
    super.key,
    required this.body,
    required this.resolveNoteId,
    required this.onOpenNote,
    required this.onCreateNote,
    required this.onRun,
    this.scrollController,
    this.noteId,
    this.onEditVisual,
    this.onToggleTask,
    this.images = const {},
    this.attachments = const {},
    this.onEditImage,
  });

  final String? noteId;
  final String body;
  final Map<String, NoteAttachment> attachments;
  final Map<String, String> images;
  final void Function(String uri, String? title, int line, int occurrence)?
  onEditImage;
  final String? Function(String title) resolveNoteId;
  final void Function(String id) onOpenNote;
  final void Function(String title) onCreateNote;
  final void Function(String? language, String code) onRun;
  final AutoScrollController? scrollController;
  final ValueChanged<CodeSegment>? onEditVisual;
  final void Function(int line, bool value)? onToggleTask;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  final _imageBytes = <String, Uint8List>{};
  Uint8List _bytes(Uri uri) {
    final key = uri.toString();
    final cached = _imageBytes[key];
    if (cached != null) return cached;
    if (_imageBytes.length >= 32) _imageBytes.remove(_imageBytes.keys.first);
    return _imageBytes[key] = uri.data!.contentAsBytes();
  }

  String? _segmentsFor;
  List<BodySegment> _segments = const [];
  PreparedMarkdown _prepared = const PreparedMarkdown('', []);
  List<Heading> _headings = const [];
  final _viewportKey = GlobalKey();
  final _activeHeading = ValueNotifier<int>(0);
  AutoScrollController? _ownedScroll;
  bool _scrollUpdateScheduled = false;
  AutoScrollController get _scroll =>
      widget.scrollController ?? (_ownedScroll ??= AutoScrollController());

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scheduleActiveHeading);
    _scheduleActiveHeading();
  }

  @override
  void didUpdateWidget(covariant MarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      (oldWidget.scrollController ?? _ownedScroll)?.removeListener(
        _scheduleActiveHeading,
      );
      _scroll.addListener(_scheduleActiveHeading);
    }
    if (oldWidget.body != widget.body) _scheduleActiveHeading();
  }

  @override
  void dispose() {
    _scroll.removeListener(_scheduleActiveHeading);
    _ownedScroll?.dispose();
    _activeHeading.dispose();
    super.dispose();
  }

  void _scheduleActiveHeading() {
    if (_scrollUpdateScheduled) return;
    _scrollUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollUpdateScheduled = false;
      if (!mounted || !_scroll.hasClients || _headings.isEmpty) return;
      final viewport = _viewportKey.currentContext?.findRenderObject();
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final top = viewport.localToGlobal(Offset.zero).dy + 48;
      var low = 0, high = segments.length;
      while (low < high) {
        final middle = (low + high) ~/ 2;
        final box = _scroll.tagMap[middle]?.context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return;
        if (box.localToGlobal(Offset(0, box.size.height)).dy > top) {
          high = middle;
        } else {
          low = middle + 1;
        }
      }
      final int? firstVisible = low < segments.length ? low : null;
      if (firstVisible == null || firstVisible >= segments.length) return;
      final line = segments[firstVisible].startLine;
      var active = 0;
      for (var i = 0; i < _headings.length; i++) {
        if (_headings[i].line <= line) {
          active = i;
        } else {
          break;
        }
      }
      _activeHeading.value = active;
    });
  }

  Future<void> _jumpToHeading(int index) async {
    if (!_scroll.hasClients || _scroll.isAutoScrolling) return;
    final heading = _headings[index];
    final target = segments.indexWhere((s) => s.startLine == heading.line);
    if (target < 0) return;
    await _scroll.scrollToIndex(
      target,
      preferPosition: AutoScrollPosition.begin,
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 280),
    );
    if (mounted) _activeHeading.value = index;
  }

  Future<void> _jumpTo(int index) async {
    if (!_scroll.hasClients || _scroll.isAutoScrolling) return;
    await _scroll.scrollToIndex(
      index,
      preferPosition: AutoScrollPosition.begin,
      duration: MediaQuery.disableAnimationsOf(context)
          ? const Duration(milliseconds: 1)
          : const Duration(milliseconds: 280),
    );
  }

  List<BodySegment> get segments {
    if (_segmentsFor != widget.body) {
      _segments = [];
      _headings = extractHeadings(widget.body);
      // Same line numbers as the source: math blocks become fences and
      // footnote definitions blank lines.
      _prepared = prepareMarkdown(widget.body);
      for (final segment in splitSegments(_prepared.body)) {
        if (segment is! TextSegment) {
          _segments.add(segment);
          continue;
        }
        final lines = segment.text.split('\n');
        final starts = [
          0,
          ..._headings
              .where(
                (h) => h.line > segment.startLine && h.line <= segment.endLine,
              )
              .map((h) => h.line - segment.startLine),
          lines.length,
        ];
        for (var j = 0; j < starts.length - 1; j++) {
          final text = lines.sublist(starts[j], starts[j + 1]).join('\n');
          var start = 0;
          var line = segment.startLine + starts[j];
          // Split large sections at paragraph boundaries for smaller render blocks.
          for (final boundary in RegExp(r'\n\s*\n(?=\S)').allMatches(text)) {
            if (boundary.end - start < 6000) continue;
            final chunk = text.substring(start, boundary.end);
            final count = '\n'.allMatches(chunk).length;
            if (chunk.trim().isNotEmpty) {
              _segments.add(TextSegment(chunk, line, line + count));
            }
            start = boundary.end;
            line += count;
          }
          if (start < text.length && text.substring(start).trim().isNotEmpty) {
            _segments.add(
              TextSegment(
                text.substring(start),
                line,
                segment.startLine + starts[j + 1] - 1,
              ),
            );
          }
        }
      }
      _segmentsFor = widget.body;
    }
    return _segments;
  }

  Future<void> _onTapLink(String text, String? href, String title) async {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    if (uri.scheme == 'markbit') {
      if (uri.host == 'attachment' && uri.pathSegments.isNotEmpty) {
        final file = widget.attachments[uri.pathSegments.first];
        if (file != null) {
          try {
            await NoteAttachmentService.open(file);
          } catch (e) {
            if (mounted) {
              showToast(
                context,
                context.tr(
                  e is FormatException
                      ? e.message
                      : 'Could not open this attachment.',
                ),
              );
            }
          }
        }
      } else if (uri.host == 'note') {
        widget.onOpenNote(uri.pathSegments.first);
      } else if (uri.host == 'create' && uri.pathSegments.isNotEmpty) {
        widget.onCreateNote(Uri.decodeComponent(uri.pathSegments.first));
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final p = context.palette;
    final theme = Theme.of(context);
    final body = TextStyle(color: p.text, fontSize: 15, height: 1.65);
    TextStyle heading(double size) => TextStyle(
      color: p.synHeading,
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );

    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      pPadding: const EdgeInsets.only(bottom: 2),
      a: TextStyle(
        color: p.accent,
        decoration: TextDecoration.underline,
        decorationColor: p.accent.withValues(alpha: 0.5),
      ),
      h1: heading(28),
      h2: heading(23),
      h3: heading(19),
      h4: heading(16.5),
      h5: heading(15),
      h6: heading(14).copyWith(color: p.textMuted),
      h1Padding: const EdgeInsets.only(top: Sp.lg, bottom: Sp.xs),
      h2Padding: const EdgeInsets.only(top: Sp.lg, bottom: Sp.xs),
      h3Padding: const EdgeInsets.only(top: Sp.md),
      strong: TextStyle(color: p.text, fontWeight: FontWeight.w700),
      em: TextStyle(color: p.text, fontStyle: FontStyle.italic),
      del: TextStyle(
        color: p.textMuted,
        decoration: TextDecoration.lineThrough,
      ),
      code: AppTheme.mono(
        size: 13,
        color: p.synString,
        height: 1.5,
      ).copyWith(backgroundColor: p.codeBg),
      codeblockPadding: const EdgeInsets.all(Sp.md),
      codeblockDecoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: p.border),
      ),
      blockquote: body.copyWith(color: p.textMuted),
      blockquotePadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.md, Sp.sm),
      blockquoteDecoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.06),
        border: Border(left: BorderSide(color: p.accent, width: 3)),
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(Rad.sm),
        ),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border, width: 1.5)),
      ),
      tableHead: body.copyWith(fontWeight: FontWeight.w700),
      tableBody: body,
      tableBorder: TableBorder.all(
        color: p.border,
        width: 1,
        borderRadius: BorderRadius.circular(Rad.sm),
      ),
      tableCellsPadding: const EdgeInsets.symmetric(
        horizontal: Sp.md,
        vertical: Sp.sm,
      ),
      tableHeadAlign: TextAlign.left,
      listBullet: body.copyWith(color: p.textMuted),
      listIndent: 22,
      blockSpacing: 12,
      checkbox: body.copyWith(color: p.accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _styleSheet(context);
    final visible = segments
        .where((s) => s is! TextSegment || s.text.trim().isNotEmpty)
        .toList();
    final footnotes = _prepared.footnotes;
    List<md.InlineSyntax> inlineSyntaxes() => [
      MathInlineSyntax(),
      if (footnotes.isNotEmpty) FootnoteRefSyntax(_prepared.numbers),
      ColoredTextSyntax(),
    ];
    Map<String, MarkdownElementBuilder> inlineBuilders() => {
      'markbit-math': MathInlineBuilder(),
      'markbit-fnref': FootnoteRefBuilder((_) => _jumpTo(visible.length)),
    };

    Widget prose(TextSegment segment) {
      var checkbox = 0;
      final lines = segment.text.split('\n');
      final tasks = [
        for (var i = 0; i < lines.length; i++)
          if (RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+\[[ xX]\]').hasMatch(lines[i]))
            segment.startLine + i,
      ];
      final imageOccurrences = <String, int>{};
      Widget buildImage(Uri uri, String? title, String? alt) {
        final original = uri.toString();
        final occurrenceKey = "$original\n$title";
        final occurrence = imageOccurrences[occurrenceKey] ?? 0;
        imageOccurrences[occurrenceKey] = occurrence + 1;
        final resolved = uri.scheme == 'attachment'
            ? widget.images[uri.path]
            : original;
        Widget image;
        try {
          final source = Uri.parse(resolved ?? '');
          if (source.scheme == 'data') {
            image = Image.memory(
              _bytes(source),
              semanticLabel: alt,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) => Text(alt ?? 'Image'),
            );
          } else if (source.scheme == 'https' || source.scheme == 'http') {
            image = Image.network(
              source.toString(),
              semanticLabel: alt,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stack) => Text(alt ?? 'Image'),
            );
          } else {
            return Text(alt ?? original);
          }
        } catch (_) {
          return Text(alt ?? 'Image');
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth * NoteImages.width(title) / 100
                : null;
            final options = ImageOptions.parse(title, alt: alt ?? '');
            final sized = SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(
                      options.rounded ? 12 : 0,
                    ),
                    child: image,
                  ),
                  if (options.caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        options.caption.replaceAll('&#124;', '|'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.palette.textMuted,
                          fontSize: Fs.small,
                        ),
                      ),
                    ),
                ],
              ),
            );
            return Align(
              alignment: switch (ImageOptions.parse(title).align) {
                'center' => Alignment.center,
                'right' => Alignment.centerRight,
                _ => Alignment.centerLeft,
              },
              child: widget.onEditImage == null
                  ? sized
                  : Tooltip(
                      message: context.tr('Resize image'),
                      child: InkWell(
                        onTap: () => widget.onEditImage!(
                          original,
                          title,
                          segment.startLine,
                          occurrence,
                        ),
                        borderRadius: BorderRadius.circular(Rad.md),
                        child: sized,
                      ),
                    ),
            );
          },
        );
      }

      return MarkdownBody(
        data: linkifyWikiLinks(segment.text, widget.resolveNoteId),
        styleSheet: sheet,
        softLineBreak: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: inlineSyntaxes(),
        blockSyntaxes: [ImageGallerySyntax(), ColoredTextBlockSyntax()],
        builders: {
          'markbit-color': _ColoredTextBuilder(),
          'markbit-gallery': ImageGalleryBuilder(buildImage),
          ...inlineBuilders(),
        },
        onTapLink: _onTapLink,
        imageBuilder: buildImage,

        checkboxBuilder: (value) {
          final line = checkbox < tasks.length ? tasks[checkbox] : null;
          checkbox++;
          return SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: widget.onToggleTask == null || line == null
                  ? null
                  : (checked) => widget.onToggleTask!(line, checked ?? false),
            ),
          );
        },
      );
    }

    Widget segmentWidget(BodySegment seg) => switch (seg) {
      TextSegment() => prose(seg),
      CodeSegment(:final info, :final code)
          when info.toLowerCase() == 'math' || info.toLowerCase() == 'latex' =>
        MathBlockView(tex: code),
      CodeSegment(:final info, :final code)
          when info.toLowerCase() == 'mermaid' &&
              aiVisual(info, code) == null &&
              MermaidDiagram.parse(code) != null =>
        MermaidView(diagram: MermaidDiagram.parse(code)!, source: code),
      CodeSegment(:final info, :final code) =>
        aiVisual(info, code) != null || info == VisualBlock.fence
            ? VisualBlockView(
                source: aiVisual(info, code)?.json ?? code,
                onEdit: widget.onEditVisual == null || info != VisualBlock.fence
                    ? null
                    : () => widget.onEditVisual!(seg),
              )
            : CodeBlockView(
                info: info,
                code: code,
                onRun: widget.onRun,
                noteId: widget.noteId,
              ),
    };

    if (visible.isEmpty) {
      return Center(
        child: Text(
          context.tr('Nothing to preview yet'),
          style: TextStyle(color: context.palette.textFaint),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = (constraints.maxWidth - 820) / 2;
        final showContents = _headings.isNotEmpty && gutter >= 90;
        return Stack(
          key: _viewportKey,
          children: [
            Positioned.fill(
              child: SelectionArea(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.depth == 0,
                    child: SingleChildScrollView(
                      key: const ValueKey('note-preview-scroll'),
                      controller: _scroll,
                      primary: false,
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        Sp.xl,
                        Sp.lg,
                        Sp.xl,
                        96,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0; index < visible.length; index++)
                            AutoScrollTag(
                              key: ValueKey(
                                '${visible[index].startLine}:$index',
                              ),
                              controller: _scroll,
                              index: index,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 820,
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: RepaintBoundary(
                                      child: segmentWidget(visible[index]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (footnotes.isNotEmpty)
                            AutoScrollTag(
                              key: const ValueKey('footnotes'),
                              controller: _scroll,
                              index: visible.length,
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 820,
                                  ),
                                  child: FootnotesSection(
                                    footnotes: footnotes,
                                    buildText: (text) => MarkdownBody(
                                      data: linkifyWikiLinks(
                                        text,
                                        widget.resolveNoteId,
                                      ),
                                      styleSheet: sheet,
                                      softLineBreak: true,
                                      extensionSet:
                                          md.ExtensionSet.gitHubFlavored,
                                      inlineSyntaxes: inlineSyntaxes(),
                                      builders: {
                                        'markbit-color': _ColoredTextBuilder(),
                                        ...inlineBuilders(),
                                      },
                                      onTapLink: _onTapLink,
                                    ),
                                    onBack: (f) {
                                      final at = visible.indexWhere(
                                        (s) =>
                                            s.startLine <= f.refLine &&
                                            s.endLine >= f.refLine,
                                      );
                                      if (at >= 0) _jumpTo(at);
                                    },
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showContents)
              Positioned(
                left: 16,
                top: 24,
                bottom: 24,
                width: (gutter - 32).clamp(58, 280),
                child: ValueListenableBuilder<int>(
                  valueListenable: _activeHeading,
                  builder: (context, active, _) => PreviewContents(
                    headings: _headings,
                    active: active,
                    onJump: _jumpToHeading,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ColoredTextBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    TextStyle applyStyles(TextStyle style, md.Element e) {
      final hex = e.attributes['color'];
      final size = double.tryParse(e.attributes['font-size'] ?? '');
      return style.copyWith(
        color: hex == null ? null : Color(int.parse('FF$hex', radix: 16)),
        fontSize: size == null ? null : size * 4 / 3,
        fontFamily: e.attributes['font-family'],
      );
    }

    final base = applyStyles(
      parentStyle ?? Theme.of(context).textTheme.bodyMedium!,
      element,
    );
    final spans = <TextSpan>[];
    void inline(md.Node node, TextStyle style) {
      if (node is md.Text) {
        spans.add(TextSpan(text: node.text, style: style));
        return;
      }
      final e = node as md.Element;
      final next = applyStyles(style, e).copyWith(
        fontWeight: e.tag == 'strong' ? FontWeight.bold : style.fontWeight,
        fontStyle: e.tag == 'em' ? FontStyle.italic : style.fontStyle,
        decoration: e.tag == 'del'
            ? TextDecoration.lineThrough
            : style.decoration,
      );
      for (final child in e.children ?? <md.Node>[]) {
        inline(child, next);
      }
    }

    for (final child in element.children ?? <md.Node>[]) {
      inline(child, base);
    }
    return Text.rich(TextSpan(children: spans));
  }
}
