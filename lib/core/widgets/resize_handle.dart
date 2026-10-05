import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// Thin draggable divider between two panes.
class ResizeHandle extends StatefulWidget {
  const ResizeHandle({
    super.key,
    required this.onDrag,
    this.onEnd,
    this.axis = Axis.horizontal,
  });

  /// Called with the delta along the axis.
  final ValueChanged<double> onDrag;
  final VoidCallback? onEnd;
  final Axis axis;

  @override
  State<ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<ResizeHandle> {
  bool _hover = false;
  bool _drag = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final horizontal = widget.axis == Axis.horizontal;
    final active = _hover || _drag;

    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: horizontal
            ? (_) => setState(() => _drag = true)
            : null,
        onHorizontalDragUpdate: horizontal
            ? (d) => widget.onDrag(d.delta.dx)
            : null,
        onHorizontalDragEnd: horizontal
            ? (_) {
                setState(() => _drag = false);
                widget.onEnd?.call();
              }
            : null,
        onVerticalDragStart: horizontal
            ? null
            : (_) => setState(() => _drag = true),
        onVerticalDragUpdate: horizontal
            ? null
            : (d) => widget.onDrag(d.delta.dy),
        onVerticalDragEnd: horizontal
            ? null
            : (_) {
                setState(() => _drag = false);
                widget.onEnd?.call();
              },
        child: SizedBox(
          width: horizontal ? 7 : null,
          height: horizontal ? null : 7,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: horizontal ? (active ? 3 : 1) : null,
              height: horizontal ? null : (active ? 3 : 1),
              color: active ? p.accent.withValues(alpha: 0.7) : p.border,
            ),
          ),
        ),
      ),
    );
  }
}
