import '../../core/widgets/app_notification.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../application/persistence_coordinator.dart';
import '../../application/reminders.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/util/ids.dart';
import '../../data/models/note.dart';
import '../../domain/note_tasks.dart';
import 'calendar_view.dart';
import 'dialogs.dart';

Future<void> showTaskDashboard(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const TaskDashboard());

/// Views of the task list.
enum TaskView {
  today('Today'),
  week('This week'),
  overdue('Overdue'),
  open('Open tasks'),
  done('Completed'),
  all('All');

  const TaskView(this.label);
  final String label;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whether [t] belongs in [view] at [now].
bool taskInView(NoteTask t, TaskView view, DateTime now) {
  final today = _day(now);
  final due = t.due;
  return switch (view) {
    TaskView.today =>
      !t.done &&
          due != null &&
          due.isBefore(today.add(const Duration(days: 1))),
    TaskView.week =>
      !t.done &&
          due != null &&
          due.isBefore(today.add(const Duration(days: 7))),
    TaskView.overdue => !t.done && due != null && due.isBefore(now),
    TaskView.open => !t.done,
    TaskView.done => t.done,
    TaskView.all => true,
  };
}

/// Overdue first, then by date (undated last), then by priority.
int compareTasks(NoteTask a, NoteTask b) {
  final da = a.due ?? DateTime(9999), db = b.due ?? DateTime(9999);
  final c = da.compareTo(db);
  if (c != 0) return c;
  return b.priority.index.compareTo(a.priority.index);
}

Color priorityColor(TaskPriority p, AppPalette palette) => switch (p) {
  TaskPriority.high => palette.danger,
  TaskPriority.medium => palette.warning,
  TaskPriority.low => palette.info,
  TaskPriority.none => palette.textFaint,
};

/// "Today 14:00", "Tomorrow", "3 days overdue", "Mon 12 Oct"...
String dueLabel(BuildContext context, DateTime due, {DateTime? now}) {
  final clock = now ?? DateTime.now();
  final days = _day(due).difference(_day(clock)).inDays;
  final time = TimeOfDay.fromDateTime(due).format(context);
  final hasTime = due.hour != 0 || due.minute != 0;
  if (due.isBefore(clock) && days < 0) {
    return context.tr('{n} days overdue', {'n': -days});
  }
  final day = switch (days) {
    0 => context.tr('Today'),
    1 => context.tr('Tomorrow'),
    -1 => context.tr('Yesterday'),
    _ => MaterialLocalizations.of(context).formatShortMonthDay(due),
  };
  return hasTime ? '$day $time' : day;
}

class TaskDashboard extends ConsumerStatefulWidget {
  const TaskDashboard({super.key});
  @override
  ConsumerState<TaskDashboard> createState() => _TaskDashboardState();
}

class _TaskDashboardState extends ConsumerState<TaskDashboard> {
  TaskView _view = TaskView.open;
  String _search = '';

  @override
  void initState() {
    super.initState();
    // Start on "Today" when something is due.
    final now = DateTime.now();
    final hasToday = ref
        .read(libraryProvider)
        .notes
        .values
        .expand(noteTasks)
        .any((t) => taskInView(t, TaskView.today, now));
    if (hasToday) _view = TaskView.today;
  }

  void _update(NoteTask t, String Function(Note note) change) {
    ref.read(persistenceProvider).flushEditors();
    final note = ref.read(libraryProvider.notifier).readable(t.noteId);
    if (note == null) return;
    ref
        .read(libraryProvider.notifier)
        .updateContent(note.id, body: change(note));
  }

  Future<void> _date(NoteTask task) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: task.due ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: task.due == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay.fromDateTime(task.due!),
    );
    if (time == null || !mounted) return;
    _update(
      task,
      (note) => changeTask(
        note,
        task,
        id: newId(),
        due: DateTime(date.year, date.month, date.day, time.hour, time.minute),
        setDate: true,
      ),
    );
  }

  void _complete(NoteTask t, bool done) {
    ref.read(persistenceProvider).flushEditors();
    final note = ref.read(libraryProvider.notifier).readable(t.noteId);
    if (note == null) return;
    final (body, next) = completeTask(note, t, done);
    ref.read(libraryProvider.notifier).updateContent(note.id, body: body);
    if (next != null) {
      showToast(
        context,
        context.tr('Repeats: next on {date}', {
          'date': dueLabel(context, next),
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider), p = context.palette;
    final now = DateTime.now();
    final all = [
      for (final n in lib.notes.values)
        ...noteTasks(ref.read(libraryProvider.notifier).readable(n.id) ?? n),
    ];
    final counts = {
      for (final v in TaskView.values)
        v: all.where((t) => taskInView(t, v, now)).length,
    };
    final tasks =
        all
            .where(
              (t) =>
                  taskInView(t, _view, now) &&
                  (t.text.toLowerCase().contains(_search) ||
                      lib.notes[t.noteId]!.displayTitle.toLowerCase().contains(
                        _search,
                      )),
            )
            .toList()
          ..sort(compareTasks);
    final notifications =
        ref.watch(settingsProvider.select((s) => s.systemNotifications)) &&
        TaskReminders.supported;
    return AppDialog(
      icon: Icons.checklist_rounded,
      title: context.tr('Tasks'),
      subtitle: context.tr(
        notifications
            ? 'Tasks from all notes. Reminders arrive as system notifications, even when Markbit is closed.'
            : 'Tasks from all notes. Reminders appear while Markbit is open.',
      ),
      width: 820,
      height: 680,
      scrollable: false,
      headerActions: [
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            showCalendarView(context);
          },
          icon: const Icon(Icons.calendar_month_outlined, size: 18),
          label: Text(context.tr('Calendar')),
        ),
      ],
      bodyPadding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.lg),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: p.textMuted,
              ),
              hintText: context.tr('Search tasks'),
            ),
          ),
          const SizedBox(height: Sp.md),
          // One scrollable row, so small windows keep room for the list.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final v in TaskView.values)
                  Padding(
                    padding: const EdgeInsets.only(right: Sp.sm),
                    child: ChoiceChip(
                      label: Text(
                        '${context.tr(v.label)}'
                        '${v == TaskView.all || v == TaskView.done ? '' : ' ${counts[v]}'}',
                      ),
                      selected: _view == v,
                      onSelected: (_) => setState(() => _view = v),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          Expanded(
            child: tasks.isEmpty
                ? DialogEmptyState(
                    icon: Icons.task_alt_rounded,
                    message: context.tr('No tasks found'),
                  )
                : ListView.separated(
                    itemCount: tasks.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) => _TaskRow(
                      task: tasks[i],
                      note: lib.notes[tasks[i].noteId]!,
                      now: now,
                      onDone: (v) => _complete(tasks[i], v),
                      onOpen: () {
                        ref
                            .read(openNoteProvider.notifier)
                            .open(tasks[i].noteId);
                        Navigator.pop(context);
                      },
                      onDate: () => _date(tasks[i]),
                      onClearDate: () => _update(
                        tasks[i],
                        (n) => changeTask(n, tasks[i], setDate: true),
                      ),
                      onPriority: (pr) => _update(
                        tasks[i],
                        (n) =>
                            changeTask(n, tasks[i], id: newId(), priority: pr),
                      ),
                      onRepeat: (r) => _update(
                        tasks[i],
                        (n) => changeTask(
                          n,
                          tasks[i],
                          id: newId(),
                          repeat: r,
                          setRepeat: true,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.note,
    required this.now,
    required this.onDone,
    required this.onOpen,
    required this.onDate,
    required this.onClearDate,
    required this.onPriority,
    required this.onRepeat,
  });

  final NoteTask task;
  final Note note;
  final DateTime now;
  final ValueChanged<bool> onDone;
  final VoidCallback onOpen, onDate, onClearDate;
  final ValueChanged<TaskPriority> onPriority;
  final ValueChanged<TaskRepeat?> onRepeat;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = task;
    final overdue = t.due != null && !t.done && t.due!.isBefore(now);
    return Material(
      color: p.codeBg,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: t.priority == TaskPriority.high && !t.done
              ? p.danger.withValues(alpha: .5)
              : p.border,
        ),
        borderRadius: BorderRadius.circular(Rad.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.xs, Sp.xs, Sp.xs, Sp.xs),
          child: Row(
            children: [
              Checkbox(value: t.done, onChanged: (v) => onDone(v ?? false)),
              if (t.priority != TaskPriority.none)
                Padding(
                  padding: const EdgeInsets.only(right: Sp.xs),
                  child: Tooltip(
                    message: context.tr(t.priority.label),
                    child: Icon(
                      Icons.flag_rounded,
                      size: 16,
                      color: priorityColor(t.priority, p),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.text,
                      style: TextStyle(
                        color: t.done ? p.textMuted : p.text,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: Sp.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          note.displayTitle,
                          style: TextStyle(
                            color: p.textFaint,
                            fontSize: Fs.small,
                          ),
                        ),
                        if (t.due != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.event_outlined,
                                size: 13,
                                color: overdue ? p.danger : p.textMuted,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                dueLabel(context, t.due!, now: now),
                                style: TextStyle(
                                  color: overdue ? p.danger : p.textMuted,
                                  fontSize: Fs.small,
                                  fontWeight: overdue
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        if (t.repeat != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.repeat_rounded,
                                size: 13,
                                color: p.textMuted,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                context.tr(t.repeat!.label),
                                style: TextStyle(
                                  color: p.textMuted,
                                  fontSize: Fs.small,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<Object>(
                tooltip: context.tr('Task options'),
                icon: Icon(
                  Icons.more_horiz_rounded,
                  size: 18,
                  color: p.textMuted,
                ),
                onSelected: (v) {
                  if (v == 'date') onDate();
                  if (v == 'clear') onClearDate();
                  if (v is TaskPriority) onPriority(v);
                  if (v is TaskRepeat) onRepeat(v);
                  if (v == 'norepeat') onRepeat(null);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'date',
                    child: Text(ctx.tr('Set date and reminder')),
                  ),
                  if (t.due != null)
                    PopupMenuItem(
                      value: 'clear',
                      child: Text(ctx.tr('Remove date')),
                    ),
                  const PopupMenuDivider(),
                  for (final pr in TaskPriority.values.reversed)
                    CheckedPopupMenuItem(
                      value: pr,
                      checked: t.priority == pr,
                      child: Row(
                        children: [
                          Icon(
                            Icons.flag_rounded,
                            size: 16,
                            color: priorityColor(pr, p),
                          ),
                          const SizedBox(width: Sp.sm),
                          Text(ctx.tr(pr.label)),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  for (final r in TaskRepeat.values)
                    CheckedPopupMenuItem(
                      value: r,
                      checked: t.repeat == r,
                      child: Text(ctx.tr(r.label)),
                    ),
                  CheckedPopupMenuItem(
                    value: 'norepeat',
                    checked: t.repeat == null,
                    child: Text(ctx.tr('Does not repeat')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps reminders scheduled: operating-system notifications when
/// available (they also arrive while Markbit is closed), in-app notices
/// otherwise.
class TaskReminderHost extends ConsumerStatefulWidget {
  const TaskReminderHost({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<TaskReminderHost> createState() => _TaskReminderHostState();
}

class _TaskReminderHostState extends ConsumerState<TaskReminderHost> {
  Timer? _timer;
  Timer? _syncTimer;
  final Set<String> _shown = {};
  TaskReminders? _system;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    if (ref.read(reminderPlatformEnabledProvider) && TaskReminders.supported) {
      final reminders = _system = TaskReminders(ref.read(sharedPrefsProvider))
        ..onOpen = (id) {
          if (mounted && ref.read(libraryProvider).notes.containsKey(id)) {
            ref.read(openNoteProvider.notifier).open(id);
          }
        };
      reminders.init().then((_) => _scheduleSync());
      ref.listenManual(libraryProvider, (_, _) => _scheduleSync());
      ref.listenManual(
        settingsProvider.select((s) => s.systemNotifications),
        (_, on) => on ? _scheduleSync() : reminders.clear(),
      );
    }
  }

  bool get _systemActive =>
      _system?.available == true &&
      ref.read(settingsProvider).systemNotifications;

  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_systemActive) return;
      final lib = ref.read(libraryProvider);
      _system!.sync([
        for (final n in lib.notes.values)
          if (!n.isLocked)
            for (final t in noteTasks(n)) (n, t),
      ]);
    });
  }

  void _check() {
    // System notifications already cover this; avoid showing both.
    if (!mounted || _systemActive) return;
    final prefs = ref.read(sharedPrefsProvider);
    for (final n in ref.read(libraryProvider).notes.values) {
      for (final t in noteTasks(n)) {
        if (t.done || t.due == null || t.due!.isAfter(DateTime.now())) continue;
        final key = 'task_notice:${t.key}:${t.due!.toIso8601String()}';
        if (_shown.contains(key) || prefs.getBool(key) == true) continue;
        _shown.add(key);
        unawaited(prefs.setBool(key, true));
        AppNotifications.show(
          context,
          '${context.tr('Task reminder')}: ${t.text}',
          duration: const Duration(seconds: 12),
          actionLabel: context.tr('Open'),
          onAction: () => ref.read(openNoteProvider.notifier).open(n.id),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
