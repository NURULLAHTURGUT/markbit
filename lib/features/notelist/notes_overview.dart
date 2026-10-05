import '../../application/collections.dart';
import '../../core/util/ids.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/actions.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/util/time_ago.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../core/widgets/cover_image.dart';
import '../../core/widgets/tag_chip.dart';
import '../../data/models/note.dart';
import '../../domain/markdown_utils.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/import_dialog.dart';
import 'bulk_note_actions.dart';
import 'note_drag.dart';
import '../../core/widgets/highlighted_text.dart';
import '../../domain/search_query.dart';

class NotesOverview extends ConsumerStatefulWidget {
  const NotesOverview({super.key, required this.onNavigation, this.onOpen});
  final VoidCallback onNavigation;
  final VoidCallback? onOpen;
  @override
  ConsumerState<NotesOverview> createState() => _NotesOverviewState();
}

class _NotesOverviewState extends ConsumerState<NotesOverview> {
  final _search = TextEditingController();
  NoteStatus? _status;
  bool _pinned = false;
  bool _compact = false;
  NavFilter? _lastNav;

  void _clearFilters() {
    ref.read(searchTextProvider.notifier).set('');
    setState(() {
      _status = null;
      _pinned = false;
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _newNote() {
    createNoteInContext(ProviderScope.containerOf(context));
    widget.onOpen?.call();
  }

  Future<void> _emptyTrash() async {
    final count = ref
        .read(libraryProvider)
        .notes
        .values
        .where((n) => n.trashed)
        .length;
    if (count == 0) return;
    final ok = await confirmAction(
      context,
      title: context.tr('Empty trash?'),
      message: context.tr('{n} note(s) will be deleted permanently.', {
        'n': count,
      }),
      confirmLabel: context.tr('Empty trash'),
    );
    if (ok && mounted) {
      ref.read(libraryProvider.notifier).emptyTrash();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final nav = ref.watch(navFilterProvider);
    ref.listen(
      navFilterProvider,
      (_, next) => ref.read(noteSelectionProvider.notifier).clear(),
    );
    if (_lastNav != nav) {
      _status = null;
      _pinned = false;
      _lastNav = nav;
    }
    final trash = nav.kind == NavKind.trash;
    final selecting = ref.watch(noteSelectionProvider).enabled;
    final trashCount = ref.watch(sidebarCountsProvider).trash;
    final query = ref.watch(searchTextProvider);
    if (_search.text != query &&
        !ref.read(searchTextProvider.notifier).pending) {
      _search.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    final notes = ref
        .watch(visibleNotesProvider)
        .where(
          (n) =>
              trash ||
              ((_status == null || n.status == _status) &&
                  (!_pinned || n.pinned)),
        )
        .toList();
    final filtering = query.trim().isNotEmpty || _status != null || _pinned;
    return ColoredBox(
      color: p.editorBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.xl, Sp.md),
            child: LayoutBuilder(
              builder: (context, headerConstraints) => Row(
                children: [
                  AppIconButton(
                    icon: Icons.menu_rounded,
                    size: 20,
                    onPressed: widget.onNavigation,
                    tooltip: context.tr('Toggle sidebar'),
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      context.tr(ref.watch(navTitleProvider)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: Fs.headline,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AppIconButton(
                    tooltip: context.tr(
                      _compact ? 'Comfortable cards' : 'Compact cards',
                    ),
                    icon: _compact
                        ? Icons.grid_view_rounded
                        : Icons.view_agenda_outlined,
                    size: 19,
                    onPressed: () => setState(() => _compact = !_compact),
                  ),
                  if (!trash)
                    PopupMenuButton<String>(
                      borderRadius: BorderRadius.circular(Rad.md),
                      tooltip: context.tr('Import files'),
                      position: PopupMenuPosition.under,
                      child: SizedBox(
                        width: 34,
                        height: 34,
                        child: Icon(
                          Icons.file_upload_outlined,
                          size: 19,
                          color: p.textMuted,
                        ),
                      ),
                      onSelected: (value) => value == 'select'
                          ? ref
                                .read(noteSelectionProvider.notifier)
                                .toggleMode()
                          : value == 'other'
                          ? showImportSourcePicker(context)
                          : showImportDialog(
                              context,
                              folder: value == 'folder',
                            ),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'files',
                          child: Text(context.tr('Import files')),
                        ),
                        PopupMenuItem(
                          value: 'folder',
                          child: Text(context.tr('Import from folder…')),
                        ),
                        PopupMenuItem(
                          value: 'other',
                          child: Text(
                            context.tr(
                              'Import from Obsidian, Notion, Evernote, Joplin…',
                            ),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'select',
                          child: Text(
                            context.tr(
                              selecting ? 'Cancel selection' : 'Select notes',
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (trash || headerConstraints.maxWidth >= 600)
                    AppIconButton(
                      tooltip: context.tr(
                        selecting ? 'Cancel selection' : 'Select notes',
                      ),
                      icon: Icons.checklist,
                      size: 19,
                      active: selecting,
                      onPressed: () =>
                          ref.read(noteSelectionProvider.notifier).toggleMode(),
                    ),
                  const SizedBox(width: Sp.sm),
                  FilledButton.icon(
                    onPressed: trash
                        ? (trashCount == 0 ? null : _emptyTrash)
                        : _newNote,
                    style: trash
                        ? FilledButton.styleFrom(backgroundColor: p.danger)
                        : null,
                    icon: Icon(
                      trash ? Icons.delete_forever_outlined : Icons.add_rounded,
                      size: 18,
                    ),
                    label: headerConstraints.maxWidth < 450
                        ? const SizedBox.shrink()
                        : Text(context.tr(trash ? 'Empty trash' : 'New note')),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Sp.xl),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _search,
                focusNode: ref.watch(filterFocusProvider),
                style: const TextStyle(fontSize: Fs.body),
                onChanged: (value) =>
                    ref.read(searchTextProvider.notifier).debounce(value),
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.zero,
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: p.textFaint,
                  ),
                  hintText: context.tr('Search your notes'),
                  suffixIcon: query.isEmpty
                      ? null
                      : AppIconButton(
                          tooltip: context.tr('Clear filter'),
                          size: 16,
                          onPressed: () =>
                              ref.read(searchTextProvider.notifier).set(''),
                          icon: Icons.close_rounded,
                        ),
                ),
              ),
            ),
          ),
          if (!trash)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.md, Sp.xl, Sp.sm),
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final status in [null, ...NoteStatus.values])
                    ChoiceChip(
                      label: Text(
                        context.tr(status == null ? 'All' : status.label),
                      ),
                      selected: _status == status,
                      onSelected: (selected) =>
                          setState(() => _status = selected ? status : null),
                    ),
                  FilterChip(
                    label: Text(context.tr('Pinned')),
                    selected: _pinned,
                    avatar: const Icon(Icons.push_pin_outlined, size: 16),
                    onSelected: (value) => setState(() => _pinned = value),
                  ),
                  if (filtering || nav.kind != NavKind.all)
                    ActionChip(
                      avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
                      label: Text(context.tr('Save search')),
                      onPressed: () async {
                        final name = await promptText(
                          context,
                          title: context.tr('Save search'),
                          hint: context.tr('Collection name'),
                        );
                        if (name != null && mounted) {
                          ref
                              .read(collectionsProvider.notifier)
                              .save(
                                SavedCollection(
                                  newId(),
                                  name,
                                  [
                                    query,
                                    if (_status != null ||
                                        nav.kind == NavKind.status)
                                      'status:${(_status ?? nav.status)!.name}',
                                    if (_pinned) 'is:pinned',
                                  ].join(' ').trim(),
                                  scope: nav.kind.name,
                                  scopeId: nav.id,
                                  scopeStatus: nav.status?.name,
                                ),
                              );
                        }
                      },
                    ),
                  if (filtering)
                    ActionChip(
                      label: Text(context.tr('Clear filters')),
                      onPressed: _clearFilters,
                    ),
                ],
              ),
            ),
          Expanded(
            child: notes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notes_rounded,
                            color: p.textFaint,
                            size: 48,
                          ),
                          const SizedBox(height: Sp.md),
                          Text(
                            context.tr(
                              trash && !filtering
                                  ? 'Trash is empty'
                                  : nav.kind == NavKind.starred && !filtering
                                  ? 'No starred notes yet. Star a note from its menu.'
                                  : filtering
                                  ? 'No notes match your filter'
                                  : 'No notes here yet',
                            ),
                            style: TextStyle(color: p.textMuted),
                          ),
                          if (filtering) ...[
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.filter_alt_off_outlined),
                              label: Text(context.tr('Clear filters')),
                            ),
                          ] else if (!trash) ...[
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _newNote,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(context.tr('Create your first note')),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      Sp.xl,
                      Sp.sm,
                      Sp.xl,
                      Sp.xl,
                    ),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 360,
                      mainAxisExtent: _compact ? 168 : 300,
                      crossAxisSpacing: Sp.lg,
                      mainAxisSpacing: Sp.lg,
                    ),
                    itemCount: notes.length,
                    itemBuilder: (_, i) => _NoteCard(
                      note: notes[i],
                      compact: _compact,
                      onOpen: () {
                        ref.read(openNoteProvider.notifier).open(notes[i].id);
                        widget.onOpen?.call();
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

class _NoteCard extends ConsumerWidget {
  const _NoteCard({
    required this.note,
    required this.onOpen,
    this.compact = false,
  });
  final bool compact;
  final Note note;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final selection = ref.watch(noteSelectionProvider);
    ref.watch(libraryProvider.select((l) => (l.notebooks, l.tags)));
    final library = ref.read(libraryProvider);
    final notebook = library.notebook(note.notebookId);
    final tags = [
      for (final id in note.tagIds)
        if (library.tag(id) != null) library.tag(id)!,
    ];
    final hasCover = note.coverImage != null && !compact;
    final words = ref.watch(searchHighlightProvider(note));
    final snippet = note.isLocked
        ? context.tr('Locked note')
        : (words.isEmpty ? null : snippetAround(note.body, words, max: 400)) ??
              NoteDigest.of(note).snippet;
    final countdown = note.trashed
        ? trashCountdown(
            note.trashedAt,
            ref.watch(settingsProvider.select((s) => s.trashRetentionDays)),
          )
        : null;
    final menu = PopupMenuButton<String>(
      borderRadius: BorderRadius.circular(Rad.md),
      tooltip: context.tr('More'),
      icon: Icon(
        Icons.more_horiz_rounded,
        size: 18,
        color: hasCover ? Colors.white : p.textMuted,
      ),
      onSelected: (action) async {
        final notifier = ref.read(libraryProvider.notifier);
        if (action == 'pin') notifier.togglePin(note.id);
        if (action == 'star') notifier.toggleStar(note.id);
        if (action == 'duplicate') {
          notifier.duplicate(note.id);
        }
        if (action == 'trash') notifier.trash(note.id);
        if (action == 'restore') notifier.restore(note.id);
        if (action == 'delete') {
          final ok = await confirmAction(
            context,
            title: context.tr('Delete permanently?'),
            message: context.tr('This note will be removed for good.'),
          );
          if (ok) notifier.deleteForever(note.id);
        }
      },
      itemBuilder: (_) => note.trashed
          ? [
              PopupMenuItem(
                value: 'restore',
                child: Text(context.tr('Restore')),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(context.tr('Delete permanently')),
              ),
            ]
          : [
              PopupMenuItem(
                value: 'pin',
                child: Text(context.tr(note.pinned ? 'Unpin' : 'Pin to top')),
              ),
              PopupMenuItem(
                value: 'star',
                child: Text(
                  context.tr(
                    note.starred ? 'Remove from starred' : 'Add to starred',
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'duplicate',
                child: Text(context.tr('Duplicate')),
              ),
              PopupMenuItem(
                value: 'trash',
                child: Text(context.tr('Move to trash')),
              ),
            ],
    );
    final checkbox = selection.enabled
        ? Checkbox(
            value: selection.ids.contains(note.id),
            onChanged: (_) =>
                ref.read(noteSelectionProvider.notifier).toggle(note.id),
          )
        : null;

    // Leading marker for text cards: the note kind, or a pin when pinned.
    final kindIcon = Icon(
      note.isLocked
          ? Icons.lock_rounded
          : note.pinned
          ? Icons.push_pin_rounded
          : note.kind == NoteKind.code
          ? Icons.code_rounded
          : Icons.description_outlined,
      size: 16,
      color: note.pinned ? p.accent : p.textFaint,
    );

    return NoteDraggable(
      noteId: note.id,
      title: note.displayTitle,
      child: Material(
        color: p.listBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg),
          side: BorderSide(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selection.enabled
              ? () => ref.read(noteSelectionProvider.notifier).toggle(note.id)
              : onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Only real covers get an image band; other notes use the space
              // for their text instead of an empty placeholder.
              if (hasCover)
                SizedBox(
                  height: 120,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CoverImage(data: note.coverImage!),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [Color(0x66000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                      Positioned(right: Sp.xs, top: Sp.xs, child: menu),
                      if (checkbox != null)
                        Positioned(left: Sp.xs, top: Sp.xs, child: checkbox),
                      if (note.pinned && checkbox == null)
                        const Positioned(
                          left: Sp.md,
                          top: Sp.md,
                          child: Icon(
                            Icons.push_pin_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    Sp.lg,
                    hasCover ? Sp.md : Sp.sm,
                    hasCover ? Sp.lg : Sp.xs,
                    Sp.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!hasCover)
                        Row(
                          children: [
                            ?checkbox,
                            if (checkbox == null) kindIcon,
                            if (note.starred) ...[
                              const SizedBox(width: Sp.xs),
                              Icon(
                                Icons.star_rounded,
                                size: 16,
                                color: p.warning,
                              ),
                            ],
                            const Spacer(),
                            menu,
                          ],
                        ),
                      Padding(
                        padding: EdgeInsets.only(right: hasCover ? 0 : Sp.md),
                        child: HighlightedText(
                          note.displayTitle,
                          words: words,
                          maxLines: 2,
                          style: TextStyle(
                            color: p.text,
                            fontSize: Fs.title,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (snippet.isNotEmpty) ...[
                        const SizedBox(height: Sp.xs + 2),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: hasCover ? 0 : Sp.md,
                            ),
                            child: LayoutBuilder(
                              // As many snippet lines as the card has room for.
                              builder: (context, c) => HighlightedText(
                                snippet,
                                words: words,
                                maxLines: (c.maxHeight / (13 * 1.45))
                                    .floor()
                                    .clamp(1, 12),
                                style: TextStyle(
                                  color: p.textMuted,
                                  fontSize: Fs.label,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      const SizedBox(height: Sp.sm),
                      Padding(
                        padding: EdgeInsets.only(right: hasCover ? 0 : Sp.md),
                        child: Row(
                          children: [
                            // Tags and notebook share the left side; the date
                            // stays pinned to the right edge.
                            Expanded(
                              child: Row(
                                children: [
                                  for (final tag in tags.take(2))
                                    Flexible(
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: Sp.xs + 2,
                                        ),
                                        child: TagChip(
                                          label: tag.name,
                                          color: Color(tag.colorValue),
                                        ),
                                      ),
                                    ),
                                  Icon(
                                    Icons.folder_outlined,
                                    color: p.textFaint,
                                    size: 13,
                                  ),
                                  const SizedBox(width: Sp.xs),
                                  Flexible(
                                    child: Text(
                                      notebook?.isInbox == true
                                          ? context.tr('General')
                                          : notebook?.name ??
                                                context.tr('No notebook'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: p.textFaint,
                                        fontSize: Fs.caption,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Sp.sm),
                            Text(
                              countdown ?? timeAgo(note.updatedAt),
                              style: TextStyle(
                                color: countdown != null
                                    ? p.danger
                                    : p.textFaint,
                                fontSize: Fs.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
