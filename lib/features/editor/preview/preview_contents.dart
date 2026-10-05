import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../domain/markdown_utils.dart';
import '../../../core/theme/tokens.dart';

/// A quiet heading rail. Nearby marks fan out around the pointer without
/// moving the document or changing the hit targets.
class PreviewContents extends StatefulWidget {
  const PreviewContents({
    super.key,
    required this.headings,
    required this.active,
    required this.onJump,
  });
  final List<Heading> headings;
  final int active;
  final ValueChanged<int> onJump;
  @override
  State<PreviewContents> createState() => _PreviewContentsState();
}

class _PreviewContentsState extends State<PreviewContents> {
  int? _hovered, _focused;
  final _scroll = ScrollController();
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PreviewContents oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active &&
        _hovered == null &&
        _focused == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final target =
            (widget.active * 28 - _scroll.position.viewportDimension / 2 + 14)
                .clamp(0.0, _scroll.position.maxScrollExtent);
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(target);
        } else {
          _scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
  }

  String _title(Heading h) => h.text
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'[*`~]'), '');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final near = _hovered ?? _focused;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          constraints.maxHeight,
          widget.headings.length * 28.0,
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: height,
            child: MouseRegion(
              onExit: (_) => setState(() => _hovered = null),
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView.builder(
                  controller: _scroll,
                  padding: EdgeInsets.zero,
                  itemExtent: 28,
                  itemCount: widget.headings.length,
                  itemBuilder: (context, index) {
                    final h = widget.headings[index];
                    final selected = index == widget.active;
                    final distance = near == null ? 99 : (index - near).abs();
                    final width = 12.0 + math.max(0, 4 - distance) * 6;
                    return Semantics(
                      label: context.tr('Jump to {heading}', {
                        'heading': _title(h),
                      }),
                      selected: selected,
                      button: true,
                      child: Tooltip(
                        message: _title(h),
                        waitDuration: const Duration(milliseconds: 500),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          onEnter: (_) => setState(() => _hovered = index),
                          onHover: (_) {
                            if (_hovered != index) {
                              setState(() => _hovered = index);
                            }
                          },
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: ValueKey('preview-toc-${h.line}'),
                              borderRadius: BorderRadius.circular(Rad.sm),
                              onFocusChange: (focus) => setState(
                                () => _focused = focus ? index : null,
                              ),
                              onTap: () => widget.onJump(index),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 40,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: AnimatedContainer(
                                        key: ValueKey(
                                          'preview-toc-mark-${h.line}',
                                        ),
                                        duration: duration,
                                        curve: Curves.easeOutCubic,
                                        width: width,
                                        height: selected ? 3 : 2,
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? p.accent
                                              : p.textMuted.withValues(
                                                  alpha: near == null
                                                      ? .35
                                                      : .65,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: AnimatedOpacity(
                                      opacity: near == null ? 0 : 1,
                                      duration: duration,
                                      child: Padding(
                                        padding: EdgeInsets.only(
                                          left: math.min(
                                            12,
                                            (h.level - 1) * 3.0,
                                          ),
                                        ),
                                        child: Text(
                                          _title(h),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: Fs.small,
                                            fontWeight: selected
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                            color: selected
                                                ? p.text
                                                : p.textMuted,
                                          ),
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
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
