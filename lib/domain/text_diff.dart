/// Line-based text diff (Myers' O((N+M)D) algorithm) for version history.
library;

enum DiffKind { same, added, removed }

class DiffLine {
  const DiffLine(this.kind, this.text, {this.oldLine, this.newLine});
  final DiffKind kind;
  final String text;

  /// 1-based line numbers in the old / new text (null when absent).
  final int? oldLine;
  final int? newLine;
}

class TextDiff {
  const TextDiff(this.lines);
  final List<DiffLine> lines;

  int get added => lines.where((l) => l.kind == DiffKind.added).length;
  int get removed => lines.where((l) => l.kind == DiffKind.removed).length;
  bool get isEmpty => added == 0 && removed == 0;

  factory TextDiff.of(String before, String after) {
    final a = before.split('\n'), b = after.split('\n');
    // Common prefix and suffix need no search.
    var start = 0;
    while (start < a.length && start < b.length && a[start] == b[start]) {
      start++;
    }
    var endA = a.length, endB = b.length;
    while (endA > start && endB > start && a[endA - 1] == b[endB - 1]) {
      endA--;
      endB--;
    }
    final out = <DiffLine>[
      for (var i = 0; i < start; i++)
        DiffLine(DiffKind.same, a[i], oldLine: i + 1, newLine: i + 1),
    ];
    final middle = _myers(a.sublist(start, endA), b.sublist(start, endB));
    var oi = start, ni = start;
    for (final kind in middle) {
      switch (kind) {
        case DiffKind.same:
          out.add(DiffLine(kind, a[oi], oldLine: ++oi, newLine: ++ni));
        case DiffKind.removed:
          out.add(DiffLine(kind, a[oi], oldLine: ++oi));
        case DiffKind.added:
          out.add(DiffLine(kind, b[ni], newLine: ++ni));
      }
    }
    for (var i = 0; i < a.length - endA; i++) {
      out.add(
        DiffLine(
          DiffKind.same,
          a[endA + i],
          oldLine: endA + i + 1,
          newLine: endB + i + 1,
        ),
      );
    }
    return TextDiff(out);
  }

  /// Edit script turning [a] into [b]; removals come before additions
  /// within a changed block.
  static List<DiffKind> _myers(List<String> a, List<String> b) {
    final n = a.length, m = b.length;
    if (n == 0) return List.filled(m, DiffKind.added);
    if (m == 0) return List.filled(n, DiffKind.removed);
    final max = n + m;
    final offset = max;
    var v = List<int>.filled(2 * max + 2, 0);
    final trace = <List<int>>[];
    var found = false;
    for (var d = 0; d <= max && !found; d++) {
      trace.add(List<int>.of(v));
      for (var k = -d; k <= d; k += 2) {
        var x = (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]))
            ? v[offset + k + 1]
            : v[offset + k - 1] + 1;
        var y = x - k;
        while (x < n && y < m && a[x] == b[y]) {
          x++;
          y++;
        }
        v[offset + k] = x;
        if (x >= n && y >= m) {
          found = true;
          break;
        }
      }
    }
    // Walk the trace backwards to recover the path.
    final script = <DiffKind>[];
    var x = n, y = m;
    for (var d = trace.length - 1; d >= 0; d--) {
      final vd = trace[d];
      final k = x - y;
      final prevK =
          (k == -d || (k != d && vd[offset + k - 1] < vd[offset + k + 1]))
          ? k + 1
          : k - 1;
      final prevX = vd[offset + prevK];
      final prevY = prevX - prevK;
      while (x > prevX && y > prevY) {
        script.add(DiffKind.same);
        x--;
        y--;
      }
      if (d > 0) {
        script.add(x == prevX ? DiffKind.added : DiffKind.removed);
      }
      x = prevX;
      y = prevY;
    }
    return script.reversed.toList();
  }
}

/// Character range of [line] that differs from [other] (common prefix and
/// suffix removed), for highlighting inside a changed line.
(int, int) changedSpan(String line, String other) {
  var start = 0;
  while (start < line.length &&
      start < other.length &&
      line.codeUnitAt(start) == other.codeUnitAt(start)) {
    start++;
  }
  var end = line.length, otherEnd = other.length;
  while (end > start &&
      otherEnd > start &&
      line.codeUnitAt(end - 1) == other.codeUnitAt(otherEnd - 1)) {
    end--;
    otherEnd--;
  }
  return (start, end);
}
