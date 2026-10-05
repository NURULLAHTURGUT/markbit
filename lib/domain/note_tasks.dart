import '../data/models/note.dart';

enum TaskPriority {
  none('No priority'),
  low('Low'),
  medium('Medium'),
  high('High');

  const TaskPriority(this.label);
  final String label;

  static TaskPriority parse(String? v) =>
      TaskPriority.values.where((p) => p.name == v).firstOrNull ??
      TaskPriority.none;
}

/// How a task repeats once it is completed.
enum TaskRepeat {
  daily('Every day'),
  weekdays('Every weekday'),
  weekly('Every week'),
  monthly('Every month'),
  yearly('Every year');

  const TaskRepeat(this.label);
  final String label;

  static TaskRepeat? parse(String? v) =>
      TaskRepeat.values.where((r) => r.name == v).firstOrNull;

  /// The occurrence after [from].
  DateTime next(DateTime from) {
    switch (this) {
      case daily:
        return from.add(const Duration(days: 1));
      case weekdays:
        var d = from.add(const Duration(days: 1));
        while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
          d = d.add(const Duration(days: 1));
        }
        return d;
      case weekly:
        return from.add(const Duration(days: 7));
      case monthly:
        return _addMonths(from, 1);
      case yearly:
        return _addMonths(from, 12);
    }
  }

  static DateTime _addMonths(DateTime d, int months) {
    final total = d.month - 1 + months;
    final year = d.year + total ~/ 12;
    final month = total % 12 + 1;
    final last = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, d.day > last ? last : d.day, d.hour, d.minute);
  }
}

class NoteTask {
  const NoteTask(
    this.noteId,
    this.line,
    this.text,
    this.done,
    this.id,
    this.due, {
    this.priority = TaskPriority.none,
    this.repeat,
  });
  final String noteId, text;
  final int line;
  final bool done;
  final String? id;
  final DateTime? due;
  final TaskPriority priority;
  final TaskRepeat? repeat;
  String get key => '$noteId:${id ?? line}';
}

final _taskLine = RegExp(r'^\s*(?:[-*+]|\d+[.)]) \[([ xX])\]\s+(.*)$');
final _meta = RegExp(r'\s*<!-- task:([\w-]+)((?: [a-z]+:[^ ]+)*) -->');

/// Fields stored in a task's `<!-- task:… -->` comment.
Map<String, String> _fields(String raw) => {
  for (final part in raw.trim().split(' '))
    if (part.contains(':'))
      part.substring(0, part.indexOf(':')): part.substring(
        part.indexOf(':') + 1,
      ),
};

List<NoteTask> noteTasks(Note note) {
  if (note.trashed || note.kind == NoteKind.code) return [];
  final tasks = <NoteTask>[];
  var fenced = false;
  final lines = note.body.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'^\s*(```|~~~)').hasMatch(lines[i])) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    final m = _taskLine.firstMatch(lines[i]);
    if (m == null) continue;
    final meta = _meta.firstMatch(m[2]!);
    final fields = meta == null ? const <String, String>{} : _fields(meta[2]!);
    tasks.add(
      NoteTask(
        note.id,
        i,
        m[2]!.replaceAll(RegExp(r'<!-- task:.*? -->'), '').trim(),
        m[1]!.toLowerCase() == 'x',
        meta?[1],
        DateTime.tryParse(fields['due'] ?? ''),
        priority: TaskPriority.parse(fields['prio']),
        repeat: TaskRepeat.parse(fields['repeat']),
      ),
    );
  }
  return tasks;
}

String _metaComment(
  String id,
  DateTime? due,
  TaskPriority priority,
  TaskRepeat? repeat,
) {
  if (due == null && priority == TaskPriority.none && repeat == null) {
    return '';
  }
  return ' <!-- task:$id'
      '${due == null ? '' : ' due:${due.toIso8601String()}'}'
      '${priority == TaskPriority.none ? '' : ' prio:${priority.name}'}'
      '${repeat == null ? '' : ' repeat:${repeat.name}'}'
      ' -->';
}

/// Rewrites the line of [task] in [note]. Returns the unchanged body when the
/// line no longer holds that task (the note was edited meanwhile).
String changeTask(
  Note note,
  NoteTask task, {
  bool? done,
  String? id,
  DateTime? due,
  bool setDate = false,
  TaskPriority? priority,
  TaskRepeat? repeat,
  bool setRepeat = false,
}) {
  final lines = note.body.split('\n');
  if (task.line >= lines.length) return note.body;
  final current = noteTasks(note).where((t) => t.line == task.line).firstOrNull;
  if (current == null ||
      (current.text != task.text ||
          (task.id != null && current.id != task.id))) {
    return note.body;
  }
  var line = lines[task.line];
  if (done != null) {
    line = line.replaceFirst(RegExp(r'\[[ xX]\]'), done ? '[x]' : '[ ]');
  }
  if (setDate || priority != null || setRepeat) {
    line = line.replaceAll(RegExp(r'\s*<!-- task:.*? -->'), '');
    line += _metaComment(
      current.id ?? id ?? task.id ?? _shortId(task),
      setDate ? due : current.due,
      priority ?? current.priority,
      setRepeat ? repeat : current.repeat,
    );
  }
  lines[task.line] = line;
  return lines.join('\n');
}

String _shortId(NoteTask task) =>
    '${task.noteId.hashCode.toUnsigned(20).toRadixString(36)}'
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// The next due date of a repeating task, skipping occurrences that are
/// already in the past.
DateTime nextOccurrence(TaskRepeat repeat, DateTime due, DateTime now) {
  var next = repeat.next(due);
  var guard = 0;
  while (!next.isAfter(now) && guard++ < 5000) {
    next = repeat.next(next);
  }
  return next;
}

/// Marks [task] done or not done. A repeating task with a date is not
/// checked off: it moves to its next occurrence instead. Returns the new
/// body and, for repeating tasks, the next date.
(String, DateTime?) completeTask(
  Note note,
  NoteTask task,
  bool done, {
  DateTime? now,
}) {
  if (done && task.repeat != null && task.due != null) {
    final next = nextOccurrence(task.repeat!, task.due!, now ?? DateTime.now());
    return (
      changeTask(note, task, done: false, due: next, setDate: true),
      next,
    );
  }
  return (changeTask(note, task, done: done), null);
}

/// Checkbox toggles from the preview: same rules as [completeTask] for the
/// task on [line].
(String, DateTime?) toggleTaskLine(Note note, int line, bool done) {
  final task = noteTasks(note).where((t) => t.line == line).firstOrNull;
  if (task == null) {
    final lines = note.body.split('\n');
    if (line >= lines.length) return (note.body, null);
    lines[line] = lines[line].replaceFirst(
      RegExp(r'\[[ xX]\]'),
      done ? '[x]' : '[ ]',
    );
    return (lines.join('\n'), null);
  }
  return completeTask(note, task, done);
}
