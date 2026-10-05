import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library_notifier.dart';
import '../../application/persistence_coordinator.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../data/models/note.dart';
import '../../domain/note_tasks.dart';
import 'dialogs.dart';
import 'task_dashboard.dart';

Future<void> showCalendarView(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const CalendarView());

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// One entry on a calendar day.
class CalendarEntry {
  const CalendarEntry(this.note, this.task, {this.repeatPreview = false});
  final Note note;
  final NoteTask? task;

  /// A future occurrence of a repeating task (not its stored date).
  final bool repeatPreview;
}

/// Tasks by day for the month containing [month], including upcoming
/// occurrences of repeating tasks; daily notes by date.
({Map<DateTime, List<CalendarEntry>> tasks, Map<DateTime, Note> daily})
calendarMonth(Library lib, DateTime month, LibraryNotifier library) {
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1);
  final tasks = <DateTime, List<CalendarEntry>>{};
  final daily = <DateTime, Note>{};
  for (final stored in lib.notes.values) {
    if (stored.trashed) continue;
    final n = library.readable(stored.id) ?? stored;
    final date = DateTime.tryParse(n.dailyDate ?? '');
    if (date != null) daily[_day(date)] = n;
    for (final t in noteTasks(n)) {
      if (t.due == null) continue;
      var due = t.due!;
      var preview = false;
      var guard = 0;
      while (due.isBefore(last) && guard++ < 400) {
        if (!due.isBefore(first)) {
          tasks
              .putIfAbsent(_day(due), () => [])
              .add(CalendarEntry(n, t, repeatPreview: preview));
        }
        if (t.repeat == null || t.done) break;
        due = t.repeat!.next(due);
        preview = true;
      }
    }
  }
  return (tasks: tasks, daily: daily);
}

class CalendarView extends ConsumerStatefulWidget {
  const CalendarView({super.key});

  @override
  ConsumerState<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends ConsumerState<CalendarView> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = _day(DateTime.now());

  void _open(String noteId) {
    ref.read(openNoteProvider.notifier).open(noteId);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lib = ref.watch(libraryProvider);
    final data = calendarMonth(lib, _month, ref.read(libraryProvider.notifier));
    final loc = MaterialLocalizations.of(context);
    final today = _day(DateTime.now());
    final firstWeekday = loc.firstDayOfWeekIndex; // 0 = Sunday
    final first = DateTime(_month.year, _month.month);
    final lead = (first.weekday % 7 - firstWeekday + 7) % 7;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((lead + days) / 7).ceil() * 7;
    final names = loc.narrowWeekdays;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 900;

    Widget grid = Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: Sp.xs),
                  child: Text(
                    names[(firstWeekday + i) % 7],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.textFaint,
                      fontSize: Fs.caption,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        Expanded(
          child: Column(
            children: [
              for (var row = 0; row < cells ~/ 7; row++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: () {
                            final index = row * 7 + col - lead;
                            if (index < 0 || index >= days) {
                              return const SizedBox.shrink();
                            }
                            final date = DateTime(
                              _month.year,
                              _month.month,
                              index + 1,
                            );
                            return _DayCell(
                              date: date,
                              today: date == today,
                              selected: date == _selected,
                              entries: data.tasks[date] ?? const [],
                              daily: data.daily[date],
                              onTap: () => setState(() => _selected = date),
                            );
                          }(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    final detail = _DayDetail(
      date: _selected,
      entries: [...?data.tasks[_selected]]
        ..sort((a, b) => a.task!.due!.compareTo(b.task!.due!)),
      daily: data.daily[_selected],
      onOpen: _open,
      onDaily: () {
        final note = ref.read(libraryProvider.notifier).dailyNoteFor(_selected);
        _open(note.id);
      },
      onToggle: (entry, done) {
        ref.read(persistenceProvider).flushEditors();
        final note = ref.read(libraryProvider.notifier).readable(entry.note.id);
        if (note == null || entry.task == null) return;
        final (body, next) = completeTask(note, entry.task!, done);
        ref.read(libraryProvider.notifier).updateContent(note.id, body: body);
        if (next != null) {
          showToast(
            context,
            context.tr('Repeats: next on {date}', {
              'date': dueLabel(context, next),
            }),
          );
        }
      },
    );

    return AppDialog(
      icon: Icons.calendar_month_outlined,
      title: context.tr('Calendar'),
      subtitle: context.tr('Task dates and daily notes'),
      width: math.min(1060, size.width - 32),
      height: math.min(760, size.height - 48),
      scrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
      headerActions: [
        AppIconButton(
          icon: Icons.chevron_left_rounded,
          tooltip: context.tr('Previous month'),
          onPressed: () =>
              setState(() => _month = DateTime(_month.year, _month.month - 1)),
        ),
        TextButton(
          onPressed: () => setState(() {
            _month = DateTime(today.year, today.month);
            _selected = today;
          }),
          child: Text(context.tr('Today')),
        ),
        AppIconButton(
          icon: Icons.chevron_right_rounded,
          tooltip: context.tr('Next month'),
          onPressed: () =>
              setState(() => _month = DateTime(_month.year, _month.month + 1)),
        ),
        const SizedBox(width: Sp.sm),
      ],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: Text(
              loc.formatMonthYear(_month),
              style: TextStyle(
                color: p.text,
                fontSize: Fs.heading,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: grid),
                      const SizedBox(width: Sp.md),
                      SizedBox(width: 300, child: detail),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(flex: 3, child: grid),
                      const SizedBox(height: Sp.sm),
                      Expanded(flex: 2, child: detail),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.today,
    required this.selected,
    required this.entries,
    required this.daily,
    required this.onTap,
  });

  final DateTime date;
  final bool today, selected;
  final List<CalendarEntry> entries;
  final Note? daily;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final open = entries.where((e) => !e.task!.done).toList();
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selected
            ? p.accent.withValues(alpha: .14)
            : p.codeBg.withValues(alpha: .6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: BorderSide(
            color: selected ? p.accent : p.border.withValues(alpha: .6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Rad.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Sp.xs + 1),
            child: LayoutBuilder(
              builder: (context, c) {
                final rows = math.max(0, ((c.maxHeight - 22) / 17).floor());
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: today
                              ? BoxDecoration(
                                  color: p.accent,
                                  borderRadius: BorderRadius.circular(Rad.pill),
                                )
                              : null,
                          child: Text(
                            '${date.day}',
                            style: TextStyle(
                              color: today ? p.onAccent : p.text,
                              fontSize: Fs.small,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (daily != null)
                          Tooltip(
                            message: context.tr('Daily note'),
                            child: Icon(
                              Icons.today_outlined,
                              size: 13,
                              color: p.accent,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    for (final e in open.take(
                      open.length > rows ? math.max(0, rows - 1) : rows,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 1),
                        child: Row(
                          children: [
                            Container(
                              width: 3,
                              height: 12,
                              margin: const EdgeInsets.only(right: 4),
                              color: priorityColor(e.task!.priority, p),
                            ),
                            Expanded(
                              child: Text(
                                e.task!.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: e.repeatPreview ? p.textMuted : p.text,
                                  fontSize: Fs.micro,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (open.length > rows && rows > 0)
                      Text(
                        '+${open.length - math.max(0, rows - 1)}',
                        style: TextStyle(
                          color: p.textFaint,
                          fontSize: Fs.micro,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DayDetail extends StatelessWidget {
  const _DayDetail({
    required this.date,
    required this.entries,
    required this.daily,
    required this.onOpen,
    required this.onDaily,
    required this.onToggle,
  });

  final DateTime date;
  final List<CalendarEntry> entries;
  final Note? daily;
  final ValueChanged<String> onOpen;
  final VoidCallback onDaily;
  final void Function(CalendarEntry entry, bool done) onToggle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: p.border),
      ),
      padding: const EdgeInsets.all(Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            MaterialLocalizations.of(context).formatFullDate(date),
            style: TextStyle(color: p.text, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: Sp.sm),
          OutlinedButton.icon(
            onPressed: daily == null ? onDaily : () => onOpen(daily!.id),
            icon: const Icon(Icons.today_outlined, size: 18),
            label: Text(
              context.tr(
                daily == null ? 'Create daily note' : 'Open daily note',
              ),
            ),
          ),
          const SizedBox(height: Sp.md),
          DialogLabel(context.tr('Tasks')),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      context.tr('Nothing due this day'),
                      style: TextStyle(color: p.textFaint, fontSize: Fs.small),
                    ),
                  )
                : ListView(
                    children: [
                      for (final e in entries)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Rad.md),
                            onTap: () => onOpen(e.note.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: e.task!.done,
                                    onChanged: e.repeatPreview
                                        ? null
                                        : (v) => onToggle(e, v ?? false),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          e.task!.text,
                                          style: TextStyle(
                                            color: e.task!.done
                                                ? p.textMuted
                                                : p.text,
                                            decoration: e.task!.done
                                                ? TextDecoration.lineThrough
                                                : null,
                                            fontSize: Fs.label,
                                          ),
                                        ),
                                        Text(
                                          [
                                            e.note.displayTitle,
                                            if (e.task!.repeat != null)
                                              context.tr(e.task!.repeat!.label),
                                          ].join(' · '),
                                          style: TextStyle(
                                            color: p.textFaint,
                                            fontSize: Fs.caption,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (e.task!.priority != TaskPriority.none)
                                    Icon(
                                      Icons.flag_rounded,
                                      size: 15,
                                      color: priorityColor(e.task!.priority, p),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
