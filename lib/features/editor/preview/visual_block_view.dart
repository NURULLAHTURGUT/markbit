import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../domain/visual_block.dart';
import '../../../core/theme/tokens.dart';

class VisualBlockView extends StatelessWidget {
  const VisualBlockView({super.key, required this.source, this.onEdit});
  final String source;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final block = VisualBlock.parse(source);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: p.codeBg,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(Rad.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Icon(
                  block?.kind == VisualKind.mindmap
                      ? Icons.account_tree_outlined
                      : Icons.bar_chart_rounded,
                  size: 18,
                  color: p.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    block?.title ?? context.tr('Invalid visual block'),
                    style: TextStyle(
                      color: p.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onEdit != null)
                  IconButton(
                    tooltip: context.tr('Edit visual block'),
                    onPressed: onEdit,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: p.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          if (block == null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr('Check the block data in the editor.'),
                style: TextStyle(color: p.textMuted),
              ),
            )
          else if (block.kind == VisualKind.mindmap)
            _MindMap(block: block)
          else
            _Chart(block: block),
        ],
      ),
    );
  }
}

class _MindMap extends StatelessWidget {
  const _MindMap({required this.block});
  final VisualBlock block;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final layout = _MapLayout(block);
    return Semantics(
      label: '${block.title}: ${block.input}',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: CustomPaint(
            size: layout.size,
            painter: _MapPainter(
              layout,
              p.text,
              p.accent,
              p.border,
              p.editorBg,
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLayout {
  _MapLayout(VisualBlock block) {
    labels = [block.title, ...block.items.map((i) => i.label)];
    final levels = [0, ...block.items.map((i) => i.depth + 1)];
    parents = [-1];
    final latest = <int, int>{0: 0};
    for (var i = 1; i < levels.length; i++) {
      parents.add(latest[levels[i] - 1]!);
      latest[levels[i]] = i;
    }
    final children = List.generate(labels.length, (_) => <int>[]);
    for (var i = 1; i < parents.length; i++) {
      children[parents[i]].add(i);
    }
    var leaf = 0;
    final y = List.filled(labels.length, 0.0);
    double position(int i) {
      if (children[i].isEmpty) return y[i] = 26 + leaf++ * 64.0;
      final ys = children[i].map(position).toList();
      return y[i] = (ys.first + ys.last) / 2;
    }

    position(0);
    positions = [
      for (var i = 0; i < labels.length; i++) Offset(levels[i] * 206.0, y[i]),
    ];
    size = Size(
      levels.reduce(math.max) * 206.0 + 168,
      math.max(104, leaf * 64.0),
    );
  }
  late final List<String> labels;
  late final List<int> parents;
  late final List<Offset> positions;
  late final Size size;
}

void _text(
  Canvas canvas,
  String text,
  Offset at,
  Color color, {
  double width = 150,
  double fontSize = 12,
  TextAlign align = TextAlign.left,
  bool bold = false,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
      ),
    ),
    maxLines: 2,
    ellipsis: '…',
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width);
  painter.paint(canvas, at);
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.layout, this.text, this.accent, this.border, this.fill);
  final _MapLayout layout;
  final Color text, accent, border, fill;
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = accent.withValues(alpha: .45)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 1; i < layout.positions.length; i++) {
      final a = layout.positions[layout.parents[i]] + const Offset(168, 0);
      final b = layout.positions[i];
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..cubicTo(a.dx + 20, a.dy, b.dx - 20, b.dy, b.dx, b.dy),
        line,
      );
    }
    for (var i = 0; i < layout.positions.length; i++) {
      final at = layout.positions[i];
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(at.dx, at.dy - 24, 168, 48),
        const Radius.circular(Rad.md),
      );
      canvas.drawRRect(
        rect,
        Paint()..color = i == 0 ? accent.withValues(alpha: .15) : fill,
      );
      canvas.drawRRect(
        rect,
        Paint()
          ..color = i == 0 ? accent : border
          ..style = PaintingStyle.stroke,
      );
      _text(
        canvas,
        layout.labels[i],
        at + const Offset(12, -15),
        text,
        width: 144,
        bold: i == 0,
      );
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}

class _Chart extends StatelessWidget {
  const _Chart({required this.block});
  final VisualBlock block;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colors = [
      p.accent,
      p.success,
      p.warning,
      p.synFunction,
      p.synString,
      p.synKeyword,
    ];
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            label: '${block.title}: ${block.input}',
            child: SizedBox(
              height: 240,
              child: CustomPaint(
                painter: _ChartPainter(block, colors, p.textMuted, p.border),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (var i = 0; i < block.items.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors[i % colors.length],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${i + 1}. ${block.items[i].label}: ${block.items[i].value}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.textMuted,
                          fontSize: Fs.small,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.block, this.colors, this.text, this.border);
  final VisualBlock block;
  final List<Color> colors;
  final Color text, border;
  @override
  void paint(Canvas canvas, Size size) {
    final values = block.items.map((i) => i.value).toList();
    if (block.style == ChartStyle.donut || block.style == ChartStyle.pie) {
      // Normalize before summing to avoid overflow with large finite values.
      final max = values.reduce(math.max);
      final scaled = values.map((v) => v / max).toList();
      final total = scaled.fold(0.0, (a, b) => a + b);
      var angle = -math.pi / 2;
      final radius = math.min(size.width, size.height) * .38;
      final rect = Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: radius,
      );
      for (var i = 0; i < values.length; i++) {
        final sweep = scaled[i] / total * 2 * math.pi;
        canvas.drawArc(
          rect,
          angle,
          sweep,
          block.style == ChartStyle.pie,
          Paint()
            ..color = colors[i % colors.length]
            ..style = block.style == ChartStyle.pie
                ? PaintingStyle.fill
                : PaintingStyle.stroke
            ..strokeWidth = 32,
        );
        angle += sweep;
      }
      return;
    }
    final maxAbs = values.map((v) => v.abs()).reduce(math.max);
    final normalized = values
        .map((v) => maxAbs == 0 ? 0.0 : v / maxAbs)
        .toList();
    var low = math.min(0.0, normalized.reduce(math.min));
    var high = math.max(0.0, normalized.reduce(math.max));
    if (high == low) high = low + 1;
    if (block.style == ChartStyle.horizontalBar) {
      final plot = Rect.fromLTWH(
        30,
        10,
        math.max(1, size.width - 44),
        size.height - 38,
      );
      double x(double value) =>
          plot.left + (value - low) / (high - low) * plot.width;
      for (var i = 0; i <= 4; i++) {
        final v = low + (high - low) * i / 4;
        canvas.drawLine(
          Offset(x(v), plot.top),
          Offset(x(v), plot.bottom),
          Paint()..color = border,
        );
        _text(
          canvas,
          (v * maxAbs).toStringAsPrecision(3),
          Offset(x(v) - 18, plot.bottom + 7),
          text,
          width: 40,
          fontSize: Fs.micro,
        );
      }
      final step = plot.height / values.length;
      for (var i = 0; i < values.length; i++) {
        final center = plot.top + step * (i + .5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              math.min(x(0), x(normalized[i])),
              center - step * .3,
              math.max(x(0), x(normalized[i])),
              center + step * .3,
            ),
            const Radius.circular(Rad.xs),
          ),
          Paint()..color = colors[i % colors.length],
        );
        _text(
          canvas,
          '${i + 1}',
          Offset(0, center - 6),
          text,
          width: 24,
          fontSize: Fs.micro,
        );
      }
      return;
    }
    final plot = Rect.fromLTWH(
      48,
      12,
      math.max(1, size.width - 58),
      size.height - 38,
    );
    double y(double v) => plot.bottom - (v - low) / (high - low) * plot.height;
    for (var i = 0; i <= 4; i++) {
      final v = low + (high - low) * i / 4;
      canvas.drawLine(
        Offset(plot.left, y(v)),
        Offset(plot.right, y(v)),
        Paint()..color = border,
      );
      _text(
        canvas,
        (v * maxAbs).toStringAsPrecision(3),
        Offset(0, y(v) - 7),
        text,
        width: 44,
        fontSize: Fs.micro,
      );
    }
    final step = plot.width / values.length;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = plot.left + step * (i + .5);
      final point = Offset(x, y(normalized[i]));
      if (block.style == ChartStyle.bar) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              x - step * .28,
              math.min(y(0), point.dy),
              x + step * .28,
              math.max(y(0), point.dy),
            ),
            const Radius.circular(Rad.xs),
          ),
          Paint()..color = colors[i % colors.length],
        );
      } else {
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawCircle(point, 4, Paint()..color = colors.first);
      }
      _text(
        canvas,
        '${i + 1}',
        Offset(x - 8, plot.bottom + 7),
        text,
        width: 20,
        fontSize: Fs.micro,
      );
    }
    if (block.style == ChartStyle.line || block.style == ChartStyle.area) {
      if (block.style == ChartStyle.area) {
        final fill = Path.from(path)
          ..lineTo(plot.left + step * (values.length - .5), y(0))
          ..lineTo(plot.left + step * .5, y(0))
          ..close();
        canvas.drawPath(
          fill,
          Paint()..color = colors.first.withValues(alpha: .22),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = colors.first
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) => true;
}
