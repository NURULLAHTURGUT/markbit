import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library_notifier.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../../data/models/note.dart';
import '../../domain/markdown_utils.dart';

/// Notes linked from [note]: `[[Title]]`, `[[id:…]]` and markbit:// links.
Set<String> linkedNoteIds(Note note, Library lib) {
  if (note.isLocked || note.kind != NoteKind.markdown) return const {};
  final out = <String>{};
  for (final target in extractWikiLinks(note.body)) {
    final id = target.startsWith('id:')
        ? target.substring(3)
        : lib.findNoteIdByTitle(target);
    if (id != null && id != note.id && lib.notes[id]?.trashed == false) {
      out.add(id);
    }
  }
  for (final m in _uriLink.allMatches(note.body)) {
    final id = m[1]!;
    if (id != note.id && lib.notes[id]?.trashed == false) out.add(id);
  }
  return out;
}

final _uriLink = RegExp(r'markbit://note/([A-Za-z0-9_-]+)');

/// Undirected links between notes, used by the graph view.
class NoteGraph {
  NoteGraph(this.nodes, this.edges);
  final List<Note> nodes;
  final List<(int, int)> edges;

  factory NoteGraph.build(
    Library lib, {
    bool includeUnlinked = false,
    String? focusId,
    int depth = 1,
  }) {
    final notes = lib.notes.values.where((n) => !n.trashed).toList();
    final pairs = <(String, String)>{};
    final degree = <String, int>{};
    for (final n in notes) {
      for (final target in linkedNoteIds(n, lib)) {
        final a = n.id.compareTo(target) < 0 ? n.id : target;
        final b = a == n.id ? target : n.id;
        if (pairs.add((a, b))) {
          degree[a] = (degree[a] ?? 0) + 1;
          degree[b] = (degree[b] ?? 0) + 1;
        }
      }
    }
    Set<String>? keep;
    if (focusId != null && lib.notes.containsKey(focusId)) {
      // The focused note and everything within [depth] links of it.
      keep = {focusId};
      var frontier = {focusId};
      for (var i = 0; i < depth; i++) {
        final next = <String>{};
        for (final (a, b) in pairs) {
          if (frontier.contains(a) && keep.add(b)) next.add(b);
          if (frontier.contains(b) && keep.add(a)) next.add(a);
        }
        frontier = next;
      }
    }
    final nodes = [
      for (final n in notes)
        if (keep?.contains(n.id) ??
            (includeUnlinked || (degree[n.id] ?? 0) > 0))
          n,
    ]..sort((a, b) => a.id.compareTo(b.id));
    final index = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i};
    final edges = [
      for (final (a, b) in pairs)
        if (index.containsKey(a) && index.containsKey(b))
          (index[a]!, index[b]!),
    ];
    return NoteGraph(nodes, edges);
  }
}

Future<void> showGraphView(BuildContext context, {String? focusId}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _GraphDialog(focusId: focusId),
    );

class _GraphDialog extends ConsumerStatefulWidget {
  const _GraphDialog({this.focusId});
  final String? focusId;

  @override
  ConsumerState<_GraphDialog> createState() => _GraphDialogState();
}

class _GraphDialogState extends ConsumerState<_GraphDialog> {
  bool _unlinked = false;
  late bool _local = widget.focusId != null;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lib = ref.watch(libraryProvider);
    final current = widget.focusId ?? ref.watch(openNoteIdProvider);
    final graph = NoteGraph.build(
      lib,
      includeUnlinked: _unlinked,
      focusId: _local ? current : null,
      depth: 2,
    );
    final size = MediaQuery.sizeOf(context);
    return AppDialog(
      icon: Icons.hub_outlined,
      title: context.tr('Link graph'),
      subtitle: context.tr('{n} notes, {e} links. Click a note to open it.', {
        'n': graph.nodes.length,
        'e': graph.edges.length,
      }),
      width: math.min(1100, size.width - 32),
      height: math.min(760, size.height - 48),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      headerActions: [
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(right: Sp.xs),
            child: FilterChip(
              label: Text(context.tr('Around this note')),
              selected: _local,
              onSelected: (v) => setState(() => _local = v),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: Sp.sm),
          child: FilterChip(
            label: Text(context.tr('Unlinked notes')),
            selected: _unlinked,
            onSelected: (v) => setState(() => _unlinked = v),
          ),
        ),
      ],
      content: graph.nodes.isEmpty
          ? DialogEmptyState(
              icon: Icons.hub_outlined,
              message: context.tr(
                'No links yet. Link notes with [[Note title]] to see them here.',
              ),
            )
          : ColoredBox(
              color: p.editorBg,
              child: _GraphCanvas(
                key: ValueKey('${_unlinked}_${_local}_${graph.nodes.length}'),
                graph: graph,
                currentId: current,
                notebookIds: [for (final nb in lib.notebooks) nb.id],
                onOpen: (id) {
                  Navigator.of(context).pop();
                  ref.read(openNoteProvider.notifier).open(id);
                },
              ),
            ),
    );
  }
}

class _GraphCanvas extends StatefulWidget {
  const _GraphCanvas({
    super.key,
    required this.graph,
    required this.currentId,
    required this.notebookIds,
    required this.onOpen,
  });

  final NoteGraph graph;
  final String? currentId;
  final List<String> notebookIds;
  final ValueChanged<String> onOpen;

  @override
  State<_GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<_GraphCanvas>
    with SingleTickerProviderStateMixin {
  static const double _world = 2400;
  late final List<Offset> _pos;
  late final List<Offset> _vel;
  late final List<int> _degree;
  late final Ticker _ticker;
  final _view = TransformationController();
  double _heat = 1;
  int? _hover;
  bool _centered = false;

  @override
  void initState() {
    super.initState();
    final n = widget.graph.nodes.length;
    final random = math.Random(7);
    const c = Offset(_world / 2, _world / 2);
    final spread = 60.0 * math.sqrt(n + 1);
    _pos = [
      for (var i = 0; i < n; i++)
        c +
            Offset.fromDirection(
              random.nextDouble() * math.pi * 2,
              random.nextDouble() * spread,
            ),
    ];
    _vel = List.filled(n, Offset.zero);
    _degree = List.filled(n, 0);
    for (final (a, b) in widget.graph.edges) {
      _degree[a]++;
      _degree[b]++;
    }
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _view.dispose();
    super.dispose();
  }

  /// A few steps of a force layout per frame until it settles.
  void _tick(Duration _) {
    for (var s = 0; s < 3; s++) {
      _step();
    }
    _heat *= .985;
    if (_heat < .02) _ticker.stop();
    if (mounted) setState(() {});
  }

  void _step() {
    final n = _pos.length;
    final force = List<Offset>.filled(n, Offset.zero);
    const repulsion = 9000.0;
    const spring = .02;
    const length = 110.0;
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        var d = _pos[i] - _pos[j];
        var dist2 = d.distanceSquared;
        if (dist2 < 1) {
          d = Offset(i.toDouble() - j, 1);
          dist2 = d.distanceSquared;
        }
        if (dist2 > 600 * 600) continue;
        final f = d / math.sqrt(dist2) * (repulsion / dist2);
        force[i] += f;
        force[j] -= f;
      }
    }
    for (final (a, b) in widget.graph.edges) {
      final d = _pos[b] - _pos[a];
      final dist = math.max(d.distance, .01);
      final f = d / dist * ((dist - length) * spring);
      force[a] += f;
      force[b] -= f;
    }
    const center = Offset(_world / 2, _world / 2);
    for (var i = 0; i < n; i++) {
      force[i] += (center - _pos[i]) * .004;
      _vel[i] = (_vel[i] + force[i]) * .6;
      final step = _vel[i];
      final limit = 30 * _heat + 1;
      _pos[i] += step.distance > limit ? step / step.distance * limit : step;
    }
  }

  double _radius(int i) => 6 + math.min(14, _degree[i] * 2.0);

  int? _hit(Offset local) {
    for (var i = _pos.length - 1; i >= 0; i--) {
      if ((_pos[i] - local).distance <= _radius(i) + 4) return i;
    }
    return null;
  }

  void _center(Size viewport) {
    if (_centered || _pos.isEmpty) return;
    _centered = true;
    final current = widget.graph.nodes.indexWhere(
      (n) => n.id == widget.currentId,
    );
    final focus = current >= 0
        ? _pos[current]
        : const Offset(_world / 2, _world / 2);
    _view.value = Matrix4.translationValues(
      viewport.width / 2 - focus.dx,
      viewport.height / 2 - focus.dy,
      0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return LayoutBuilder(
      builder: (context, constraints) {
        _center(constraints.biggest);
        return InteractiveViewer(
          transformationController: _view,
          constrained: false,
          minScale: .2,
          maxScale: 3,
          boundaryMargin: const EdgeInsets.all(_world),
          child: MouseRegion(
            cursor: _hover == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onHover: (e) {
              final hit = _hit(e.localPosition);
              if (hit != _hover) setState(() => _hover = hit);
            },
            onExit: (_) => setState(() => _hover = null),
            child: GestureDetector(
              onTapUp: (d) {
                final hit = _hit(d.localPosition);
                if (hit != null) widget.onOpen(widget.graph.nodes[hit].id);
              },
              child: CustomPaint(
                size: const Size(_world, _world),
                painter: _GraphPainter(
                  graph: widget.graph,
                  positions: _pos,
                  radius: _radius,
                  hover: _hover,
                  currentId: widget.currentId,
                  notebookIds: widget.notebookIds,
                  palette: p,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.graph,
    required this.positions,
    required this.radius,
    required this.hover,
    required this.currentId,
    required this.notebookIds,
    required this.palette,
  });

  final NoteGraph graph;
  final List<Offset> positions;
  final double Function(int) radius;
  final int? hover;
  final String? currentId;
  final List<String> notebookIds;
  final AppPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final p = palette;
    final neighbours = <int>{};
    if (hover != null) {
      for (final (a, b) in graph.edges) {
        if (a == hover) neighbours.add(b);
        if (b == hover) neighbours.add(a);
      }
    }
    final dim = hover != null;
    final edge = Paint()..strokeWidth = 1.2;
    for (final (a, b) in graph.edges) {
      final lit = a == hover || b == hover;
      edge.color = lit
          ? p.accent.withValues(alpha: .9)
          : p.textFaint.withValues(alpha: dim ? .12 : .35);
      canvas.drawLine(positions[a], positions[b], edge);
    }
    final many = graph.nodes.length > 60;
    for (var i = 0; i < graph.nodes.length; i++) {
      final note = graph.nodes[i];
      final current = note.id == currentId;
      final lit = i == hover || neighbours.contains(i) || !dim;
      final nb = notebookIds.indexOf(note.notebookId ?? '');
      final base = current
          ? p.accent
          : AppPalette.tagColors[(nb < 0 ? 0 : nb) %
                AppPalette.tagColors.length];
      final r = radius(i);
      canvas.drawCircle(
        positions[i],
        r,
        Paint()..color = base.withValues(alpha: lit ? 1 : .25),
      );
      if (current || i == hover) {
        canvas.drawCircle(
          positions[i],
          r + 3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = p.text.withValues(alpha: .8),
        );
      }
      // Labels for everything in small graphs; otherwise only for the
      // hovered note, its neighbours, hubs and the current note.
      final label =
          !many || i == hover || neighbours.contains(i) || current || r >= 14;
      if (!label) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: note.displayTitle,
          style: TextStyle(
            color: p.text.withValues(alpha: lit ? .95 : .3),
            fontSize: i == hover ? Fs.small + 1 : Fs.small,
            fontWeight: i == hover || current
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 180);
      tp.paint(canvas, positions[i] + Offset(-tp.width / 2, r + 4));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
