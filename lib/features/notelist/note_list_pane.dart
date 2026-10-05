import '../../core/widgets/cover_image.dart';
import '../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/actions.dart';

import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/platform_info.dart';
import '../../core/util/time_ago.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../core/widgets/status_visuals.dart';
import '../../core/widgets/tag_chip.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/note.dart';
import '../../domain/languages.dart';
import '../../domain/markdown_utils.dart';
import '../dialogs/dialogs.dart';
import 'bulk_note_actions.dart';
import 'note_drag.dart';
import '../shell/note_window.dart';
import '../../core/widgets/highlighted_text.dart';
import '../../domain/search_query.dart';
import '../dialogs/import_dialog.dart';

/// Middle column: filter field + list of notes.
class NoteListPane extends ConsumerStatefulWidget {
  const NoteListPane({
    super.key,
    this.onOpen,
    this.onToggleSidebar,
    this.showSidebarToggle = false,
    this.leading,
  });

  /// Called after a note was selected (mobile pushes the editor route).
  final VoidCallback? onOpen;
  final VoidCallback? onToggleSidebar;
  final bool showSidebarToggle;
  final Widget? leading;

  @override
  ConsumerState<NoteListPane> createState() => _NoteListPaneState();
}

class _NoteListPaneState extends ConsumerState<NoteListPane> {
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _newNote({NoteKind kind = NoteKind.markdown, String? language}) {
    createNoteInContext(
      ProviderScope.containerOf(context),
      kind: kind,
      language: language,
    );
    widget.onOpen?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    ref.listen(
      navFilterProvider,
      (_, next) => ref.read(noteSelectionProvider.notifier).clear(),
    );
    final selection = ref.watch(noteSelectionProvider);
    final notes = ref.watch(visibleNotesProvider);
    final rawTitle = ref.watch(navTitleProvider);
    final nav = ref.watch(navFilterProvider);
    final title = nav.kind == NavKind.notebook || nav.kind == NavKind.tag
        ? (nav.kind == NavKind.notebook &&
                  ref.watch(libraryProvider).notebook(nav.id)?.isInbox == true
              ? context.tr('General')
              : rawTitle)
        : context.tr(rawTitle);
    final query = ref.watch(searchTextProvider);
    final selectedId = ref.watch(openNoteIdProvider);
    final settings = ref.watch(settingsProvider);

    // Keep the field in sync when the query is cleared elsewhere.
    if (query.isEmpty &&
        _filter.text.isNotEmpty &&
        !ref.read(searchTextProvider.notifier).pending) {
      _filter.clear();
    }

    return ColoredBox(
      color: p.listBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                child: Row(
                  children: [
                    if (widget.leading != null)
                      widget.leading!
                    else if (widget.showSidebarToggle)
                      AppIconButton(
                        icon: Icons.view_sidebar_outlined,
                        tooltip: context.tr('Toggle sidebar'),
                        onPressed: widget.onToggleSidebar,
                      )
                    else
                      const SizedBox(width: Sp.sm),
                    const SizedBox(width: Sp.xs),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.text,
                          fontSize: Fs.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.edit_square,
                      tooltip: context.tr('New note ({key}+N)', {
                        'key': PlatformInfo.modKey,
                      }),
                      onPressed: _newNote,
                    ),
                    PopupMenuButton<String>(
                      borderRadius: BorderRadius.circular(Rad.md),
                      tooltip: context.tr('More actions'),
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        color: p.textMuted,
                        size: 20,
                      ),
                      onSelected: (id) {
                        if (id == '__select__') {
                          ref.read(noteSelectionProvider.notifier).toggleMode();
                        } else if (id == '__other__') {
                          showImportSourcePicker(context);
                        } else if (id == '__import__' || id == '__folder__') {
                          showImportDialog(context, folder: id == '__folder__');
                        } else {
                          _newNote(kind: NoteKind.code, language: id);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: '__select__',
                          child: Text(
                            context.tr(
                              selection.enabled
                                  ? 'Cancel selection'
                                  : 'Select notes',
                            ),
                          ),
                        ),
                        if (nav.kind != NavKind.trash)
                          PopupMenuItem(
                            value: '__import__',
                            child: Text(context.tr('Import files')),
                          ),
                        if (nav.kind != NavKind.trash)
                          PopupMenuItem(
                            value: '__folder__',
                            child: Text(context.tr('Import from folder…')),
                          ),
                        if (nav.kind != NavKind.trash)
                          PopupMenuItem(
                            value: '__other__',
                            child: Text(
                              context.tr(
                                'Import from Obsidian, Notion, Evernote, Joplin…',
                              ),
                            ),
                          ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          enabled: false,
                          height: 30,
                          child: Text(
                            context.tr('New code note'),
                            style: TextStyle(
                              color: p.sectionLabel,
                              fontSize: Fs.caption,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (final l in Languages.runnable.where(
                          (l) => l.toolchains.isNotEmpty,
                        ))
                          PopupMenuItem(
                            value: l.id,
                            height: 36,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.code_rounded,
                                  size: 16,
                                  color: p.textMuted,
                                ),
                                const SizedBox(width: Sp.sm),
                                Text(l.name),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (widget.showSidebarToggle)
                      AppIconButton(
                        icon: Icons.close_rounded,
                        tooltip: context.tr('Hide note list'),
                        onPressed: () => ref
                            .read(noteListVisibleProvider.notifier)
                            .set(false),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.sm),
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _filter,
                focusNode: ref.watch(filterFocusProvider),
                onChanged: ref.read(searchTextProvider.notifier).debounce,
                style: const TextStyle(fontSize: Fs.body),
                decoration: InputDecoration(
                  hintText: context.tr('Filter'),
                  contentPadding: EdgeInsets.zero,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: p.textFaint,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (query.isNotEmpty)
                        AppIconButton(
                          icon: Icons.close_rounded,
                          tooltip: context.tr('Clear filter'),
                          size: 16,
                          onPressed: () {
                            _filter.clear();
                            ref.read(searchTextProvider.notifier).set('');
                          },
                        ),
                      _SortMenu(settings: settings),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (nav.kind == NavKind.trash && notes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.md, 0, Sp.md, Sp.sm),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: p.danger),
                  onPressed: () async {
                    final ok = await confirmAction(
                      context,
                      title: context.tr('Empty trash?'),
                      message: context.tr(
                        '{n} note(s) will be deleted permanently.',
                        {'n': notes.length},
                      ),
                      confirmLabel: context.tr('Empty trash'),
                    );
                    if (ok) ref.read(libraryProvider.notifier).emptyTrash();
                  },
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: Text(context.tr('Empty trash')),
                ),
              ),
            ),
          Divider(height: 1, color: p.border),
          Expanded(
            child: notes.isEmpty
                ? _EmptyList(
                    searching: query.trim().isNotEmpty,
                    trash: nav.kind == NavKind.trash,
                    onNew: _newNote,
                  )
                : Scrollbar(
                    child: ListView.builder(
                      itemCount: notes.length,
                      itemBuilder: (context, i) {
                        final n = notes[i];
                        final tile = NoteTile(
                          key: ValueKey(n.id),
                          note: n,
                          selected: n.id == selectedId,
                          onTap: () {
                            if (selection.enabled) {
                              ref
                                  .read(noteSelectionProvider.notifier)
                                  .toggle(n.id);
                              return;
                            }
                            ref.read(openNoteProvider.notifier).open(n.id);
                            widget.onOpen?.call();
                          },
                        );
                        return selection.enabled
                            ? Row(
                                children: [
                                  Checkbox(
                                    value: selection.ids.contains(n.id),
                                    onChanged: (_) => ref
                                        .read(noteSelectionProvider.notifier)
                                        .toggle(n.id),
                                  ),
                                  Expanded(child: tile),
                                ],
                              )
                            : tile;
                      },
                    ),
                  ),
          ),
          BulkNoteActions(visibleIds: notes.map((n) => n.id).toList()),
        ],
      ),
    );
  }
}

class _SortMenu extends ConsumerWidget {
  const _SortMenu({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final n = ref.read(settingsProvider.notifier);

    PopupMenuItem<String> item(String v, String label, bool checked) =>
        PopupMenuItem(
          value: v,
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: checked
                    ? Icon(Icons.check_rounded, size: 18, color: p.accent)
                    : null,
              ),
              Text(label),
            ],
          ),
        );

    return PopupMenuButton<String>(
      borderRadius: BorderRadius.circular(Rad.md),
      tooltip: context.tr('Sort'),
      icon: Icon(Icons.swap_vert_rounded, size: 19, color: p.textFaint),
      onSelected: (v) {
        switch (v) {
          case 'updated':
            n.update((s) => s.copyWith(sortField: SortField.updated));
          case 'created':
            n.update((s) => s.copyWith(sortField: SortField.created));
          case 'title':
            n.update((s) => s.copyWith(sortField: SortField.title));
          case 'asc':
            n.update((s) => s.copyWith(sortAscending: true));
          case 'desc':
            n.update((s) => s.copyWith(sortAscending: false));
        }
      },
      itemBuilder: (_) => [
        item(
          'updated',
          context.tr('Last updated'),
          settings.sortField == SortField.updated,
        ),
        item(
          'created',
          context.tr('Date created'),
          settings.sortField == SortField.created,
        ),
        item(
          'title',
          context.tr('Title'),
          settings.sortField == SortField.title,
        ),
        const PopupMenuDivider(),
        item('desc', context.tr('Descending'), !settings.sortAscending),
        item('asc', context.tr('Ascending'), settings.sortAscending),
      ],
    );
  }
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({
    required this.searching,
    required this.trash,
    required this.onNew,
  });
  final bool searching;
  final bool trash;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final icon = searching
        ? Icons.search_off_rounded
        : (trash ? Icons.delete_outline_rounded : Icons.note_add_outlined);
    final text = searching
        ? context.tr('No notes match your filter')
        : (trash
              ? context.tr('Trash is empty')
              : context.tr('No notes here yet'));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: p.textFaint),
            const SizedBox(height: Sp.md),
            Text(
              text,
              style: TextStyle(color: p.textMuted, fontWeight: FontWeight.w600),
            ),
            if (searching) ...[
              const SizedBox(height: 4),
              Text(
                context.tr(
                  'Try operators like tag:work, status:active, lang:python, has:code',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textFaint, fontSize: Fs.small),
              ),
            ],
            if (!searching && !trash) ...[
              const SizedBox(height: Sp.lg),
              FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(context.tr('New note')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NoteTile extends ConsumerStatefulWidget {
  const NoteTile({
    super.key,
    required this.note,
    required this.selected,
    required this.onTap,
  });

  final Note note;
  final bool selected;
  final VoidCallback onTap;

  @override
  ConsumerState<NoteTile> createState() => _NoteTileState();
}

class _NoteTileState extends ConsumerState<NoteTile> {
  bool _hover = false;

  Future<void> _menu(Offset at) async {
    final p = context.palette;
    final n = widget.note;
    final lib = ref.read(libraryProvider.notifier);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;

    PopupMenuItem<String> mi(
      String v,
      IconData icon,
      String label, {
      Color? color,
    }) => PopupMenuItem(
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? p.textMuted),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    );

    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        overlay.globalToLocal(at) & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: n.trashed
          ? [
              mi(
                'restore',
                Icons.restore_from_trash_rounded,
                context.tr('Restore'),
              ),
              mi(
                'delete',
                Icons.delete_forever_outlined,
                context.tr('Delete permanently'),
                color: p.danger,
              ),
            ]
          : [
              mi(
                'pin',
                n.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                n.pinned ? context.tr('Unpin') : context.tr('Pin to top'),
              ),
              mi(
                'star',
                n.starred ? Icons.star_rounded : Icons.star_outline_rounded,
                n.starred
                    ? context.tr('Remove from starred')
                    : context.tr('Add to starred'),
              ),
              mi('duplicate', Icons.copy_all_rounded, context.tr('Duplicate')),
              if (canOpenNoteWindows)
                mi(
                  'window',
                  Icons.open_in_new_rounded,
                  context.tr('Open in new window'),
                ),
              const PopupMenuDivider(),
              mi(
                'trash',
                Icons.delete_outline_rounded,
                context.tr('Move to trash'),
                color: p.danger,
              ),
            ],
    );
    if (v == null || !mounted) return;
    switch (v) {
      case 'pin':
        lib.togglePin(n.id);
      case 'star':
        lib.toggleStar(n.id);
      case 'window':
        await openNoteWindow(context, ref, n.id);
      case 'duplicate':
        final copy = lib.duplicate(n.id);
        if (copy != null) ref.read(openNoteProvider.notifier).open(copy.id);
      case 'trash':
        lib.trash(n.id);
        showToast(
          context,
          context.tr('Moved to trash'),
          actionLabel: context.tr('Undo'),
          onAction: () => lib.restore(n.id),
        );
      case 'restore':
        lib.restore(n.id);
      case 'delete':
        final ok = await confirmAction(
          context,
          title: context.tr('Delete permanently?'),
          message: context.tr('This note will be removed for good.'),
        );
        if (ok) {
          if (ref.read(openNoteIdProvider) == n.id) {
            ref.read(openNoteProvider.notifier).close();
          }
          lib.deleteForever(n.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = widget.note;
    final lib = ref.watch(libraryProvider.select((l) => l.tags));
    final digest = NoteDigest.of(n);
    final progress = digest.progress;
    final status = statusVisual(n.status, p);
    final tags = [
      for (final id in n.tagIds)
        for (final t in lib)
          if (t.id == id) t,
    ];
    final selected = widget.selected;
    final words = ref.watch(searchHighlightProvider(n));
    final snippet = words.isEmpty
        ? digest.snippet
        : (snippetAround(n.body, words) ?? digest.snippet);
    final countdown = n.trashed
        ? trashCountdown(
            n.trashedAt,
            ref.watch(settingsProvider.select((s) => s.trashRetentionDays)),
          )
        : null;

    return NoteDraggable(
      noteId: n.id,
      title: n.displayTitle,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (d) => _menu(d.globalPosition),
          onLongPressStart: (d) => _menu(d.globalPosition),
          child: Semantics(
            button: true,
            selected: selected,
            label: context.tr('{title}, updated {time}', {
              'title': n.displayTitle,
              'time': timeAgo(n.updatedAt),
            }),
            child: Material(
              borderRadius: BorderRadius.circular(Rad.md),
              clipBehavior: Clip.antiAlias,
              color: selected
                  ? p.selection
                  : (_hover ? p.hover : Colors.transparent),
              child: InkWell(
                borderRadius: BorderRadius.circular(Rad.md),
                onTap: widget.onTap,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    Sp.lg,
                    Sp.md,
                    Sp.md,
                    Sp.md,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: p.border.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (n.isLocked)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: Sp.xs,
                                      top: 2,
                                    ),
                                    child: Icon(
                                      Icons.lock_rounded,
                                      size: 14,
                                      color: p.textMuted,
                                    ),
                                  ),
                                if (n.pinned)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: Sp.xs,
                                      top: 2,
                                    ),
                                    child: Icon(
                                      Icons.push_pin,
                                      size: 14,
                                      color: p.accent,
                                    ),
                                  ),
                                if (n.starred)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: Sp.xs,
                                      top: 1,
                                    ),
                                    child: Icon(
                                      Icons.star_rounded,
                                      size: 15,
                                      color: p.warning,
                                    ),
                                  ),
                                if (n.kind == NoteKind.code)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: Sp.xs,
                                      top: 2,
                                    ),
                                    child: Icon(
                                      Icons.code_rounded,
                                      size: 15,
                                      color: p.synFunction,
                                    ),
                                  ),
                                if (n.status != NoteStatus.none)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: Sp.xs,
                                      top: 2,
                                    ),
                                    child: Icon(
                                      status.icon,
                                      size: 15,
                                      color: status.color,
                                    ),
                                  ),
                                Expanded(
                                  child: HighlightedText(
                                    n.displayTitle,
                                    words: words,
                                    maxLines: 2,
                                    style: TextStyle(
                                      color: n.trashed ? p.textMuted : p.text,
                                      fontSize: Fs.body,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (n.isLocked) ...[
                              const SizedBox(height: 3),
                              Text(
                                context.tr('Locked note'),
                                style: TextStyle(
                                  color: p.textFaint,
                                  fontSize: Fs.small,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ] else if (snippet.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              HighlightedText(
                                snippet,
                                words: words,
                                maxLines: 2,
                                style: TextStyle(
                                  color: p.textMuted,
                                  fontSize: Fs.small,
                                  height: 1.4,
                                ),
                              ),
                            ],
                            const SizedBox(height: Sp.sm - 2),
                            Wrap(
                              spacing: Sp.sm,
                              runSpacing: Sp.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  countdown ?? timeAgo(n.updatedAt),
                                  style: TextStyle(
                                    color: countdown != null
                                        ? p.danger
                                        : p.textFaint,
                                    fontSize: Fs.caption,
                                  ),
                                ),
                                if (!progress.isEmpty)
                                  _Progress(progress: progress),
                                if (n.kind == NoteKind.code &&
                                    n.language != null)
                                  Text(
                                    Languages.find(n.language)?.name ??
                                        n.language!,
                                    style: TextStyle(
                                      color: p.textFaint,
                                      fontSize: Fs.caption,
                                    ),
                                  ),
                                for (final t in tags.take(3))
                                  TagChip(
                                    label: t.name,
                                    color: Color(t.colorValue),
                                  ),
                                if (tags.length > 3)
                                  Text(
                                    '+${tags.length - 3}',
                                    style: TextStyle(
                                      color: p.textFaint,
                                      fontSize: Fs.caption,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // A small thumbnail keeps rows with and without covers
                      // at a similar height.
                      if (n.coverImage != null) ...[
                        const SizedBox(width: Sp.md),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Rad.md),
                          child: CoverImage(
                            data: n.coverImage!,
                            width: 56,
                            height: 56,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.progress});
  final TaskProgress progress;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final done = progress.done == progress.total;
    return Semantics(
      label: context.tr('{done} of {total} tasks done', {
        'done': progress.done,
        'total': progress.total,
      }),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.checklist_rounded,
            size: 15,
            color: done ? p.success : p.textFaint,
          ),
          const SizedBox(width: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(Rad.pill),
            child: SizedBox(
              width: 38,
              height: 5,
              child: LinearProgressIndicator(
                value: progress.fraction,
                backgroundColor: p.border,
                valueColor: AlwaysStoppedAnimation(
                  done ? p.success : p.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            context.tr('{done} of {total}', {
              'done': progress.done,
              'total': progress.total,
            }),
            style: TextStyle(
              color: p.textFaint,
              fontSize: Fs.caption,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
