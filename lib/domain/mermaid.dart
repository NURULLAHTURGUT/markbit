/// Parsers for the Mermaid diagrams the preview draws natively: flowcharts
/// (`flowchart` / `graph`) and sequence diagrams. Mindmap, pie and xychart
/// are converted to visual blocks elsewhere.
library;

sealed class MermaidDiagram {
  const MermaidDiagram();

  /// Returns null for syntax this app does not draw (shown as source).
  static MermaidDiagram? parse(String source) {
    final lines = _clean(source);
    if (lines.isEmpty) return null;
    final head = lines.first.trim();
    if (RegExp(r'^(flowchart|graph)\b', caseSensitive: false).hasMatch(head)) {
      return Flowchart.parse(lines);
    }
    if (RegExp(r'^sequenceDiagram\b').hasMatch(head)) {
      return SequenceDiagram.parse(lines);
    }
    return null;
  }

  static List<String> _clean(String source) => [
    for (final raw in source.split('\n'))
      if (raw.replaceFirst(RegExp(r'%%.*$'), '').trim() case final l
          when l.isNotEmpty)
        l,
  ];
}

// ------------------------------------------------------------------ flowchart

enum FlowDirection { topDown, bottomUp, leftRight, rightLeft }

enum FlowShape {
  rect,
  round,
  stadium,
  circle,
  diamond,
  hexagon,
  database,
  subroutine,
  flag,
  parallelogram,
}

class FlowNode {
  FlowNode(this.id, this.label, this.shape);
  final String id;
  String label;
  FlowShape shape;
}

enum FlowLine { solid, dotted, thick, invisible }

class FlowEdge {
  const FlowEdge(
    this.from,
    this.to, {
    this.label = '',
    this.line = FlowLine.solid,
    this.arrow = true,
    this.arrowBack = false,
  });
  final String from;
  final String to;
  final String label;
  final FlowLine line;
  final bool arrow;
  final bool arrowBack;
}

class Flowchart extends MermaidDiagram {
  Flowchart(this.direction, this.nodes, this.edges);
  final FlowDirection direction;

  /// In order of first appearance.
  final List<FlowNode> nodes;
  final List<FlowEdge> edges;

  bool get horizontal =>
      direction == FlowDirection.leftRight ||
      direction == FlowDirection.rightLeft;

  // Shapes, longest delimiters first so `((` wins over `(`.
  static const _shapes = <(String, String, FlowShape)>[
    ('(((', ')))', FlowShape.circle),
    ('((', '))', FlowShape.circle),
    ('([', '])', FlowShape.stadium),
    ('[[', ']]', FlowShape.subroutine),
    ('[(', ')]', FlowShape.database),
    ('{{', '}}', FlowShape.hexagon),
    ('[/', '/]', FlowShape.parallelogram),
    ('[\\', '\\]', FlowShape.parallelogram),
    ('[/', '\\]', FlowShape.parallelogram),
    ('[', ']', FlowShape.rect),
    ('(', ')', FlowShape.round),
    ('{', '}', FlowShape.diamond),
    ('>', ']', FlowShape.flag),
  ];

  static final _id = RegExp(r'[A-Za-z0-9_À-ɏЀ-ӿ.]+');
  static final _edge = RegExp(
    r'\s*(<)?(?:'
    // -- text -->, == text ==>, -. text .->
    r'(--|==|-\.)\s*([^\s>|-][^>|]*?)\s*(-->|==>|\.->|---|===|\.-)'
    r'|'
    r'(-{2,}>|={2,}>|-\.+->|-{3,}|={3,}|-\.+-|~~~|--[xo]|==[xo]|-\.+-?[xo])'
    r')\s*(?:\|([^|]*)\|)?\s*',
  );

  static Flowchart? parse(List<String> lines) {
    final header = lines.first.trim().split(RegExp(r'\s+'));
    final dir = switch (header.length > 1 ? header[1].toUpperCase() : 'TD') {
      'LR' => FlowDirection.leftRight,
      'RL' => FlowDirection.rightLeft,
      'BT' => FlowDirection.bottomUp,
      _ => FlowDirection.topDown,
    };
    final nodes = <String, FlowNode>{};
    final edges = <FlowEdge>[];

    FlowNode node(String id, String? label, FlowShape? shape) {
      final existing = nodes[id];
      if (existing != null) {
        if (label != null) {
          existing.label = label;
          existing.shape = shape ?? existing.shape;
        }
        return existing;
      }
      return nodes[id] = FlowNode(id, label ?? id, shape ?? FlowShape.rect);
    }

    // Reads `id`, `id[label]`, `id(label)`... at [at]; returns the ids read
    // (several with `&`) and the position after them.
    (List<String>, int)? readNodes(String s, int at) {
      final ids = <String>[];
      var i = at;
      while (true) {
        final m = _id.matchAsPrefix(s, i);
        if (m == null) return ids.isEmpty ? null : (ids, i);
        final id = m[0]!;
        i = m.end;
        String? label;
        FlowShape? shape;
        for (final (open, close, kind) in _shapes) {
          if (!s.startsWith(open, i)) continue;
          final end = s.indexOf(close, i + open.length);
          if (end < 0) continue;
          label = s.substring(i + open.length, end).trim();
          if (label.length >= 2 &&
              label.startsWith('"') &&
              label.endsWith('"')) {
            label = label.substring(1, label.length - 1);
          }
          shape = kind;
          i = end + close.length;
          break;
        }
        node(
          id,
          label?.replaceAll('<br>', '\n').replaceAll('<br/>', '\n'),
          shape,
        );
        ids.add(id);
        final amp = RegExp(r'\s*&\s*').matchAsPrefix(s, i);
        if (amp == null) return (ids, i);
        i = amp.end;
      }
    }

    for (final raw in lines.skip(1)) {
      for (var statement in raw.split(';')) {
        statement = statement.trim();
        if (statement.isEmpty ||
            RegExp(
              r'^(classDef|class|style|linkStyle|click|subgraph|end|direction)\b',
            ).hasMatch(statement)) {
          continue;
        }
        var first = readNodes(statement, 0);
        if (first == null) continue;
        var at = first.$2;
        while (at < statement.length) {
          final e = _edge.matchAsPrefix(statement, at);
          if (e == null) break;
          final next = readNodes(statement, e.end);
          if (next == null) break;
          final token = e[4] ?? e[5] ?? '';
          final label = (e[3] ?? e[6] ?? '').trim();
          final line = token.contains('=')
              ? FlowLine.thick
              : token.contains('.')
              ? FlowLine.dotted
              : token == '~~~'
              ? FlowLine.invisible
              : FlowLine.solid;
          final arrow = token.endsWith('>');
          for (final a in first!.$1) {
            for (final b in next.$1) {
              edges.add(
                FlowEdge(
                  a,
                  b,
                  label: label.replaceAll('"', ''),
                  line: line,
                  arrow: arrow,
                  arrowBack: e[1] != null,
                ),
              );
            }
          }
          first = next;
          at = next.$2;
        }
      }
    }
    if (nodes.isEmpty) return null;
    return Flowchart(dir, nodes.values.toList(), edges);
  }
}

// ------------------------------------------------------------------ sequence

class SeqParticipant {
  SeqParticipant(this.id, this.label, {this.actor = false});
  final String id;
  String label;
  bool actor;
}

sealed class SeqItem {
  const SeqItem();
}

class SeqMessage extends SeqItem {
  const SeqMessage(
    this.from,
    this.to,
    this.text, {
    this.dashed = false,
    this.arrow = SeqArrow.filled,
    this.number,
  });
  final String from;
  final String to;
  final String text;
  final bool dashed;
  final SeqArrow arrow;
  final int? number;
}

enum SeqArrow { filled, open, cross, async }

enum NotePlacement { left, right, over }

class SeqNote extends SeqItem {
  const SeqNote(this.placement, this.participants, this.text);
  final NotePlacement placement;
  final List<String> participants;
  final String text;
}

/// `loop`, `alt`, `opt`, `par`, `critical`, `break`, `rect` and their
/// `else`/`and` sections.
class SeqBlockStart extends SeqItem {
  const SeqBlockStart(this.kind, this.label);
  final String kind;
  final String label;
}

class SeqBlockSection extends SeqItem {
  const SeqBlockSection(this.label);
  final String label;
}

class SeqBlockEnd extends SeqItem {
  const SeqBlockEnd();
}

class SequenceDiagram extends MermaidDiagram {
  SequenceDiagram(this.participants, this.items);
  final List<SeqParticipant> participants;
  final List<SeqItem> items;

  static final _participant = RegExp(
    r'^(participant|actor)\s+(.+?)(?:\s+as\s+(.+))?$',
  );
  static final _message = RegExp(
    r'^(.+?)\s*(-->>|->>|-->|->|--x|-x|--\)|-\))\s*[+-]?\s*(.+?)\s*:\s*(.*)$',
  );
  static final _note = RegExp(
    r'^note\s+(left of|right of|over)\s+([^:]+):\s*(.*)$',
    caseSensitive: false,
  );
  static final _block = RegExp(
    r'^(loop|alt|opt|par|critical|break|rect)\b\s*(.*)$',
  );
  static final _section = RegExp(r'^(else|and|option)\b\s*(.*)$');

  static SequenceDiagram? parse(List<String> lines) {
    final participants = <String, SeqParticipant>{};
    SeqParticipant ensure(String id) =>
        participants[id] ??= SeqParticipant(id, id);
    final items = <SeqItem>[];
    var numbering = false;
    var number = 0;
    var depth = 0;
    for (final raw in lines.skip(1)) {
      final line = raw.trim();
      if (line == 'autonumber' || line.startsWith('autonumber ')) {
        numbering = true;
        continue;
      }
      if (RegExp(
        r'^(activate|deactivate|title|box|links?|create|destroy)\b',
      ).hasMatch(line)) {
        continue;
      }
      final p = _participant.firstMatch(line);
      if (p != null) {
        final part = ensure(p[2]!.trim());
        if (p[3] != null) part.label = p[3]!.trim();
        part.actor = p[1] == 'actor';
        continue;
      }
      final note = _note.firstMatch(line);
      if (note != null) {
        final who = note[2]!.split(',').map((e) => e.trim()).toList();
        who.forEach(ensure);
        items.add(
          SeqNote(
            switch (note[1]!.toLowerCase()) {
              'left of' => NotePlacement.left,
              'right of' => NotePlacement.right,
              _ => NotePlacement.over,
            },
            who,
            _text(note[3]!),
          ),
        );
        continue;
      }
      final block = _block.firstMatch(line);
      if (block != null) {
        depth++;
        items.add(SeqBlockStart(block[1]!, _text(block[2]!)));
        continue;
      }
      final section = _section.firstMatch(line);
      if (section != null && depth > 0) {
        items.add(SeqBlockSection(_text(section[2]!)));
        continue;
      }
      if (line == 'end') {
        if (depth > 0) {
          depth--;
          items.add(const SeqBlockEnd());
        }
        continue;
      }
      final m = _message.firstMatch(line);
      if (m != null) {
        final from = ensure(m[1]!.trim()).id;
        final to = ensure(m[3]!.trim()).id;
        final kind = m[2]!;
        items.add(
          SeqMessage(
            from,
            to,
            _text(m[4]!),
            dashed: kind.startsWith('--'),
            arrow: kind.endsWith('>>')
                ? SeqArrow.filled
                : kind.endsWith('x')
                ? SeqArrow.cross
                : kind.endsWith(')')
                ? SeqArrow.async
                : SeqArrow.open,
            number: numbering ? ++number : null,
          ),
        );
      }
    }
    while (depth-- > 0) {
      items.add(const SeqBlockEnd());
    }
    if (participants.isEmpty) return null;
    return SequenceDiagram(participants.values.toList(), items);
  }

  static String _text(String s) =>
      s.trim().replaceAll('<br>', '\n').replaceAll('<br/>', '\n');
}
