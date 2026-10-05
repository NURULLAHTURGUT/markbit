import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../domain/mermaid.dart';
import '../../dialogs/dialogs.dart';

/// A Mermaid flowchart or sequence diagram drawn natively, with a toggle to
/// show its source.
class MermaidView extends StatefulWidget {
  const MermaidView({super.key, required this.diagram, required this.source});
  final MermaidDiagram diagram;
  final String source;

  @override
  State<MermaidView> createState() => _MermaidViewState();
}

class _MermaidViewState extends State<MermaidView> {
  bool _source = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final kind = switch (widget.diagram) {
      Flowchart() => context.tr('Flowchart'),
      SequenceDiagram() => context.tr('Sequence diagram'),
    };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: Sp.sm),
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.only(left: Sp.md, right: Sp.xs),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 14, color: p.textFaint),
                const SizedBox(width: Sp.xs + 2),
                Text(
                  'Mermaid · $kind',
                  style: TextStyle(
                    color: p.textMuted,
                    fontSize: Fs.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.copy_rounded,
                  size: 16,
                  tooltip: context.tr('Copy code'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.source));
                    showToast(context, context.tr('Code copied'));
                  },
                ),
                AppIconButton(
                  icon: _source ? Icons.schema_outlined : Icons.code_rounded,
                  size: 16,
                  tooltip: context.tr(_source ? 'Show diagram' : 'Show source'),
                  active: _source,
                  onPressed: () => setState(() => _source = !_source),
                ),
              ],
            ),
          ),
          if (_source)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(Sp.md),
              child: SelectableText(
                widget.source,
                style: AppTheme.mono(size: 12.5, color: p.text),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final _DiagramPainter painter = switch (widget.diagram) {
                  final Flowchart f => _FlowchartPainter.layout(f, p),
                  final SequenceDiagram s => _SequencePainter.layout(s, p),
                };
                final size = painter.size;
                final canvas = CustomPaint(size: size, painter: painter);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(Sp.md),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: math.max(0, constraints.maxWidth - Sp.md * 2),
                    ),
                    child: Center(child: canvas),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

abstract class _DiagramPainter extends CustomPainter {
  Size get size;
}

TextPainter _text(
  String text,
  Color color, {
  double size = 13,
  FontWeight weight = FontWeight.w500,
  double maxWidth = 200,
  TextAlign align = TextAlign.center,
}) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(
      fontFamily: AppTheme.uiFont,
      color: color,
      fontSize: size,
      fontWeight: weight,
      height: 1.3,
    ),
  ),
  textAlign: align,
  textDirection: TextDirection.ltr,
)..layout(maxWidth: maxWidth);

void _arrowHead(Canvas canvas, Offset tip, Offset from, Paint paint) {
  final dir = tip - from;
  if (dir.distance == 0) return;
  final unit = dir / dir.distance;
  final normal = Offset(-unit.dy, unit.dx);
  final base = tip - unit * 9;
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo((base + normal * 4.5).dx, (base + normal * 4.5).dy)
      ..lineTo((base - normal * 4.5).dx, (base - normal * 4.5).dy)
      ..close(),
    Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill,
  );
}

void _dashed(
  Canvas canvas,
  Offset a,
  Offset b,
  Paint paint, {
  double dash = 5,
}) {
  final d = b - a;
  final length = d.distance;
  if (length == 0) return;
  final unit = d / length;
  for (var t = 0.0; t < length; t += dash * 2) {
    canvas.drawLine(a + unit * t, a + unit * math.min(t + dash, length), paint);
  }
}

// ------------------------------------------------------------------ flowchart

class _PlacedNode {
  _PlacedNode(this.node, this.label, this.size);
  final FlowNode node;
  final TextPainter label;
  final Size size;
  int rank = 0;
  double order = 0;
  Offset center = Offset.zero;
  Rect get rect =>
      Rect.fromCenter(center: center, width: size.width, height: size.height);
}

/// Layered layout: ranks from the longest path (cycles ignored), order in a
/// rank by repeated barycenter sweeps, then evenly spaced rows.
class _FlowchartPainter extends _DiagramPainter {
  _FlowchartPainter(this.chart, this.palette, this.nodes, this.size);

  final Flowchart chart;
  final AppPalette palette;
  final Map<String, _PlacedNode> nodes;
  @override
  final Size size;

  factory _FlowchartPainter.layout(Flowchart chart, AppPalette p) {
    final nodes = <String, _PlacedNode>{};
    for (final n in chart.nodes) {
      final label = _text(n.label, p.text, maxWidth: 180);
      var w = label.width + 28, h = label.height + 18;
      switch (n.shape) {
        case FlowShape.diamond:
          w = w * 1.45;
          h = math.max(h * 1.6, 54);
        case FlowShape.circle:
          w = h = math.max(w, h) + 6;
        case FlowShape.hexagon || FlowShape.parallelogram:
          w += 18;
        default:
          break;
      }
      nodes[n.id] = _PlacedNode(n, label, Size(math.max(w, 56), h));
    }
    final out = <String, List<String>>{for (final id in nodes.keys) id: []};
    for (final e in chart.edges) {
      if (e.from != e.to) out[e.from]!.add(e.to);
    }
    // Drop back edges (DFS) so ranking terminates on cycles.
    final forward = <String, List<String>>{for (final id in nodes.keys) id: []};
    final state = <String, int>{};
    void dfs(String id) {
      state[id] = 1;
      for (final next in out[id]!) {
        if (state[next] == 1) continue; // back edge
        forward[id]!.add(next);
        if (state[next] == null) dfs(next);
      }
      state[id] = 2;
    }

    for (final id in nodes.keys) {
      if (state[id] == null) dfs(id);
    }
    // Longest path ranks.
    final indegree = {for (final id in nodes.keys) id: 0};
    for (final targets in forward.values) {
      for (final t in targets) {
        indegree[t] = indegree[t]! + 1;
      }
    }
    final queue = [
      for (final e in indegree.entries)
        if (e.value == 0) e.key,
    ];
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      for (final t in forward[id]!) {
        nodes[t]!.rank = math.max(nodes[t]!.rank, nodes[id]!.rank + 1);
        indegree[t] = indegree[t]! - 1;
        if (indegree[t] == 0) queue.add(t);
      }
    }
    final ranks = <int, List<_PlacedNode>>{};
    var index = 0;
    for (final n in nodes.values) {
      n.order = (index++).toDouble();
      ranks.putIfAbsent(n.rank, () => []).add(n);
    }
    final rankCount = ranks.keys.fold<int>(0, math.max) + 1;
    // Barycenter sweeps reduce crossings.
    final neighbours = <String, List<String>>{
      for (final id in nodes.keys) id: [],
    };
    for (final e in chart.edges) {
      neighbours[e.from]!.add(e.to);
      neighbours[e.to]!.add(e.from);
    }
    for (var sweep = 0; sweep < 6; sweep++) {
      for (var r = 0; r < rankCount; r++) {
        final row = ranks[r] ?? [];
        for (final n in row) {
          final ns = neighbours[n.node.id]!
              .map((id) => nodes[id]!)
              .where((m) => m.rank != n.rank)
              .toList();
          if (ns.isNotEmpty) {
            n.order = ns.fold<double>(0, (s, m) => s + m.order) / ns.length;
          }
        }
        row.sort((a, b) => a.order.compareTo(b.order));
        for (var i = 0; i < row.length; i++) {
          row[i].order = i.toDouble();
        }
      }
    }
    // Coordinates along the flow (main) and across it (cross).
    const rankGap = 56.0, nodeGap = 28.0, margin = 8.0;
    final horizontal = chart.horizontal;
    double mainOf(Size s) => horizontal ? s.width : s.height;
    double crossOf(Size s) => horizontal ? s.height : s.width;
    final rankSize = <int, double>{};
    final rowSize = <int, double>{};
    for (final entry in ranks.entries) {
      rankSize[entry.key] = entry.value
          .map((n) => mainOf(n.size))
          .fold(0, math.max);
      rowSize[entry.key] =
          entry.value.fold<double>(0, (s, n) => s + crossOf(n.size)) +
          nodeGap * (entry.value.length - 1);
    }
    final widest = rowSize.values.fold<double>(0, math.max);
    var main = margin;
    for (var r = 0; r < rankCount; r++) {
      final row = ranks[r] ?? [];
      final extent = rankSize[r] ?? 0;
      var cross = margin + (widest - (rowSize[r] ?? 0)) / 2;
      for (final n in row) {
        final c = cross + crossOf(n.size) / 2;
        final m = main + extent / 2;
        n.center = horizontal ? Offset(m, c) : Offset(c, m);
        cross += crossOf(n.size) + nodeGap;
      }
      main += extent + rankGap;
    }
    final total = main - rankGap + margin;
    var size = horizontal
        ? Size(total, widest + margin * 2)
        : Size(widest + margin * 2, total);
    // Bottom-up and right-left mirror the main axis.
    if (chart.direction == FlowDirection.bottomUp ||
        chart.direction == FlowDirection.rightLeft) {
      for (final n in nodes.values) {
        n.center = horizontal
            ? Offset(size.width - n.center.dx, n.center.dy)
            : Offset(n.center.dx, size.height - n.center.dy);
      }
    }
    size = Size(math.max(size.width, 40), math.max(size.height, 40));
    return _FlowchartPainter(chart, p, nodes, size);
  }

  /// Where the line from the node center towards [toward] leaves its shape.
  Offset _exit(_PlacedNode n, Offset toward) {
    final d = toward - n.center;
    if (d.distance == 0) return n.center;
    final hw = n.size.width / 2, hh = n.size.height / 2;
    if (n.node.shape == FlowShape.circle) {
      return n.center + d / d.distance * hw;
    }
    if (n.node.shape == FlowShape.diamond) {
      final t = 1 / (d.dx.abs() / hw + d.dy.abs() / hh);
      return n.center + d * t;
    }
    final t = math.min(
      d.dx == 0 ? double.infinity : hw / d.dx.abs(),
      d.dy == 0 ? double.infinity : hh / d.dy.abs(),
    );
    return n.center + d * t;
  }

  @override
  void paint(Canvas canvas, Size _) {
    final p = palette;
    for (final e in chart.edges) {
      if (e.line == FlowLine.invisible) continue;
      final a = nodes[e.from]!, b = nodes[e.to]!;
      final paint = Paint()
        ..color = p.textMuted
        ..strokeWidth = e.line == FlowLine.thick ? 2.6 : 1.4
        ..style = PaintingStyle.stroke;
      if (e.from == e.to) {
        final r = a.rect;
        final loop = Path()
          ..moveTo(r.right, r.center.dy - 6)
          ..cubicTo(
            r.right + 34,
            r.center.dy - 26,
            r.right + 34,
            r.center.dy + 26,
            r.right,
            r.center.dy + 6,
          );
        canvas.drawPath(loop, paint);
        if (e.arrow) {
          _arrowHead(
            canvas,
            Offset(r.right, r.center.dy + 6),
            Offset(r.right + 20, r.center.dy + 14),
            paint,
          );
        }
        continue;
      }
      final start = _exit(a, b.center), end = _exit(b, a.center);
      if (e.line == FlowLine.dotted) {
        _dashed(canvas, start, end, paint, dash: 4);
      } else {
        canvas.drawLine(start, end, paint);
      }
      if (e.arrow) _arrowHead(canvas, end, start, paint);
      if (e.arrowBack) _arrowHead(canvas, start, end, paint);
      if (e.label.isNotEmpty) {
        final label = _text(e.label, p.textMuted, size: 11.5, maxWidth: 140);
        final mid = (start + end) / 2;
        final box = Rect.fromCenter(
          center: mid,
          width: label.width + 10,
          height: label.height + 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(4)),
          Paint()..color = p.codeBg,
        );
        label.paint(canvas, box.topLeft + const Offset(5, 2));
      }
    }
    for (final n in nodes.values) {
      final r = n.rect;
      final fill = Paint()
        ..color = p.accent.withValues(alpha: p.isDark ? .16 : .10);
      final stroke = Paint()
        ..color = p.accent.withValues(alpha: .75)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;
      final Path shape;
      switch (n.node.shape) {
        case FlowShape.round:
          shape = Path()
            ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(10)));
        case FlowShape.stadium:
          shape = Path()
            ..addRRect(
              RRect.fromRectAndRadius(r, Radius.circular(r.height / 2)),
            );
        case FlowShape.circle:
          shape = Path()..addOval(r);
        case FlowShape.diamond:
          shape = Path()
            ..moveTo(r.center.dx, r.top)
            ..lineTo(r.right, r.center.dy)
            ..lineTo(r.center.dx, r.bottom)
            ..lineTo(r.left, r.center.dy)
            ..close();
        case FlowShape.hexagon:
          const k = 12.0;
          shape = Path()
            ..moveTo(r.left + k, r.top)
            ..lineTo(r.right - k, r.top)
            ..lineTo(r.right, r.center.dy)
            ..lineTo(r.right - k, r.bottom)
            ..lineTo(r.left + k, r.bottom)
            ..lineTo(r.left, r.center.dy)
            ..close();
        case FlowShape.parallelogram:
          const k = 10.0;
          shape = Path()
            ..moveTo(r.left + k, r.top)
            ..lineTo(r.right, r.top)
            ..lineTo(r.right - k, r.bottom)
            ..lineTo(r.left, r.bottom)
            ..close();
        case FlowShape.flag:
          shape = Path()
            ..moveTo(r.left, r.top)
            ..lineTo(r.right, r.top)
            ..lineTo(r.right, r.bottom)
            ..lineTo(r.left, r.bottom)
            ..lineTo(r.left + 10, r.center.dy)
            ..close();
        case FlowShape.database:
          shape = Path()
            ..addRRect(
              RRect.fromRectAndRadius(r, Radius.elliptical(r.width / 2, 7)),
            );
        case FlowShape.rect || FlowShape.subroutine:
          shape = Path()
            ..addRRect(RRect.fromRectAndRadius(r, const Radius.circular(3)));
      }
      canvas.drawPath(shape, fill);
      canvas.drawPath(shape, stroke);
      if (n.node.shape == FlowShape.subroutine) {
        canvas.drawLine(
          Offset(r.left + 7, r.top),
          Offset(r.left + 7, r.bottom),
          stroke,
        );
        canvas.drawLine(
          Offset(r.right - 7, r.top),
          Offset(r.right - 7, r.bottom),
          stroke,
        );
      }
      if (n.node.shape == FlowShape.database) {
        canvas.drawOval(Rect.fromLTWH(r.left, r.top, r.width, 14), stroke);
      }
      n.label.paint(
        canvas,
        r.center - Offset(n.label.width / 2, n.label.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(_FlowchartPainter old) =>
      old.chart != chart || old.palette != palette;
}

// ------------------------------------------------------------------- sequence

class _SequencePainter extends _DiagramPainter {
  _SequencePainter(this.diagram, this.palette, this.x, this.size, this.boxes);

  final SequenceDiagram diagram;
  final AppPalette palette;

  /// Lifeline x position per participant id.
  final Map<String, double> x;
  @override
  final Size size;
  final Map<String, TextPainter> boxes;

  static const double _top = 8, _boxHeight = 38, _row = 42, _gap = 40;

  factory _SequencePainter.layout(SequenceDiagram d, AppPalette p) {
    final boxes = {
      for (final part in d.participants)
        part.id: _text(
          part.label,
          p.text,
          weight: FontWeight.w600,
          maxWidth: 160,
        ),
    };
    // Space columns so the longest message between neighbours fits.
    final widths = [
      for (final part in d.participants)
        math.max(boxes[part.id]!.width + 28, 80.0),
    ];
    final order = {
      for (var i = 0; i < d.participants.length; i++) d.participants[i].id: i,
    };
    final gaps = List<double>.filled(
      math.max(0, d.participants.length - 1),
      _gap,
    );
    for (final item in d.items) {
      if (item is! SeqMessage) continue;
      final a = order[item.from]!, b = order[item.to]!;
      final label = _text(item.text, p.text, size: 12, maxWidth: 260);
      final need = label.width + 30;
      if (a == b) {
        if (a < gaps.length) gaps[a] = math.max(gaps[a], label.width + 50);
        continue;
      }
      final lo = math.min(a, b), hi = math.max(a, b);
      var span = 0.0;
      for (var i = lo; i < hi; i++) {
        span += widths[i] / 2 + gaps[i] + widths[i + 1] / 2;
      }
      if (span < need) {
        final extra = (need - span) / (hi - lo);
        for (var i = lo; i < hi; i++) {
          gaps[i] += extra;
        }
      }
    }
    final x = <String, double>{};
    var cursor = 8.0;
    for (var i = 0; i < d.participants.length; i++) {
      x[d.participants[i].id] = cursor + widths[i] / 2;
      cursor += widths[i] + (i < gaps.length ? gaps[i] : 0);
    }
    var height = _top + _boxHeight + 20;
    for (final item in d.items) {
      height += switch (item) {
        SeqMessage(:final from, :final to, :final text) =>
          (from == to ? _row + 18 : _row) +
              (_text(text, p.text, size: 12, maxWidth: 260).height - 16).clamp(
                0,
                200,
              ),
        SeqNote(:final text) =>
          _text(text, p.text, size: 12, maxWidth: 220).height + 26,
        SeqBlockStart() || SeqBlockSection() => 30,
        SeqBlockEnd() => 12,
      };
    }
    height += _boxHeight + 16;
    return _SequencePainter(d, p, x, Size(cursor + 8, height), boxes);
  }

  void _participant(Canvas canvas, SeqParticipant part, double y) {
    final p = palette;
    final cx = x[part.id]!;
    final label = boxes[part.id]!;
    final rect = Rect.fromCenter(
      center: Offset(cx, y + _boxHeight / 2),
      width: math.max(label.width + 24, 72),
      height: _boxHeight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = p.accent.withValues(alpha: p.isDark ? .18 : .10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()
        ..color = p.accent.withValues(alpha: .75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
    if (part.actor) {
      final icon = Paint()
        ..color = p.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3;
      final head = Offset(rect.left + 12, rect.center.dy - 5);
      canvas.drawCircle(head, 3.5, icon);
      canvas.drawLine(
        head + const Offset(0, 3.5),
        head + const Offset(0, 11),
        icon,
      );
    }
    label.paint(
      canvas,
      rect.center - Offset(label.width / 2, label.height / 2),
    );
  }

  @override
  void paint(Canvas canvas, Size _) {
    final p = palette;
    final d = diagram;
    final line = Paint()
      ..color = p.textFaint.withValues(alpha: .6)
      ..strokeWidth = 1;
    final lifeTop = _top + _boxHeight,
        lifeBottom = size.height - _boxHeight - 8;
    for (final part in d.participants) {
      _dashed(
        canvas,
        Offset(x[part.id]!, lifeTop),
        Offset(x[part.id]!, lifeBottom),
        line,
      );
      _participant(canvas, part, _top);
      _participant(canvas, part, lifeBottom);
    }
    final left = x.values.fold<double>(double.infinity, math.min) - 30;
    final right = x.values.fold<double>(0, math.max) + 30;
    var y = lifeTop + 20;
    final blocks = <(double, String, String)>[]; // top, kind, label
    final message = Paint()
      ..color = p.text.withValues(alpha: .85)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    for (final item in d.items) {
      switch (item) {
        case SeqMessage():
          final label = _text(
            item.number == null ? item.text : '${item.number}. ${item.text}',
            p.text,
            size: 12,
            maxWidth: 260,
          );
          final extra = (label.height - 16).clamp(0, 200).toDouble();
          final x1 = x[item.from]!, x2 = x[item.to]!;
          if (item.from == item.to) {
            label.paint(canvas, Offset(x1 + 8, y - 2));
            final ly = y + label.height + 2;
            final path = Path()
              ..moveTo(x1, ly)
              ..lineTo(x1 + 34, ly)
              ..lineTo(x1 + 34, ly + 16)
              ..lineTo(x1, ly + 16);
            canvas.drawPath(path, message);
            _arrowHead(
              canvas,
              Offset(x1, ly + 16),
              Offset(x1 + 10, ly + 16),
              message,
            );
            y += _row + 18 + extra;
            break;
          }
          label.paint(canvas, Offset((x1 + x2) / 2 - label.width / 2, y));
          final ly = y + label.height + 4;
          final start = Offset(x1, ly), end = Offset(x2, ly);
          if (item.dashed) {
            _dashed(canvas, start, end, message);
          } else {
            canvas.drawLine(start, end, message);
          }
          switch (item.arrow) {
            case SeqArrow.filled:
              _arrowHead(canvas, end, start, message);
            case SeqArrow.open || SeqArrow.async:
              final dir = x2 > x1 ? -1.0 : 1.0;
              canvas.drawLine(end, end + Offset(dir * 9, -5), message);
              canvas.drawLine(end, end + Offset(dir * 9, 5), message);
            case SeqArrow.cross:
              canvas.drawLine(
                end + const Offset(-5, -5),
                end + const Offset(5, 5),
                message,
              );
              canvas.drawLine(
                end + const Offset(-5, 5),
                end + const Offset(5, -5),
                message,
              );
          }
          y += _row + extra;
        case SeqNote():
          final label = _text(item.text, p.text, size: 12, maxWidth: 220);
          final xs = item.participants.map((id) => x[id]!).toList();
          final lo = xs.reduce(math.min), hi = xs.reduce(math.max);
          final w = math.max(
            label.width + 16,
            hi - lo + (item.placement == NotePlacement.over ? 60 : 0),
          );
          final cx = switch (item.placement) {
            NotePlacement.left => lo - w / 2 - 12,
            NotePlacement.right => hi + w / 2 + 12,
            NotePlacement.over => (lo + hi) / 2,
          };
          final rect = Rect.fromCenter(
            center: Offset(cx, y + (label.height + 12) / 2),
            width: w,
            height: label.height + 12,
          );
          canvas.drawRect(
            rect,
            Paint()..color = p.warning.withValues(alpha: p.isDark ? .22 : .16),
          );
          canvas.drawRect(
            rect,
            Paint()
              ..color = p.warning.withValues(alpha: .7)
              ..style = PaintingStyle.stroke,
          );
          label.paint(
            canvas,
            rect.center - Offset(label.width / 2, label.height / 2),
          );
          y += label.height + 26;
        case SeqBlockStart():
          blocks.add((y, item.kind, item.label));
          y += 30;
        case SeqBlockSection():
          if (blocks.isNotEmpty) {
            _dashed(canvas, Offset(left, y + 4), Offset(right, y + 4), line);
            _text(
              '[${item.label}]',
              p.textMuted,
              size: 11.5,
              maxWidth: 260,
            ).paint(canvas, Offset(left + 8, y + 8));
          }
          y += 30;
        case SeqBlockEnd():
          if (blocks.isEmpty) break;
          final (top, kind, label) = blocks.removeLast();
          final inset = blocks.length * 6.0;
          final rect = Rect.fromLTRB(left + inset, top, right - inset, y + 4);
          canvas.drawRect(
            rect,
            Paint()
              ..color = p.textMuted.withValues(alpha: .7)
              ..style = PaintingStyle.stroke,
          );
          final tag = _text(kind, p.text, size: 11, weight: FontWeight.w700);
          final tab = Rect.fromLTWH(
            rect.left,
            rect.top,
            tag.width + 14,
            tag.height + 6,
          );
          canvas.drawRect(tab, Paint()..color = p.surface.withValues(alpha: 1));
          canvas.drawRect(
            tab,
            Paint()
              ..color = p.textMuted.withValues(alpha: .7)
              ..style = PaintingStyle.stroke,
          );
          tag.paint(canvas, tab.topLeft + const Offset(7, 3));
          if (label.isNotEmpty) {
            _text(
              '[$label]',
              p.textMuted,
              size: 11.5,
              maxWidth: 260,
            ).paint(canvas, Offset(tab.right + 8, rect.top + 4));
          }
          y += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_SequencePainter old) =>
      old.diagram != diagram || old.palette != palette;
}
