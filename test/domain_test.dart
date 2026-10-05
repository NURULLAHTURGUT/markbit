import 'package:markbit/data/models/note.dart';
import 'package:markbit/domain/languages.dart';
import 'package:markbit/domain/markdown_utils.dart';
import 'package:markbit/domain/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

Note _note({
  String title = 'T',
  String body = '',
  NoteStatus status = NoteStatus.none,
  bool pinned = false,
  NoteKind kind = NoteKind.markdown,
  String? language,
}) {
  final now = DateTime(2025, 1, 1);
  return Note(
    id: 'id',
    title: title,
    body: body,
    status: status,
    pinned: pinned,
    kind: kind,
    language: language,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('markdown utils', () {
    const body =
        '# Title\n\nSome text\n\n```python\nprint("hi")\n```\n\n- [x] one\n- [ ] two\n\n```\n# not a heading\n- [ ] not a task\n```\n';

    test('splits prose and fenced code', () {
      final segs = splitSegments(body);
      final code = segs.whereType<CodeSegment>().toList();
      expect(code.length, 2);
      expect(code.first.info, 'python');
      expect(code.first.code, 'print("hi")');
      expect(code.first.startLine, 4);
      expect(code.first.endLine, 6);
      expect(code.last.info, '');
    });

    test('unterminated fence swallows the rest', () {
      final segs = splitSegments('text\n```js\nlet a = 1;\n');
      expect(segs.whereType<CodeSegment>().single.info, 'js');
    });

    test('headings ignore code blocks', () {
      final h = extractHeadings(body);
      expect(h.length, 1);
      expect(h.single.text, 'Title');
      expect(h.single.line, 0);
    });

    test('task progress ignores code blocks', () {
      final p = taskProgress(body);
      expect(p.done, 1);
      expect(p.total, 2);
    });

    test('snippet strips markdown and skips fences', () {
      expect(
        makeSnippet('# Head\n\n**bold** text\n```\ncode\n```'),
        'Head bold text',
      );
    });

    test('wiki links are linkified', () {
      final out = linkifyWikiLinks(
        'see [[A]] and [[B|label]]',
        (t) => t == 'A' ? '42' : null,
      );
      expect(out, contains('[A](markbit://note/42)'));
      expect(out, contains('[label](markbit://create/B)'));
    });
  });

  group('search query', () {
    final q = SearchQuery.parse;

    test('free text must match title or body', () {
      final n = _note(title: 'Hello', body: 'world');
      expect(
        q('hello').match(n, tagNames: [], notebookName: null),
        greaterThan(0),
      );
      expect(
        q('world').match(n, tagNames: [], notebookName: null),
        greaterThan(0),
      );
      expect(q('nope').match(n, tagNames: [], notebookName: null), -1);
    });

    test('operators', () {
      final n = _note(status: NoteStatus.active, body: '```python\n1\n```');
      bool ok(String s) =>
          q(s).match(n, tagNames: ['work'], notebookName: 'Projects') >= 0;
      expect(ok('tag:work'), isTrue);
      expect(ok('tag:home'), isFalse);
      expect(ok('notebook:proj'), isTrue);
      expect(ok('status:active'), isTrue);
      expect(ok('status:completed'), isFalse);
      expect(ok('lang:python'), isTrue);
      expect(ok('has:code'), isTrue);
      expect(ok('is:pinned'), isFalse);
    });

    test('quoted values', () {
      final n = _note();
      expect(
        q(
          'tag:"side project"',
        ).match(n, tagNames: ['Side Project'], notebookName: null),
        greaterThanOrEqualTo(0),
      );
    });
  });

  group('languages', () {
    test('aliases resolve', () {
      expect(Languages.find('py')?.id, 'python');
      expect(Languages.find('C++')?.id, 'cpp');
      expect(Languages.find('TS')?.id, 'typescript');
      expect(Languages.find('nonsense'), isNull);
    });

    test('runnable languages have a source file name', () {
      for (final l in Languages.runnable) {
        expect(l.sourceFileName, isNotEmpty);
      }
    });
  });
}
