import '../core/theme/app_palette.dart';
import '../core/util/ids.dart';
import 'models/library_models.dart';
import 'models/note.dart';
import 'repository/library_repository.dart';

/// Loads the library and, on first launch, fills it with a starter set so the
/// app never opens onto an empty screen.
Future<LibrarySnapshot> loadOrSeed(LibraryRepository repo) async {
  final snap = await repo.load();
  final hasInbox = snap.notebooks.any((n) => n.isInbox);
  if (!snap.isFresh && hasInbox) return snap;

  final inbox = Notebook(id: newId(), name: 'General', isInbox: true);
  final work = Notebook(id: newId(), name: 'Work');
  final projects = Notebook(id: newId(), name: 'Projects', parentId: work.id);

  Tag tag(String name, int i) => Tag(
    id: newId(),
    name: name,
    colorValue: AppPalette.tagColors[i].toARGB32(),
  );
  final tWork = tag('work', 0);
  final tPersonal = tag('personal', 1);
  final tBug = tag('bug', 2);
  final tResearch = tag('research', 3);

  final notebooks = snap.isFresh
      ? [inbox, work, projects]
      : [inbox, ...snap.notebooks];
  final tags = snap.isFresh ? [tWork, tPersonal, tBug, tResearch] : snap.tags;
  final templates = snap.isFresh ? _templates() : snap.templates;

  var minutes = 0;
  Note note({
    required String title,
    required String body,
    String? notebookId,
    NoteStatus status = NoteStatus.none,
    List<String> tagIds = const [],
    bool pinned = false,
    NoteKind kind = NoteKind.markdown,
    String? language,
  }) {
    minutes += 47;
    final t = DateTime.now().subtract(Duration(minutes: minutes));
    return Note(
      id: newId(),
      title: title,
      body: body,
      notebookId: notebookId ?? inbox.id,
      status: status,
      tagIds: tagIds,
      pinned: pinned,
      kind: kind,
      language: language,
      createdAt: t,
      updatedAt: t,
    );
  }

  final notes = snap.isFresh
      ? <Note>[
          note(
            title: 'Welcome to Markbit',
            pinned: true,
            tagIds: [tWork.id],
            body: _welcome,
          ),
          note(
            title: 'Note list scrolling stutters with 3k notes',
            notebookId: projects.id,
            status: NoteStatus.active,
            tagIds: [tWork.id, tBug.id],
            body: _bugNote,
          ),
          note(
            title: 'Fibonacci in three languages',
            notebookId: work.id,
            status: NoteStatus.onHold,
            tagIds: [tResearch.id],
            body: _fibNote,
          ),
          note(
            title: 'quick_sort.py',
            kind: NoteKind.code,
            language: 'python',
            tagIds: [tPersonal.id],
            body: _quickSort,
          ),
        ]
      : const <Note>[];

  for (final n in notes) {
    await repo.saveNote(n);
  }
  await repo.saveMeta(notebooks: notebooks, tags: tags, templates: templates);

  return LibrarySnapshot(
    notes: [...snap.notes, ...notes],
    notebooks: notebooks,
    tags: tags,
    templates: templates,
    isFresh: false,
  );
}

List<NoteTemplate> _templates() => [
  NoteTemplate(
    id: newId(),
    name: 'Bug report',
    title: 'Bug: ',
    body:
        '## Summary\n\n## Steps to reproduce\n\n1. \n2. \n\n## Expected\n\n## Actual\n\n## Checklist\n\n- [ ] Reproduce\n- [ ] Find root cause\n- [ ] Fix\n- [ ] Add regression test\n',
  ),
  NoteTemplate(
    id: newId(),
    name: 'Meeting notes',
    title: 'Meeting \u2014 ',
    body:
        '## Attendees\n\n## Agenda\n\n## Notes\n\n## Action items\n\n- [ ] \n',
  ),
  NoteTemplate(
    id: newId(),
    name: 'Code experiment',
    title: 'Experiment: ',
    body:
        '## Idea\n\n## Try it\n\n```python\nprint("hello")\n```\n\n## Result\n',
  ),
  NoteTemplate(
    id: newId(),
    name: 'Daily log',
    title: 'Daily log',
    body: '## Today\n\n- [ ] \n\n## Notes\n\n## Tomorrow\n\n- [ ] \n',
  ),
];

const String _welcome = '''## Write notes. Run code.

Markbit is a notebook for developers. Every fenced code block with a
language tag gets a **Run** button \u2014 try it:

```python
for i in range(1, 4):
    print(f"Hello from Python #{i}")
```

```javascript
const squares = [1, 2, 3, 4].map((n) => n * n);
console.log("squares:", squares);
```

### Things to try

- [x] Open the editor / split / preview modes at the top
- [ ] Press `Ctrl+Enter` inside a code block to run it
- [ ] Press `Ctrl+K` for the command palette
- [ ] Create a **code note** (a whole file) from the `+` menu
- [ ] Connect an AI model in Settings
- [ ] Link notes with [[Fibonacci in three languages]]

Search understands operators: `tag:work`, `status:active`, `lang:python`, `has:code`.
''';

const String _bugNote = '''## Symptoms

Scrolling the note list stutters badly once the library has ~3,000 notes.

## Ideas

- [x] Profile the build of each tile
- [x] Cache derived snippets per note
- [ ] Virtualise with a fixed item extent
- [ ] Move filtering off the UI thread
''';

const String _fibNote = '''## Fibonacci

Same algorithm, different languages. Run them and compare.

```python
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a

print([fib(i) for i in range(10)])
```

```dart
int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);

void main() {
  print(List.generate(10, fib));
}
```

```go
package main

import "fmt"

func fib(n int) int {
	if n < 2 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func main() {
	for i := 0; i < 10; i++ {
		fmt.Print(fib(i), " ")
	}
	fmt.Println()
}
```
''';

const String _quickSort = '''def quick_sort(items):
    if len(items) <= 1:
        return items
    pivot, *rest = items
    left = [x for x in rest if x < pivot]
    right = [x for x in rest if x >= pivot]
    return quick_sort(left) + [pivot] + quick_sort(right)


data = [9, 3, 7, 1, 8, 2, 5]
print("input :", data)
print("sorted:", quick_sort(data))
''';
