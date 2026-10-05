import '../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/actions.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/note.dart';
import '../settings/settings_dialog.dart';
import '../templates/templates_dialog.dart';
import '../dialogs/import_dialog.dart';
import '../../application/persistence_coordinator.dart';
import '../../application/note_vault.dart';
import '../../core/widgets/highlighted_text.dart';
import '../../core/widgets/status_visuals.dart';
import '../../data/pdf_export_service.dart';
import '../../domain/search_query.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/searchable_picker.dart';
import '../editor/note_history_dialog.dart';
import '../editor/note_lock.dart';
import '../graph/graph_view.dart';
import '../shell/note_window.dart';
import '../dialogs/calendar_view.dart';
import '../dialogs/task_dashboard.dart';
import '../../application/shortcuts.dart';

class _Entry {
  const _Entry({
    required this.title,
    required this.icon,
    required this.action,
    this.hint,
    this.subtitle,
    this.words = const {},
    this.note = false,
  });
  final String title;
  final String? hint;

  /// Second line: where a note matched, or its notebook.
  final String? subtitle;

  /// Search words to highlight in [title] and [subtitle].
  final Set<String> words;
  final IconData icon;
  final VoidCallback action;
  final bool note;
}

Future<void> showCommandPalette(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (_) =>
        const Align(alignment: Alignment(0, -0.6), child: _Palette()),
  );
}

class _Palette extends ConsumerStatefulWidget {
  const _Palette();

  @override
  ConsumerState<_Palette> createState() => _PaletteState();
}

class _PaletteState extends ConsumerState<_Palette> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  int _index = 0;
  static const double _rowHeight = 52;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static bool _fuzzy(String text, String query) {
    if (query.isEmpty) return true;
    final t = text.toLowerCase();
    final q = query.toLowerCase();
    if (t.contains(q)) return true;
    var i = 0;
    for (var k = 0; k < t.length && i < q.length; k++) {
      if (t[k] == q[i]) i++;
    }
    return i == q.length;
  }

  List<_Entry> _commands(BuildContext ctx) {
    final container = ProviderScope.containerOf(context);
    final keys = ref.read(shortcutsProvider);
    void close() => Navigator.of(context).pop();

    return [
      _Entry(
        title: context.tr('Import files'),
        icon: Icons.file_upload_outlined,
        action: () {
          close();
          showImportDialog(ctx);
        },
      ),
      _Entry(
        title: context.tr('Import from Obsidian, Notion, Evernote, Joplin…'),
        icon: Icons.move_down_rounded,
        action: () {
          final navigator = Navigator.of(context);
          close();
          showImportSourcePicker(navigator.context);
        },
      ),
      _Entry(
        title: context.tr('Import from folder…'),
        icon: Icons.folder_open_outlined,
        action: () {
          close();
          showImportDialog(ctx, folder: true);
        },
      ),
      _Entry(
        title: context.tr('New note'),
        hint: keys[AppShortcut.newNote]!.label,
        icon: Icons.edit_square,
        action: () {
          close();
          createNoteInContext(container);
        },
      ),
      _Entry(
        title: context.tr('New code note (Python)'),
        icon: Icons.terminal_rounded,
        action: () {
          close();
          createNoteInContext(
            container,
            kind: NoteKind.code,
            language: 'python',
          );
        },
      ),
      _Entry(
        title: context.tr('New code note (JavaScript)'),
        icon: Icons.javascript_rounded,
        action: () {
          close();
          createNoteInContext(
            container,
            kind: NoteKind.code,
            language: 'javascript',
          );
        },
      ),
      _Entry(
        title: context.tr('Note templates\u2026'),
        icon: Icons.dashboard_customize_outlined,
        action: () {
          close();
          showTemplatesDialog(ctx);
        },
      ),
      _Entry(
        title: context.tr('Toggle sidebar'),
        hint: keys[AppShortcut.toggleSidebar]!.label,
        icon: Icons.view_sidebar_outlined,
        action: () {
          close();
          container.read(sidebarVisibleProvider.notifier).toggle();
        },
      ),
      _Entry(
        title: context.tr('Toggle focus mode'),
        hint: keys[AppShortcut.focusMode]!.label,
        icon: Icons.open_in_full_rounded,
        action: () {
          close();
          container.read(focusModeProvider.notifier).toggle();
        },
      ),
      _Entry(
        title: context.tr('Toggle AI assistant'),
        hint: keys[AppShortcut.aiAssistant]!.label,
        icon: Icons.auto_awesome_rounded,
        action: () {
          close();
          container.read(aiPanelVisibleProvider.notifier).toggle();
        },
      ),
      _Entry(
        title: context.tr('Toggle outline'),
        icon: Icons.list_alt_rounded,
        action: () {
          close();
          container.read(outlineVisibleProvider.notifier).toggle();
        },
      ),
      for (final m in ViewMode.values)
        _Entry(
          title: context.tr('View: {name}', {
            'name': context.tr(switch (m) {
              ViewMode.edit => 'Editor',
              ViewMode.split => 'Split',
              ViewMode.preview => 'Preview',
            }),
          }),
          icon: switch (m) {
            ViewMode.edit => Icons.edit_outlined,
            ViewMode.split => Icons.vertical_split_outlined,
            ViewMode.preview => Icons.visibility_outlined,
          },
          action: () {
            close();
            container.read(viewModeProvider.notifier).set(m);
          },
        ),
      for (final pal in Palettes.all)
        _Entry(
          title: context.tr('Theme: {name}', {'name': context.tr(pal.name)}),
          icon: Icons.palette_outlined,
          action: () {
            close();
            container
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(themeId: pal.id));
          },
        ),
      _Entry(
        title: context.tr('Recently opened'),
        icon: Icons.history_rounded,
        action: () {
          close();
          container
              .read(navFilterProvider.notifier)
              .select(const NavFilter.recent());
          container.read(notesOverviewProvider.notifier).set(false);
        },
      ),
      _Entry(
        title: context.tr('Starred'),
        icon: Icons.star_outline_rounded,
        action: () {
          close();
          container
              .read(navFilterProvider.notifier)
              .select(const NavFilter.starred());
          container.read(notesOverviewProvider.notifier).set(false);
        },
      ),
      _Entry(
        title: context.tr('Tasks'),
        icon: Icons.checklist_rounded,
        action: () {
          final navigator = Navigator.of(context);
          close();
          showTaskDashboard(navigator.context);
        },
      ),
      _Entry(
        title: context.tr('Calendar'),
        icon: Icons.calendar_month_outlined,
        action: () {
          final navigator = Navigator.of(context);
          close();
          showCalendarView(navigator.context);
        },
      ),
      _Entry(
        title: context.tr('Link graph'),
        icon: Icons.hub_outlined,
        action: () {
          final navigator = Navigator.of(context);
          close();
          showGraphView(navigator.context);
        },
      ),
      _Entry(
        title: context.tr('Next tab'),
        hint: keys[AppShortcut.nextTab]!.label,
        icon: Icons.keyboard_tab_rounded,
        action: () {
          close();
          container.read(persistenceProvider).flushEditors();
          container.read(openNoteProvider.notifier).cycleTab(1);
        },
      ),
      _Entry(
        title: context.tr('Previous tab'),
        hint: keys[AppShortcut.previousTab]!.label,
        icon: Icons.keyboard_tab_rounded,
        action: () {
          close();
          container.read(persistenceProvider).flushEditors();
          container.read(openNoteProvider.notifier).cycleTab(-1);
        },
      ),
      _Entry(
        title: context.tr('Open trash'),
        icon: Icons.delete_outline_rounded,
        action: () {
          close();
          container
              .read(navFilterProvider.notifier)
              .select(const NavFilter.trash());
        },
      ),
      _Entry(
        title: context.tr('Settings'),
        hint: keys[AppShortcut.settings]!.label,
        icon: Icons.settings_outlined,
        action: () {
          close();
          showSettingsDialog(ctx);
        },
      ),
    ];
  }

  /// Commands for the open note (move, tag, status, export, history...).
  List<_Entry> _noteCommands() {
    final id = ref.read(openNoteIdProvider);
    final note = id == null ? null : ref.read(noteProvider(id));
    if (note == null || note.trashed) return const [];
    final container = ProviderScope.containerOf(context);
    final navigator = Navigator.of(context);
    final library = container.read(libraryProvider.notifier);
    final title = note.displayTitle;
    // Dialogs open from the navigator's context: the palette's own context
    // is gone once it closes.
    BuildContext host() => navigator.context;
    void close() => navigator.pop();
    String forNote(String label) => '$label \u2014 $title';

    return [
      _Entry(
        title: forNote(context.tr('Move to notebook\u2026')),
        icon: Icons.drive_file_move_outline,
        action: () async {
          close();
          final lib = container.read(libraryProvider);
          final chosen = await showSearchablePicker<String>(
            host(),
            title: context.tr('Move to notebook'),
            selected: note.notebookId,
            options: [
              for (final nb in lib.notebooks)
                PickerOption(
                  nb.id,
                  nb.isInbox ? context.tr('General') : lib.notebookPath(nb.id),
                  icon: nb.isInbox
                      ? Icons.inbox_outlined
                      : Icons.folder_outlined,
                ),
            ],
          );
          if (chosen != null) library.setNotebook(note.id, chosen);
        },
      ),
      _Entry(
        title: forNote(context.tr('Add or remove tag\u2026')),
        icon: Icons.sell_outlined,
        action: () async {
          close();
          final lib = container.read(libraryProvider);
          final chosen = await showSearchablePicker<String>(
            host(),
            title: context.tr('Tags'),
            options: [
              for (final t in lib.tags)
                PickerOption(
                  t.id,
                  t.name,
                  icon: note.tagIds.contains(t.id)
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                ),
            ],
          );
          if (chosen != null) library.toggleTag(note.id, chosen);
        },
      ),
      _Entry(
        title: forNote(context.tr('Change status\u2026')),
        icon: Icons.flag_outlined,
        action: () async {
          close();
          final palette = context.palette;
          final chosen = await showSearchablePicker<NoteStatus>(
            host(),
            title: context.tr('Status'),
            selected: note.status,
            options: [
              for (final st in NoteStatus.values)
                PickerOption(
                  st,
                  context.tr(st.label),
                  icon: statusVisual(st, palette).icon,
                ),
            ],
          );
          if (chosen != null) library.setStatus(note.id, chosen);
        },
      ),
      _Entry(
        title: forNote(
          context.tr(note.starred ? 'Remove from starred' : 'Add to starred'),
        ),
        icon: note.starred ? Icons.star_rounded : Icons.star_outline_rounded,
        action: () {
          close();
          library.toggleStar(note.id);
        },
      ),
      _Entry(
        title: forNote(context.tr(note.pinned ? 'Unpin' : 'Pin to top')),
        icon: note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        action: () {
          close();
          library.togglePin(note.id);
        },
      ),
      _Entry(
        title: forNote(context.tr('Export PDF')),
        icon: Icons.picture_as_pdf_outlined,
        action: () {
          close();
          container.read(persistenceProvider).flushEditors();
          final current = container.read(noteProvider(note.id));
          if (current != null) PdfExportService.export(host(), current);
        },
      ),
      _Entry(
        title: forNote(context.tr('Print')),
        icon: Icons.print_outlined,
        action: () {
          close();
          container.read(persistenceProvider).flushEditors();
          final current = container.read(noteProvider(note.id));
          if (current != null) {
            PdfExportService.export(host(), current, print: true);
          }
        },
      ),
      if (!note.isLocked)
        _Entry(
          title: forNote(context.tr('Version history')),
          icon: Icons.history,
          action: () {
            close();
            container.read(persistenceProvider).flushEditors();
            showNoteHistory(host(), ref, note.id);
          },
        ),
      _Entry(
        title: forNote(context.tr('Duplicate')),
        icon: Icons.copy_all_rounded,
        action: () {
          close();
          container.read(persistenceProvider).flushEditors();
          final copy = library.duplicate(note.id);
          if (copy != null) {
            container.read(openNoteProvider.notifier).open(copy.id);
          }
        },
      ),
      if (!note.isLocked)
        _Entry(
          title: forNote(context.tr('Lock with password\u2026')),
          icon: Icons.lock_outline_rounded,
          action: () {
            close();
            container.read(persistenceProvider).flushEditors();
            showLockNoteDialog(host(), note.id);
          },
        )
      else if (container.read(noteVaultProvider).containsKey(note.id))
        _Entry(
          title: forNote(context.tr('Lock now')),
          icon: Icons.lock_rounded,
          action: () {
            close();
            container.read(noteVaultProvider.notifier).lock(note.id);
          },
        ),
      if (canOpenNoteWindows && ref.read(noteWindowProvider) == null)
        _Entry(
          title: forNote(context.tr('Open in new window')),
          icon: Icons.open_in_new_rounded,
          action: () {
            close();
            openNoteWindow(host(), ref, note.id);
          },
        ),
      _Entry(
        title: forNote(context.tr('Show in link graph')),
        icon: Icons.hub_outlined,
        action: () {
          close();
          showGraphView(host(), focusId: note.id);
        },
      ),
      _Entry(
        title: forNote(context.tr('Close tab')),
        hint: ref.read(shortcutsProvider)[AppShortcut.closeTab]!.label,
        icon: Icons.tab_unselected_rounded,
        action: () {
          close();
          container.read(persistenceProvider).flushEditors();
          container.read(openNoteProvider.notifier).closeTab(note.id);
        },
      ),
      _Entry(
        title: forNote(context.tr('Move to trash')),
        icon: Icons.delete_outline_rounded,
        action: () {
          close();
          container.read(persistenceProvider).flushEditors();
          library.trash(note.id);
          showToast(
            host(),
            context.tr('Moved to trash'),
            actionLabel: context.tr('Undo'),
            onAction: () => library.restore(note.id),
          );
        },
      ),
    ];
  }

  List<_Entry> _results(BuildContext ctx) {
    final raw = _controller.text;
    final commandsOnly = raw.startsWith('>');
    final q = (commandsOnly ? raw.substring(1) : raw).trim();
    final container = ProviderScope.containerOf(context);

    final commands = [
      ..._noteCommands(),
      ..._commands(ctx),
    ].where((c) => _fuzzy(c.title, q)).toList();
    if (commandsOnly) return commands;

    final lib = ref.read(libraryProvider);
    final List<Note> notes;
    final query = SearchQuery.parse(q);
    if (q.isEmpty) {
      // Nothing typed: the most recently opened notes.
      final recent = ref.read(recentNotesProvider);
      notes = recent
          .map((id) => lib.notes[id])
          .whereType<Note>()
          .where((n) => !n.trashed)
          .toList();
      if (notes.length < 6) {
        notes.addAll(
          (lib.notes.values
                  .where((n) => !n.trashed && !recent.contains(n.id))
                  .toList()
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
              .take(6 - notes.length),
        );
      }
    } else {
      // Same engine as the note list: titles, content, tags and filters.
      final scored = <(Note, int)>[];
      for (final n in lib.notes.values) {
        if (n.trashed) continue;
        final score = query.match(
          n,
          tagNames: [for (final id in n.tagIds) lib.tag(id)?.name ?? ''],
          notebookName: lib.notebook(n.notebookId)?.name,
        );
        if (score >= 0) scored.add((n, score));
      }
      scored.sort((a, b) {
        final c = b.$2.compareTo(a.$2);
        return c != 0 ? c : b.$1.updatedAt.compareTo(a.$1.updatedAt);
      });
      notes = [for (final e in scored) e.$1];
    }

    final noteEntries = notes.take(q.isEmpty ? 6 : 12).map((n) {
      final words = query.hasTerms ? query.highlightWords(n) : const <String>{};
      final inBody = words.isEmpty || n.isLocked
          ? null
          : snippetAround(n.body, words, max: 90);
      return _Entry(
        title: n.displayTitle,
        subtitle: inBody ?? lib.notebookPath(n.notebookId),
        words: words,
        hint: n.starred ? '\u2605' : null,
        icon: n.isLocked
            ? Icons.lock_outline_rounded
            : n.kind == NoteKind.code
            ? Icons.code_rounded
            : Icons.description_outlined,
        note: true,
        action: () {
          Navigator.of(context).pop();
          container.read(openNoteProvider.notifier).open(n.id);
        },
      );
    });

    return [...noteEntries, ...commands];
  }

  void _move(int delta, int length) {
    if (length == 0) return;
    setState(() => _index = (_index + delta) % length);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _index * _rowHeight;
      final pos = _scroll.position;
      if (target < pos.pixels) {
        _scroll.jumpTo(target);
      } else if (target + _rowHeight > pos.pixels + pos.viewportDimension) {
        _scroll.jumpTo(target + _rowHeight - pos.viewportDimension);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final results = _results(context);
    if (_index >= results.length) _index = 0;

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 480),
        child: Container(
          margin: const EdgeInsets.all(Sp.lg),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Rad.lg),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      _move(1, results.length),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      _move(results.length - 1, results.length),
                  const SingleActivator(LogicalKeyboardKey.enter): () {
                    if (results.isNotEmpty) results[_index].action();
                  },
                },
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: (_) => setState(() => _index = 0),
                  style: const TextStyle(fontSize: Fs.title),
                  decoration: InputDecoration(
                    hintText: context.tr(
                      'Search notes and content, or type > for commands',
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.all(Sp.lg),
                    prefixIcon: Icon(Icons.search_rounded, color: p.textMuted),
                  ),
                ),
              ),
              Divider(height: 1, color: p.border),
              Flexible(
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(Sp.xl),
                        child: Text(
                          context.tr('No results'),
                          style: TextStyle(color: p.textMuted),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        itemExtent: _rowHeight,
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final e = results[i];
                          final selected = i == _index;
                          return InkWell(
                            borderRadius: BorderRadius.circular(Rad.md),
                            onTap: e.action,
                            child: Container(
                              decoration: BoxDecoration(
                                color: selected
                                    ? p.selection
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(Rad.md),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: Sp.lg,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    e.icon,
                                    size: 19,
                                    color: selected ? p.accent : p.textMuted,
                                  ),
                                  const SizedBox(width: Sp.md),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        HighlightedText(
                                          e.title,
                                          words: e.words,
                                          maxLines: 1,
                                          style: TextStyle(
                                            color: p.text,
                                            fontWeight: e.note
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                          ),
                                        ),
                                        if (e.subtitle != null &&
                                            e.subtitle!.isNotEmpty)
                                          HighlightedText(
                                            e.subtitle!,
                                            words: e.words,
                                            maxLines: 1,
                                            style: TextStyle(
                                              color: p.textFaint,
                                              fontSize: Fs.caption,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (e.hint != null)
                                    Text(
                                      e.hint!,
                                      style: TextStyle(
                                        color: p.textFaint,
                                        fontSize: Fs.caption,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
