import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../application/persistence_coordinator.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/repository/library_repository.dart';
import '../../data/repository/note_history_store.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../dialogs/dialogs.dart';
import '../../application/ui_providers.dart';
import '../../domain/text_diff.dart';

/// What the right-hand pane shows for the selected version.
enum _Compare { content, current, previous }

Future<void> showNoteHistory(
  BuildContext context,
  WidgetRef ref,
  String id,
) async {
  await ref.read(persistenceProvider).flush();
  final repository = ref.read(libraryRepositoryProvider);
  if (repository is! FileLibraryRepository || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _History(id: id, store: repository.history),
  );
}

class _History extends ConsumerStatefulWidget {
  const _History({required this.id, required this.store});
  final String id;
  final NoteHistoryStore store;
  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  List<NoteRevision>? _revisions;
  NoteRevision? _selected;
  _Compare _compare = _Compare.current;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final revisions = await widget.store.read(widget.id);
      if (mounted) setState(() => _revisions = revisions.reversed.toList());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _checkpoint() async {
    setState(() => _busy = true);
    try {
      await widget.store.record(
        ref.read(libraryProvider).notes[widget.id]!,
        force: true,
      );
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    final old = _selected;
    if (old == null) return;
    final ok = await confirmAction(
      context,
      title: context.tr('Restore this version?'),
      message: context.tr(
        'The current version will be saved before restoring.',
      ),
      confirmLabel: context.tr('Restore'),
      destructive: false,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final current = ref.read(libraryProvider).notes[widget.id]!;
      await widget.store.record(current, force: true);
      ref
          .read(libraryProvider.notifier)
          .updateContent(widget.id, title: old.note.title, body: old.note.body);
      await ref
          .read(libraryProvider.notifier)
          .setCover(widget.id, old.note.coverImage);
      await ref.read(persistenceProvider).flush();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _busy = false;
        });
      }
    }
  }

  Widget _versions() {
    final p = context.palette;
    if (_revisions == null) {
      return DialogEmptyState(
        loading: _error == null,
        icon: Icons.error_outline_rounded,
        message: _error ?? context.tr('Loading…'),
      );
    }
    if (_revisions!.isEmpty) {
      return DialogEmptyState(
        icon: Icons.history_rounded,
        message: context.tr('No earlier versions yet'),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(Sp.sm),
      children: [
        for (final revision in _revisions!)
          DialogListItem(
            selected: _selected == revision,
            leading: const Icon(Icons.schedule_rounded),
            title: Text(
              MaterialLocalizations.of(
                context,
              ).formatFullDate(revision.savedAt),
              style: const TextStyle(fontSize: Fs.small + .5),
            ),
            subtitle: Text(
              '${TimeOfDay.fromDateTime(revision.savedAt).format(context)} · ${revision.note.displayTitle}',
            ),
            trailing: _selected == revision
                ? Icon(Icons.chevron_right_rounded, size: 18, color: p.accent)
                : const SizedBox.shrink(),
            onTap: () => setState(() => _selected = revision),
          ),
      ],
    );
  }

  Widget _preview() {
    final selected = _selected;
    if (selected == null) {
      return DialogEmptyState(
        icon: Icons.touch_app_outlined,
        message: context.tr('Select a version'),
      );
    }
    final at = _revisions!.indexOf(selected);
    final previous = at + 1 < _revisions!.length ? _revisions![at + 1] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, 0),
          child: SegmentedButton<_Compare>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _Compare.current,
                label: Text(context.tr('Changes since')),
                tooltip: context.tr('Compare with the current note'),
              ),
              ButtonSegment(
                value: _Compare.previous,
                enabled: previous != null,
                label: Text(context.tr('What changed')),
                tooltip: context.tr('Compare with the version before it'),
              ),
              ButtonSegment(
                value: _Compare.content,
                label: Text(context.tr('Content')),
              ),
            ],
            selected: {
              _compare == _Compare.previous && previous == null
                  ? _Compare.current
                  : _compare,
            },
            onSelectionChanged: (v) => setState(() => _compare = v.first),
          ),
        ),
        Expanded(
          child: switch (_compare) {
            _Compare.content => _content(selected),
            _Compare.previous when previous != null => _DiffView(
              key: ValueKey('prev:${selected.savedAt}'),
              beforeTitle: previous.note.title,
              afterTitle: selected.note.title,
              before: previous.note.body,
              after: selected.note.body,
            ),
            _ => _DiffView(
              key: ValueKey('cur:${selected.savedAt}'),
              beforeTitle: selected.note.title,
              afterTitle: ref.read(noteProvider(widget.id))?.title ?? '',
              before: selected.note.body,
              after: ref.read(noteProvider(widget.id))?.body ?? '',
            ),
          },
        ),
      ],
    );
  }

  Widget _content(NoteRevision selected) {
    final p = context.palette;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selected.note.displayTitle,
            style: TextStyle(
              color: p.text,
              fontSize: Fs.title + 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: Sp.md),
          SelectableText(
            selected.note.body,
            style: AppTheme.mono(size: 12.5, color: p.text),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget pane(Widget child, {Color? color}) => Container(
      decoration: BoxDecoration(
        color: color ?? p.codeBg,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
    return AppDialog(
      icon: Icons.history_rounded,
      title: context.tr('Version history'),
      width: 940,
      height: MediaQuery.sizeOf(context).height * .8,
      scrollable: false,
      bodyPadding: const EdgeInsets.all(Sp.lg),
      content: LayoutBuilder(
        builder: (_, cons) => cons.maxWidth >= 650
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 290, child: pane(_versions())),
                  const SizedBox(width: Sp.md),
                  Expanded(child: pane(_preview(), color: p.editorBg)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: 180, child: pane(_versions())),
                  const SizedBox(height: Sp.md),
                  Expanded(child: pane(_preview(), color: p.editorBg)),
                ],
              ),
      ),
      footerLeading: _error != null
          ? Text(
              _error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.danger, fontSize: Fs.small),
            )
          : TextButton.icon(
              onPressed: _busy ? null : _checkpoint,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(context.tr('Save current version')),
            ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(context.tr('Close')),
        ),
        FilledButton.icon(
          onPressed:
              _selected == null ||
                  _busy ||
                  ref.watch(libraryProvider).notes[widget.id]?.trashed != false
              ? null
              : _restore,
          icon: const Icon(Icons.restore_rounded),
          label: Text(context.tr('Restore')),
        ),
      ],
    );
  }
}

/// Line diff between two versions: unified, with removed lines in red,
/// added lines in green and long unchanged stretches folded.
class _DiffView extends StatefulWidget {
  const _DiffView({
    super.key,
    required this.before,
    required this.after,
    required this.beforeTitle,
    required this.afterTitle,
  });
  final String before, after, beforeTitle, afterTitle;

  @override
  State<_DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<_DiffView> {
  late final TextDiff _diff = TextDiff.of(widget.before, widget.after);
  final Set<int> _expanded = {};
  static const _context = 3;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lines = _diff.lines;
    if (_diff.isEmpty && widget.beforeTitle == widget.afterTitle) {
      return DialogEmptyState(
        icon: Icons.check_circle_outline_rounded,
        message: context.tr('No differences'),
      );
    }
    // Rows: either a line index or a folded run (start, length).
    final rows = <Object>[];
    var i = 0;
    while (i < lines.length) {
      if (lines[i].kind != DiffKind.same) {
        rows.add(i++);
        continue;
      }
      var j = i;
      while (j < lines.length && lines[j].kind == DiffKind.same) {
        j++;
      }
      final keepStart = i == 0 ? 0 : _context;
      final keepEnd = j == lines.length ? 0 : _context;
      if (j - i > keepStart + keepEnd + 2 && !_expanded.contains(i)) {
        for (var k = i; k < i + keepStart; k++) {
          rows.add(k);
        }
        rows.add((i + keepStart, j - i - keepStart - keepEnd, i));
        for (var k = j - keepEnd; k < j; k++) {
          rows.add(k);
        }
      } else {
        for (var k = i; k < j; k++) {
          rows.add(k);
        }
      }
      i = j;
    }
    final mono = AppTheme.mono(size: 12.5, color: p.text, height: 1.5);
    Widget number(int? n) => SizedBox(
      width: 40,
      child: Text(
        n?.toString() ?? '',
        textAlign: TextAlign.right,
        style: mono.copyWith(color: p.textFaint, fontSize: 11),
      ),
    );

    Widget lineRow(int index) {
      final line = lines[index];
      final (Color? bg, Color sign, String mark) = switch (line.kind) {
        DiffKind.added => (p.success.withValues(alpha: .13), p.success, '+'),
        DiffKind.removed => (
          p.danger.withValues(alpha: .13),
          p.danger,
          '\u2212',
        ),
        DiffKind.same => (null, p.textFaint, ' '),
      };
      // Highlight the changed part of a line that replaced a single line.
      InlineSpan text = TextSpan(text: line.text);
      final partner = switch (line.kind) {
        DiffKind.removed
            when index + 1 < lines.length &&
                lines[index + 1].kind == DiffKind.added &&
                (index == 0 || lines[index - 1].kind != DiffKind.removed) =>
          lines[index + 1],
        DiffKind.added
            when index > 0 &&
                lines[index - 1].kind == DiffKind.removed &&
                (index + 1 >= lines.length ||
                    lines[index + 1].kind != DiffKind.added) =>
          lines[index - 1],
        _ => null,
      };
      if (partner != null) {
        final (a, b) = changedSpan(line.text, partner.text);
        if (b > a && b - a < line.text.length) {
          text = TextSpan(
            children: [
              TextSpan(text: line.text.substring(0, a)),
              TextSpan(
                text: line.text.substring(a, b),
                style: TextStyle(backgroundColor: sign.withValues(alpha: .28)),
              ),
              TextSpan(text: line.text.substring(b)),
            ],
          );
        }
      }
      return Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            number(line.oldLine),
            number(line.newLine),
            SizedBox(
              width: 22,
              child: Text(
                mark,
                textAlign: TextAlign.center,
                style: mono.copyWith(color: sign, fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(child: Text.rich(text, style: mono)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Sp.md),
          child: Wrap(
            spacing: Sp.md,
            runSpacing: Sp.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '+${_diff.added}',
                style: TextStyle(color: p.success, fontWeight: FontWeight.w700),
              ),
              Text(
                '\u2212${_diff.removed}',
                style: TextStyle(color: p.danger, fontWeight: FontWeight.w700),
              ),
              Text(
                context.tr('lines'),
                style: TextStyle(color: p.textMuted, fontSize: Fs.small),
              ),
              if (widget.beforeTitle != widget.afterTitle)
                Text(
                  context.tr('Title: "{a}" \u2192 "{b}"', {
                    'a': widget.beforeTitle,
                    'b': widget.afterTitle,
                  }),
                  style: TextStyle(color: p.textMuted, fontSize: Fs.small),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: p.border),
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: Sp.sm),
              itemCount: rows.length,
              itemBuilder: (context, r) {
                final row = rows[r];
                if (row is int) return lineRow(row);
                final (_, count, key) = row as (int, int, int);
                return InkWell(
                  onTap: () => setState(() => _expanded.add(key)),
                  child: Container(
                    color: p.codeBg,
                    padding: const EdgeInsets.symmetric(vertical: Sp.xs),
                    alignment: Alignment.center,
                    child: Text(
                      context.tr('{n} unchanged lines \u2014 show', {
                        'n': count,
                      }),
                      style: TextStyle(
                        color: p.textFaint,
                        fontSize: Fs.caption,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
