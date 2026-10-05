import 'dart:math' as math;

import '../data/models/note.dart';

/// Lower-cases and strips Turkish and common Latin diacritics one character
/// at a time, so "Görev", "GOREV" and "görev" compare equal and every index
/// in the folded string matches the same index in the original (needed for
/// highlighting).
String foldSearch(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    final c = String.fromCharCode(rune);
    final mapped = _fold[c];
    if (mapped != null) {
      out.write(mapped);
      continue;
    }
    final lower = c.toLowerCase();
    // Keep the length stable: multi-character lowercase forms are rare and
    // would shift highlight positions.
    out.write(lower.length == c.length ? lower : c);
  }
  return out.toString();
}

const _fold = {
  'İ': 'i', 'I': 'i', 'ı': 'i', 'Î': 'i', 'î': 'i', //
  'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g', 'Ç': 'c', 'ç': 'c', //
  'Ü': 'u', 'ü': 'u', 'Û': 'u', 'û': 'u', 'Ö': 'o', 'ö': 'o', //
  'Â': 'a', 'â': 'a', 'Ä': 'a', 'ä': 'a', 'É': 'e', 'é': 'e', //
  'È': 'e', 'è': 'e', 'Á': 'a', 'á': 'a', 'Ñ': 'n', 'ñ': 'n',
};

class _SearchText {
  _SearchText(Note note)
    : title = foldSearch(note.title),
      body = foldSearch(note.body);
  final String title;
  final String body;
  Set<String>? _words;

  /// Distinct words (3+ letters) of title and body, for typo tolerance.
  Set<String> get words => _words ??= {
    for (final m in _word.allMatches('$title\n$body'))
      if (m.end - m.start >= 3) m[0]!,
  };
  static final _word = RegExp(r'[\p{L}\p{N}_]+', unicode: true);
}

/// A date filter such as `updated:>2026-09-01` or `created:today`.
class _DateRange {
  const _DateRange(this.field, this.from, this.to);
  final String field; // created | updated
  final DateTime? from; // inclusive
  final DateTime? to; // exclusive

  bool contains(Note note) {
    final value = field == 'created' ? note.createdAt : note.updatedAt;
    if (from != null && value.isBefore(from!)) return false;
    if (to != null && !value.isBefore(to!)) return false;
    return true;
  }

  static _DateRange? parse(String field, String raw, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    var op = '';
    var value = raw;
    for (final candidate in ['>=', '<=', '>', '<', '=']) {
      if (value.startsWith(candidate)) {
        op = candidate;
        value = value.substring(candidate.length);
        break;
      }
    }
    // Relative periods mean "within the last ...".
    final relative = switch (value) {
      'today' || 'bugun' => (today, today.add(const Duration(days: 1))),
      'yesterday' || 'dun' => (today.subtract(const Duration(days: 1)), today),
      'week' || 'hafta' => (today.subtract(const Duration(days: 6)), null),
      'month' || 'ay' => (today.subtract(const Duration(days: 29)), null),
      'year' || 'yil' => (today.subtract(const Duration(days: 364)), null),
      _ => null,
    };
    if (relative != null && op.isEmpty) {
      return _DateRange(field, relative.$1, relative.$2);
    }
    final span = RegExp(r'^(\d+)([dwmy])$').firstMatch(value);
    if (span != null) {
      final n = int.parse(span[1]!);
      final days = switch (span[2]) {
        'd' => n,
        'w' => n * 7,
        'm' => n * 30,
        _ => n * 365,
      };
      final start = today.subtract(Duration(days: math.max(0, days - 1)));
      // "<7d" means older than that; anything else means within it.
      return op.startsWith('<')
          ? _DateRange(field, null, start)
          : _DateRange(field, start, null);
    }
    final date = DateTime.tryParse(value);
    final day = date == null
        ? relative?.$1
        : DateTime(date.year, date.month, date.day);
    if (day == null) return null;
    final next = day.add(const Duration(days: 1));
    return switch (op) {
      '>' => _DateRange(field, next, null),
      '>=' => _DateRange(field, day, null),
      '<' => _DateRange(field, null, day),
      '<=' => _DateRange(field, null, next),
      _ => _DateRange(field, day, next),
    };
  }
}

/// One condition of a query: free text or a `key:value` filter.
class _Atom {
  _Atom(this.key, this.value, {this.negated = false, this.phrase = false});
  final String? key;
  final String value;
  final bool negated;

  /// Quoted text: matched exactly, never fuzzily.
  final bool phrase;
  _DateRange? date;

  bool get isText => key == null;
}

/// Parsed note search query.
///
/// * Free text: every word must appear in the title, body or a tag. Words of
///   four or more letters tolerate one typo (two from eight letters). Quote a
///   phrase for an exact match: `"release notes"`.
/// * Filters: `tag:x`, `notebook:x`, `status:active`, `kind:code`,
///   `lang:python`, `is:pinned|starred|locked`, `has:code|tasks|images`,
///   `created:` / `updated:` with a date (`2026-09-01`, `>2026-09-01`,
///   `<=2026-09-01`) or a period (`today`, `yesterday`, `week`, `month`,
///   `7d`, `2w`, `3m`, `<30d` for older than 30 days).
/// * `-word` or `-tag:x` excludes; `a OR b` (or `a | b`) matches either.
///
/// Matching ignores case and Turkish/Latin diacritics.
class SearchQuery {
  static final _index = Expando<_SearchText>('search text');

  SearchQuery._(this._clauses);

  /// AND of OR-groups.
  final List<List<_Atom>> _clauses;

  bool get isEmpty => _clauses.isEmpty;

  /// Whether ranking by relevance makes sense (positive free text).
  bool get hasTerms =>
      _clauses.any((c) => c.any((a) => a.isText && !a.negated));

  /// Positive free-text terms (folded), used for highlighting.
  List<String> get terms => [
    for (final c in _clauses)
      for (final a in c)
        if (a.isText && !a.negated) a.value,
  ];

  static final RegExp _token = RegExp(
    r'(-)?(?:([A-Za-z]+):)?(?:"([^"]*)"?|(\S+))',
  );

  factory SearchQuery.parse(String raw, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final clauses = <List<_Atom>>[];
    var joinNext = false;
    for (final m in _token.allMatches(raw)) {
      final whole = m[0]!;
      if (whole == 'OR' || whole == '|' || whole == 'VEYA') {
        joinNext = clauses.isNotEmpty;
        continue;
      }
      final negated = m[1] != null;
      var key = m[2]?.toLowerCase();
      final quoted = m[3] != null;
      final value = foldSearch((m[3] ?? m[4] ?? '').trim());
      if (value.isEmpty || (negated && value == '-')) continue;
      key = switch (key) {
        'nb' => 'notebook',
        'type' => 'kind',
        'language' => 'lang',
        'etiket' => 'tag',
        'defter' => 'notebook',
        'durum' => 'status',
        null => null,
        _ => key,
      };
      _Atom atom;
      if (key == 'created' || key == 'updated') {
        atom = _Atom(key, value, negated: negated);
        atom.date = _DateRange.parse(key!, value, clock);
        if (atom.date == null) {
          atom = _Atom(null, '$key:$value', negated: negated, phrase: true);
        }
      } else if (const {
        'tag', 'notebook', 'status', 'kind', 'lang', 'is', 'has', //
      }.contains(key)) {
        atom = _Atom(
          key,
          key == 'status' ? value.replaceAll(RegExp(r'[\s_-]'), '') : value,
          negated: negated,
        );
      } else {
        // Unknown operator: the whole token is plain text.
        atom = _Atom(
          null,
          key == null ? value : '$key:$value',
          negated: negated,
          phrase: quoted || key != null,
        );
      }
      if (joinNext && clauses.isNotEmpty) {
        clauses.last.add(atom);
      } else {
        clauses.add([atom]);
      }
      joinNext = false;
    }
    return SearchQuery._(clauses);
  }

  /// Returns a relevance score (>= 0) when [note] matches, otherwise `-1`.
  int match(
    Note note, {
    required List<String> tagNames,
    required String? notebookName,
  }) {
    if (isEmpty) return 0;
    final indexed = _index[note] ??= _SearchText(note);
    final tags = [for (final t in tagNames) foldSearch(t)];
    final notebook = notebookName == null ? null : foldSearch(notebookName);
    var score = 1;
    for (final clause in _clauses) {
      var best = -1;
      for (final atom in clause) {
        final s = _score(atom, note, indexed, tags, notebook);
        final hit = atom.negated ? (s < 0 ? 0 : -1) : s;
        if (hit > best) best = hit;
      }
      if (best < 0) return -1;
      score += best;
    }
    if (hasTerms &&
        DateTime.now().difference(note.updatedAt) < const Duration(days: 7)) {
      score += 2;
    }
    return score;
  }

  /// Score of one positive atom, or -1 when it does not match.
  int _score(
    _Atom a,
    Note note,
    _SearchText text,
    List<String> tags,
    String? notebook,
  ) {
    final v = a.value;
    switch (a.key) {
      case 'tag':
        return tags.any((n) => n.contains(v)) ? 1 : -1;
      case 'notebook':
        return (notebook?.contains(v) ?? false) ? 1 : -1;
      case 'status':
        return foldSearch(note.status.name) == v ? 1 : -1;
      case 'kind':
        return note.kind.name == v ? 1 : -1;
      case 'lang':
        final own = note.language?.toLowerCase();
        return own == v || text.body.contains('```$v') ? 1 : -1;
      case 'is':
        final ok = switch (v) {
          'pinned' || 'sabit' => note.pinned,
          'starred' || 'favorite' || 'yildizli' => note.starred,
          'locked' || 'kilitli' => note.isLocked,
          'trashed' => note.trashed,
          _ => false,
        };
        return ok ? 1 : -1;
      case 'has':
        final ok = switch (v) {
          'code' => note.kind == NoteKind.code || text.body.contains('```'),
          'tasks' => RegExp(r'\[[ x]\]').hasMatch(text.body),
          'images' => note.images.isNotEmpty || text.body.contains('!['),
          'cover' => note.coverImage != null,
          _ => false,
        };
        return ok ? 1 : -1;
      case 'created' || 'updated':
        return a.date!.contains(note) ? 1 : -1;
    }
    return _textScore(v, text, tags, fuzzy: !a.phrase);
  }

  int _textScore(
    String term,
    _SearchText text,
    List<String> tags, {
    required bool fuzzy,
  }) {
    var score = 0;
    final title = text.title;
    if (title == term) {
      score += 30;
    } else if (RegExp('(^|\\W)${RegExp.escape(term)}').hasMatch(title)) {
      score += title.startsWith(term) ? 16 : 12;
    } else if (title.contains(term)) {
      score += 8;
    }
    if (tags.any((t) => t == term)) {
      score += 8;
    } else if (tags.any((t) => t.contains(term))) {
      score += 4;
    }
    final hits = _count(text.body, term, 5);
    if (hits > 0) score += 1 + hits;
    if (score > 0) return score;
    if (!fuzzy || term.length < 4 || term.contains(' ')) return -1;
    final limit = term.length >= 8 ? 2 : 1;
    for (final word in text.words) {
      if ((word.length - term.length).abs() > limit) continue;
      if (_distance(term, word, limit) <= limit) {
        return title.contains(word) ? 4 : 1;
      }
    }
    return -1;
  }

  /// Words of [note] that matched the query, for highlighting: the terms
  /// themselves plus words that matched one of them with a typo.
  Set<String> highlightWords(Note note) {
    final words = terms.where((t) => t.length >= 2).toSet();
    if (words.isEmpty) return words;
    final indexed = _index[note] ??= _SearchText(note);
    for (final term in words.toList()) {
      if (term.length < 4 ||
          indexed.title.contains(term) ||
          indexed.body.contains(term)) {
        continue;
      }
      final limit = term.length >= 8 ? 2 : 1;
      for (final word in indexed.words) {
        if ((word.length - term.length).abs() <= limit &&
            _distance(term, word, limit) <= limit) {
          words.add(word);
        }
      }
    }
    return words;
  }

  static int _count(String text, String term, int cap) {
    var n = 0;
    var i = text.indexOf(term);
    while (i >= 0 && n < cap) {
      n++;
      i = text.indexOf(term, i + term.length);
    }
    return n;
  }

  /// Optimal string alignment distance, stopping early above [limit].
  static int _distance(String a, String b, int limit) {
    final n = a.length, m = b.length;
    var prev2 = List<int>.filled(m + 1, 0);
    var prev = List<int>.generate(m + 1, (j) => j);
    for (var i = 1; i <= n; i++) {
      final cur = List<int>.filled(m + 1, 0)..[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= m; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = math.min(
          math.min(prev[j] + 1, cur[j - 1] + 1),
          prev[j - 1] + cost,
        );
        if (i > 1 &&
            j > 1 &&
            a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
            a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1)) {
          v = math.min(v, prev2[j - 2] + 1);
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > limit) return limit + 1;
      prev2 = prev;
      prev = cur;
    }
    return prev[m];
  }
}

/// Ranges of [text] that contain one of [words] (already folded).
List<(int, int)> highlightRanges(String text, Iterable<String> words) {
  if (words.isEmpty || text.isEmpty) return const [];
  final folded = foldSearch(text);
  if (folded.length != text.length) return const [];
  final ranges = <(int, int)>[];
  for (final w in words) {
    if (w.isEmpty) continue;
    var i = folded.indexOf(w);
    while (i >= 0) {
      ranges.add((i, i + w.length));
      i = folded.indexOf(w, i + w.length);
    }
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in ranges) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, math.max(last.$2, r.$2)));
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// A short plain-text excerpt of [body] around the first occurrence of one
/// of [words], or null when none occurs.
String? snippetAround(String body, Iterable<String> words, {int max = 150}) {
  if (words.isEmpty) return null;
  final lines = body.split('\n');
  for (final raw in lines) {
    final folded = foldSearch(raw);
    final hit = words
        .map((w) => (w, folded.indexOf(w)))
        .where((e) => e.$2 >= 0)
        .fold<(String, int)?>(
          null,
          (best, e) => best == null || e.$2 < best.$2 ? e : best,
        );
    if (hit == null) continue;
    var line = raw
        .replaceFirst(RegExp(r'^\s*#{1,6}\s+'), '')
        .replaceFirst(RegExp(r'^\s*>\s?'), '')
        .replaceFirst(RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?'), '')
        .replaceAll(RegExp(r'[*_`~]'), '')
        .replaceAll(RegExp(r'\[\[id:[^|\]]*\|'), '[[')
        .trim();
    if (line.isEmpty) continue;
    final at = foldSearch(line).indexOf(hit.$1);
    if (line.length <= max || at < 0) {
      return line.length <= max ? line : '${line.substring(0, max)}…';
    }
    var start = math.max(0, at - max ~/ 3);
    final end = math.min(line.length, start + max);
    start = math.max(0, end - max);
    return '${start > 0 ? '…' : ''}${line.substring(start, end).trim()}'
        '${end < line.length ? '…' : ''}';
  }
  return null;
}
