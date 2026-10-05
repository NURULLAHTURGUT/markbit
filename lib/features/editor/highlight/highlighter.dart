import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../domain/languages.dart';

enum Tok {
  keyword,
  string,
  number,
  comment,
  type,
  function,
  heading,
  link,
  marker,
  bold,
  italic,
  quote,
}

class Token {
  const Token(this.start, this.end, this.tok);
  final int start;
  final int end;
  final Tok tok;
}

Set<String> _kw(String words) =>
    words.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

class _Spec {
  _Spec({
    required String keywords,
    String builtins = '',
    this.lineComment,
    this.blockComment = false,
    this.tripleQuotes = false,
    this.backtick = false,
    this.annotations = false,
    this.preprocessor = false,
    this.caseInsensitive = false,
    this.singleQuote = true,
    this.extras = const [],
    this.identifiers = true,
  }) : keywords = _kw(keywords),
       builtins = _kw(builtins);

  final Set<String> keywords;
  final Set<String> builtins;
  final String? lineComment; // regex source for the comment start, e.g. r'//'
  final bool blockComment;
  final bool tripleQuotes;
  final bool backtick;
  final bool annotations;
  final bool preprocessor;
  final bool caseInsensitive;
  final bool singleQuote;
  final List<(String, Tok)> extras;
  final bool identifiers;

  late final _Compiled compiled = _compile();

  _Compiled _compile() {
    final parts = <(String, Tok?)>[];
    if (blockComment) {
      parts.add((r'/\*[\s\S]*?(?:\*/|(?![\s\S]))', Tok.comment));
    }
    if (tripleQuotes) {
      parts.add((r'"""[\s\S]*?(?:"""|(?![\s\S]))', Tok.string));
      parts.add((r"'''[\s\S]*?(?:'''|(?![\s\S]))", Tok.string));
    }
    if (lineComment != null) parts.add(('$lineComment[^\\n]*', Tok.comment));
    if (preprocessor) parts.add((r'^[ \t]*#[ \t]*\w+', Tok.keyword));
    for (final e in extras) {
      parts.add((e.$1, e.$2));
    }
    if (backtick) parts.add((r'`(?:\\[\s\S]|[^`\\])*`?', Tok.string));
    parts.add((r'"(?:\\.|[^"\\\n])*"?', Tok.string));
    if (singleQuote) parts.add((r"'(?:\\.|[^'\\\n])*'?", Tok.string));
    if (annotations) parts.add((r'@[A-Za-z_]\w*', Tok.function));
    parts.add((
      r'\b0[xX][0-9a-fA-F_]+\b|\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?[fFlLuU]*\b',
      Tok.number,
    ));
    if (identifiers) parts.add((r'[A-Za-z_$][\w$]*', null));

    final source = parts.map((p) => '(${p.$1})').join('|');
    return _Compiled(
      RegExp(source, multiLine: true),
      parts.map((p) => p.$2).toList(growable: false),
    );
  }
}

class _Compiled {
  _Compiled(this.regex, this.kinds);
  final RegExp regex;

  /// Token kind per capture group; `null` means "identifier".
  final List<Tok?> kinds;
}

final Map<String, _Spec> _specs = _buildSpecs();

Map<String, _Spec> _buildSpecs() {
  final jsKw =
      'async await break case catch class const continue debugger default delete do else '
      'export extends finally for from function if import in instanceof let new of return static '
      'super switch this throw try typeof var void while with yield null undefined true false';
  final jsBuiltins =
      'console Math JSON Promise Array Object String Number Boolean Map Set Date '
      'RegExp Error require module process parseInt parseFloat setTimeout setInterval fetch';
  final cKw =
      'auto break case char const continue default do double else enum extern float for goto '
      'if inline int long register restrict return short signed sizeof static struct switch typedef '
      'union unsigned void volatile while NULL true false bool';
  final cppKw =
      '$cKw class namespace template typename using public private protected virtual '
      'override final new delete this throw try catch nullptr constexpr noexcept operator friend '
      'explicit mutable static_cast dynamic_cast reinterpret_cast const_cast decltype co_await '
      'co_return co_yield concept requires';

  final shellVar = (r'\$(?:\{[^}\n]*\}|\w+|[?#@*!$])', Tok.type);

  return {
    'python': _Spec(
      keywords:
          'False None True and as assert async await break class continue def del elif else '
          'except finally for from global if import in is lambda nonlocal not or pass raise return '
          'try while with yield match case',
      builtins:
          'print len range int str float list dict set tuple bool input open type isinstance '
          'enumerate zip map filter sorted sum min max abs any all super object self cls',
      lineComment: '#',
      tripleQuotes: true,
      annotations: true,
    ),
    'javascript': _Spec(
      keywords: jsKw,
      builtins: jsBuiltins,
      lineComment: '//',
      blockComment: true,
      backtick: true,
    ),
    'typescript': _Spec(
      keywords:
          '$jsKw interface type enum implements namespace declare readonly public private '
          'protected abstract as is keyof infer satisfies',
      builtins: '$jsBuiltins string number boolean any unknown never object',
      lineComment: '//',
      blockComment: true,
      backtick: true,
      annotations: true,
    ),
    'dart': _Spec(
      keywords:
          'abstract as assert async await break case catch class const continue covariant '
          'default deferred do dynamic else enum export extends extension external factory false '
          'final finally for Function get hide if implements import in interface is late library '
          'mixin new null on operator part required rethrow return sealed set show static super '
          'switch sync this throw true try typedef var void when while with yield',
      builtins:
          'print int double num String bool List Map Set Future Stream Iterable Object',
      lineComment: '//',
      blockComment: true,
      annotations: true,
    ),
    'java': _Spec(
      keywords:
          'abstract assert boolean break byte case catch char class const continue default do '
          'double else enum extends final finally float for goto if implements import instanceof '
          'int interface long native new package private protected public return short static '
          'strictfp super switch synchronized this throw throws transient try void volatile while '
          'var record null true false',
      builtins:
          'String System Math Integer List Map Set ArrayList HashMap Object',
      lineComment: '//',
      blockComment: true,
      annotations: true,
    ),
    'kotlin': _Spec(
      keywords:
          'as break class continue do else false for fun if in interface is null object package '
          'return super this throw true try typealias val var when while by catch constructor '
          'finally import init abstract companion const data enum final inline inner internal '
          'lateinit open operator out override private protected public sealed suspend vararg',
      builtins:
          'println print listOf mapOf setOf mutableListOf String Int Long Double Boolean',
      lineComment: '//',
      blockComment: true,
      annotations: true,
    ),
    'c': _Spec(
      keywords: cKw,
      builtins:
          'printf scanf malloc free strlen memcpy memset puts fopen fclose',
      lineComment: '//',
      blockComment: true,
      preprocessor: true,
    ),
    'cpp': _Spec(
      keywords: cppKw,
      builtins:
          'std cout cin endl string vector map set unique_ptr shared_ptr printf',
      lineComment: '//',
      blockComment: true,
      preprocessor: true,
    ),
    'csharp': _Spec(
      keywords:
          'abstract as base bool break byte case catch char checked class const continue decimal '
          'default delegate do double else enum event explicit extern false finally fixed float for '
          'foreach goto if implicit in int interface internal is lock long namespace new null object '
          'operator out override params private protected public readonly ref return sbyte sealed '
          'short sizeof static string struct switch this throw true try typeof uint ulong unchecked '
          'unsafe ushort using var virtual void volatile while async await record init required',
      builtins: 'Console List Dictionary String Math Task',
      lineComment: '//',
      blockComment: true,
    ),
    'go': _Spec(
      keywords:
          'break case chan const continue default defer else fallthrough for func go goto if '
          'import interface map package range return select struct switch type var nil true false iota',
      builtins:
          'append cap close copy delete len make new panic print println recover string int '
          'int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 float32 float64 bool byte rune error any',
      lineComment: '//',
      blockComment: true,
      backtick: true,
    ),
    'rust': _Spec(
      keywords:
          'as async await break const continue crate dyn else enum extern false fn for if impl in '
          'let loop match mod move mut pub ref return self Self static struct super trait true type '
          'unsafe use where while',
      builtins:
          'Vec String Option Some None Result Ok Err Box i8 i16 i32 i64 i128 isize u8 u16 u32 '
          'u64 u128 usize f32 f64 bool char str',
      lineComment: '//',
      blockComment: true,
      extras: const [(r'[A-Za-z_]\w*!', Tok.function)],
    ),
    'ruby': _Spec(
      keywords:
          'alias and begin break case class def do else elsif end ensure false for if in module '
          'next nil not or redo rescue retry return self super then true undef unless until when '
          'while yield',
      builtins:
          'puts print require require_relative attr_accessor attr_reader attr_writer p',
      lineComment: '#',
      extras: const [(r':[A-Za-z_]\w*', Tok.number)],
    ),
    'php': _Spec(
      keywords:
          'abstract and array as break callable case catch class clone const continue declare '
          'default do echo else elseif empty extends final finally fn for foreach function global if '
          'implements include include_once instanceof interface isset list match namespace new null '
          'or print private protected public readonly require require_once return static switch '
          'throw trait try unset use var while xor yield true false',
      lineComment: r'(?://|#)',
      blockComment: true,
      extras: const [
        (r'\$[A-Za-z_]\w*', Tok.type),
        (r'<\?php|\?>', Tok.keyword),
      ],
    ),
    'lua': _Spec(
      keywords:
          'and break do else elseif end false for function goto if in local nil not or repeat '
          'return then true until while',
      builtins:
          'print pairs ipairs require table string math os io type tostring tonumber',
      extras: const [
        (r'--\[\[[\s\S]*?(?:\]\]|(?![\s\S]))', Tok.comment),
        (r'--[^\n]*', Tok.comment),
      ],
    ),
    'perl': _Spec(
      keywords:
          'my our local sub if elsif else unless while until for foreach return use no package '
          'print say last next redo',
      lineComment: '#',
      extras: const [(r'[$@%][A-Za-z_]\w*', Tok.type)],
    ),
    'bash': _Spec(
      keywords:
          'if then else elif fi for while until do done case esac in function select time return '
          'exit break continue local export readonly declare unset source alias',
      builtins: 'echo cd set shift trap test read printf eval exec',
      lineComment: r'(?:(?<=\s)|^)#',
      extras: [shellVar],
    ),
    'powershell': _Spec(
      keywords:
          'begin break catch class continue data do dynamicparam else elseif end exit filter '
          'finally for foreach from function if in param process return switch throw trap try until '
          'using var while',
      lineComment: '#',
      extras: const [
        (r'\$(?:\{[^}\n]*\}|\w+)', Tok.type),
        (r'\b[A-Z][a-z]+-[A-Z]\w+\b', Tok.function),
      ],
    ),
    'swift': _Spec(
      keywords:
          'associatedtype class deinit enum extension fileprivate func import init inout internal '
          'let open operator private protocol public rethrows static struct subscript typealias var '
          'break case continue default defer do else fallthrough for guard if in repeat return switch '
          'where while as Any catch false is nil super self Self throw throws true try async await '
          'actor some',
      builtins: 'print String Int Double Bool Array Dictionary Set',
      lineComment: '//',
      blockComment: true,
    ),
    'r': _Spec(
      keywords:
          'if else repeat while function for next break TRUE FALSE NULL Inf NaN NA in',
      builtins: 'print cat c list data paste length seq',
      lineComment: '#',
    ),
    'sql': _Spec(
      keywords:
          'select from where insert into values update set delete create table alter drop index '
          'view join inner left right outer full on group by order having limit offset union all '
          'distinct as and or not null is in like between exists case when then else end primary key '
          'foreign references default unique check constraint asc desc begin commit rollback',
      builtins: 'count sum avg min max coalesce cast',
      lineComment: '--',
      blockComment: true,
      caseInsensitive: true,
    ),
    'json': _Spec(
      keywords: 'true false null',
      singleQuote: false,
      identifiers: false,
      extras: const [(r'"(?:\\.|[^"\\\n])*"(?=\s*:)', Tok.type)],
    ),
    'yaml': _Spec(
      keywords: 'true false null yes no on off',
      lineComment: r'(?:(?<=\s)|^)#',
      extras: const [(r'^[ \t-]*[\w.\-/]+(?=\s*:)', Tok.type)],
    ),
    'toml': _Spec(
      keywords: 'true false',
      lineComment: '#',
      extras: const [
        (r'^[ \t]*\[\[?[^\]\n]+\]\]?', Tok.keyword),
        (r'^[ \t]*[\w.\-]+(?=\s*=)', Tok.type),
      ],
    ),
    'html': _Spec(
      keywords: '',
      identifiers: false,
      extras: const [
        (r'<!--[\s\S]*?(?:-->|(?![\s\S]))', Tok.comment),
        (r'</?[A-Za-z][\w:.-]*', Tok.keyword),
        (r'/?>', Tok.keyword),
        (r'[A-Za-z_:][\w:.-]*(?==)', Tok.type),
      ],
    ),
    'css': _Spec(
      keywords: '',
      identifiers: false,
      blockComment: true,
      extras: const [
        (r'#[0-9a-fA-F]{3,8}\b', Tok.number),
        (r'@[\w-]+', Tok.keyword),
        (r'[.#][A-Za-z_][\w-]*', Tok.type),
        (r'[A-Za-z-]+(?=\s*:)', Tok.function),
        (r'-?\d*\.?\d+(?:px|em|rem|%|vh|vw|s|ms|deg|fr)?', Tok.number),
      ],
    ),
  };
}

/// Returns syntax tokens for [code]. Unknown languages yield no tokens.
List<Token> tokenizeCode(String code, String? languageId, {int offset = 0}) {
  final lang = Languages.find(languageId);
  final spec = _specs[lang?.id ?? ''];
  if (spec == null) return const [];
  final compiled = spec.compiled;
  final out = <Token>[];

  for (final m in compiled.regex.allMatches(code)) {
    var group = 0;
    for (var i = 1; i <= m.groupCount; i++) {
      if (m.group(i) != null) {
        group = i - 1;
        break;
      }
    }
    var tok = compiled.kinds[group];
    if (tok == null) {
      final word = m.group(0)!;
      final key = spec.caseInsensitive ? word.toLowerCase() : word;
      if (spec.keywords.contains(key)) {
        tok = Tok.keyword;
      } else if (spec.builtins.contains(key)) {
        tok = Tok.function;
      } else if (m.end < code.length && code.codeUnitAt(m.end) == 0x28) {
        tok = Tok.function;
      } else if (word.codeUnitAt(0) >= 0x41 &&
          word.codeUnitAt(0) <= 0x5A &&
          word.length > 1 &&
          word != word.toUpperCase()) {
        tok = Tok.type;
      } else {
        continue;
      }
    }
    out.add(Token(offset + m.start, offset + m.end, tok));
  }
  return out;
}

// ------------------------------------------------------------------ markdown

final RegExp _fenceLine = RegExp(r'^( {0,3})(`{3,}|~{3,})\s*([^\s`]*)(.*)$');
final RegExp _headingLine = RegExp(r'^ {0,3}(#{1,6})(\s.*|)$');
final RegExp _quoteLine = RegExp(r'^\s*>+');
final RegExp _listMarker = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+(\[[ xX]\]\s)?');
final RegExp _hr = RegExp(r'^\s*([-*_])(?:\s*\1){2,}\s*$');
final RegExp _inline = RegExp(
  r'(`[^`\n]+`)' // 1 code
  r'|(\*\*[^*\n]+\*\*|__[^_\n]+__)' // 2 bold
  r'|(\[\[[^\]\n]+\]\])' // 3 wikilink
  r'|(!?\[[^\]\n]*\]\([^)\n]*\))' // 4 link
  r'|(https?://[^\s)>\]]+)' // 5 url
  r'|((?<![*\w])\*[^*\s][^*\n]*\*(?!\*)|(?<![_\w])_[^_\s][^_\n]*_(?![_\w]))', // 6 italic
);

/// Tokenizes a markdown document, including fenced code blocks.
List<Token> tokenizeMarkdown(String text) {
  final out = <Token>[];
  var pos = 0;
  String? fenceChar;
  var fenceLen = 0;
  String? fenceLang;
  var codeStart = 0;

  void closeBlock(int end) {
    if (fenceLang != null && end > codeStart) {
      out.addAll(
        tokenizeCode(
          text.substring(codeStart, end),
          fenceLang,
          offset: codeStart,
        ),
      );
    }
  }

  while (pos <= text.length) {
    var eol = text.indexOf('\n', pos);
    if (eol == -1) eol = text.length;
    final line = text.substring(pos, eol);

    if (fenceChar != null) {
      final t = line.trimLeft();
      final isClose =
          t.startsWith(fenceChar * fenceLen) &&
          t.replaceAll(fenceChar, '').trim().isEmpty;
      if (isClose) {
        closeBlock(pos);
        out.add(Token(pos, eol, Tok.marker));
        fenceChar = null;
        fenceLang = null;
      }
    } else {
      final f = _fenceLine.firstMatch(line);
      if (f != null) {
        fenceChar = f.group(2)![0];
        fenceLen = f.group(2)!.length;
        fenceLang = f.group(3);
        codeStart = eol + 1;
        final markerEnd = pos + f.group(1)!.length + f.group(2)!.length;
        out.add(Token(pos, markerEnd, Tok.marker));
        if (line.length > markerEnd - pos) {
          out.add(Token(markerEnd, eol, Tok.type));
        }
      } else {
        _markdownLine(line, pos, out);
      }
    }
    pos = eol + 1;
  }
  if (fenceChar != null) closeBlock(text.length);

  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

void _markdownLine(String line, int base, List<Token> out) {
  if (line.isEmpty) return;

  final h = _headingLine.firstMatch(line);
  if (h != null) {
    final markerLen = h.group(1)!.length;
    final lead = line.indexOf('#');
    out.add(Token(base + lead, base + lead + markerLen, Tok.marker));
    out.add(Token(base + lead + markerLen, base + line.length, Tok.heading));
    return;
  }
  if (_hr.hasMatch(line)) {
    out.add(Token(base, base + line.length, Tok.marker));
    return;
  }

  var inlineStart = 0;
  final q = _quoteLine.firstMatch(line);
  if (q != null) {
    out.add(Token(base, base + q.end, Tok.marker));
    inlineStart = q.end;
  }
  final l = _listMarker.firstMatch(line);
  if (l != null && q == null) {
    final mark = l.group(0)!;
    final box = l.group(1);
    final markEnd = box == null ? mark.length : mark.length - box.length;
    out.add(Token(base, base + markEnd, Tok.marker));
    if (box != null) {
      out.add(Token(base + markEnd, base + mark.length - 1, Tok.keyword));
    }
    inlineStart = mark.length;
  }

  for (final m in _inline.allMatches(line, inlineStart)) {
    final Tok tok;
    if (m.group(1) != null) {
      tok = Tok.string;
    } else if (m.group(2) != null) {
      tok = Tok.bold;
    } else if (m.group(3) != null || m.group(4) != null || m.group(5) != null) {
      tok = Tok.link;
    } else {
      tok = Tok.italic;
    }
    out.add(Token(base + m.start, base + m.end, tok));
  }
}

/// Ranges of a markdown document that are code: fenced blocks (including
/// their fence lines) and inline `code` spans. Used to draw code in a
/// monospace font when prose uses a proportional one.
List<(int, int)> markdownCodeRanges(String text) {
  final out = <(int, int)>[];
  final inlineCode = RegExp(r'`[^`\n]+`');
  var pos = 0;
  String? fenceChar;
  var fenceLen = 0;
  var blockStart = 0;
  while (pos <= text.length) {
    var eol = text.indexOf('\n', pos);
    if (eol == -1) eol = text.length;
    final line = text.substring(pos, eol);
    if (fenceChar != null) {
      final t = line.trimLeft();
      if (t.startsWith(fenceChar * fenceLen) &&
          t.replaceAll(fenceChar, '').trim().isEmpty) {
        out.add((blockStart, eol));
        fenceChar = null;
      }
    } else {
      final f = _fenceLine.firstMatch(line);
      if (f != null) {
        fenceChar = f.group(2)![0];
        fenceLen = f.group(2)!.length;
        blockStart = pos;
      } else {
        for (final m in inlineCode.allMatches(line)) {
          out.add((pos + m.start, pos + m.end));
        }
      }
    }
    pos = eol + 1;
  }
  if (fenceChar != null) out.add((blockStart, text.length));
  return out;
}

// ------------------------------------------------------------------- styling

TextStyle _styleFor(Tok tok, TextStyle base, AppPalette p) {
  switch (tok) {
    case Tok.keyword:
      return base.copyWith(color: p.synKeyword);
    case Tok.string:
      return base.copyWith(color: p.synString);
    case Tok.number:
      return base.copyWith(color: p.synNumber);
    case Tok.comment:
      return base.copyWith(color: p.synComment, fontStyle: FontStyle.italic);
    case Tok.type:
      return base.copyWith(color: p.synType);
    case Tok.function:
      return base.copyWith(color: p.synFunction);
    case Tok.heading:
      return base.copyWith(color: p.synHeading, fontWeight: FontWeight.w700);
    case Tok.link:
      return base.copyWith(color: p.synLink);
    case Tok.marker:
      return base.copyWith(color: p.synMarker);
    case Tok.bold:
      return base.copyWith(fontWeight: FontWeight.w700);
    case Tok.italic:
      return base.copyWith(fontStyle: FontStyle.italic);
    case Tok.quote:
      return base.copyWith(color: p.synComment);
  }
}

/// Builds a [TextSpan] whose flattened text equals [text]. Overlapping tokens
/// are resolved in favour of the first one.
TextSpan buildHighlightedSpan(
  String text,
  List<Token> tokens,
  TextStyle base,
  AppPalette palette,
) {
  if (tokens.isEmpty) return TextSpan(text: text, style: base);
  final children = <InlineSpan>[];
  var cursor = 0;
  for (final t in tokens) {
    if (t.start < cursor || t.end <= t.start || t.end > text.length) continue;
    if (t.start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, t.start)));
    }
    children.add(
      TextSpan(
        text: text.substring(t.start, t.end),
        style: _styleFor(t.tok, base, palette),
      ),
    );
    cursor = t.end;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(style: base, children: children);
}
