import '../../application/persistence_coordinator.dart';
import '../../application/collections.dart';
import '../dialogs/task_dashboard.dart';
import '../dialogs/calendar_view.dart';
import '../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/library_notifier.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/status_visuals.dart';
import '../../core/widgets/color_picker_panel.dart';
import '../../data/models/library_models.dart';
import '../../data/models/note.dart';
import '../dialogs/dialogs.dart';
import '../settings/settings_dialog.dart';
import '../templates/templates_dialog.dart';
import '../graph/graph_view.dart';
import '../notelist/note_drag.dart';
import '../dialogs/searchable_picker.dart';
import '../../core/widgets/motion.dart';

/// Left navigation: notebooks, status, tags, trash.
class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({super.key, this.onNavigate});

  /// Called after the user picks a destination (closes the drawer on phones).
  final VoidCallback? onNavigate;

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  final Set<String> _collapsedSections = {};
  final Set<String> _collapsedNotebooks = {};
  final Set<String> _collapsedTags = {};
  bool _searchNotebooks = false;
  bool _searchTags = false;
  String _notebookFilter = '';
  String _tagFilter = '';

  void _select(NavFilter f) {
    ref.read(navFilterProvider.notifier).select(f);
    final cards =
        f.kind == NavKind.all ||
        f.kind == NavKind.starred ||
        f.kind == NavKind.trash ||
        f.kind == NavKind.notebook ||
        f.kind == NavKind.status ||
        f.kind == NavKind.tag;
    ref.read(notesOverviewProvider.notifier).set(cards);
    if (cards) {
      ref.read(searchTextProvider.notifier).set('');
      ref.read(focusModeProvider.notifier).set(false);
    }
    widget.onNavigate?.call();
  }

  Future<void> _showMenu(
    Offset at,
    List<PopupMenuEntry<String>> items,
    void Function(String) onSelected,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        overlay.globalToLocal(at) & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (value != null) onSelected(value);
  }

  PopupMenuItem<String> _mi(
    String v,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final p = context.palette;
    return PopupMenuItem<String>(
      value: v,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? p.textMuted),
          const SizedBox(width: 10),
          Flexible(
            child: Text(label, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }

  Future<void> _newNotebook({String? parentId}) async {
    final name = await promptText(
      context,
      title: parentId == null
          ? context.tr('New notebook')
          : context.tr('New sub-notebook'),
      hint: context.tr('Notebook name'),
      confirmLabel: context.tr('Create'),
    );
    if (name == null) return;
    final nb = ref
        .read(libraryProvider.notifier)
        .createNotebook(name, parentId: parentId);
    if (parentId != null) setState(() => _collapsedNotebooks.remove(parentId));
    _select(NavFilter.notebook(nb.id));
  }

  Future<void> _newTag() async {
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (_) => const _TagEditDialog(),
    );
    if (result != null && mounted) {
      ref
          .read(libraryProvider.notifier)
          .createTag(result.$1, colorValue: result.$2);
    }
  }

  void _notebookMenu(Offset at, Notebook nb) {
    if (nb.isInbox) {
      _showMenu(
        at,
        [
          _mi(
            'sub',
            Icons.create_new_folder_outlined,
            context.tr('New sub-notebook'),
          ),
        ],
        (_) {
          _newNotebook(parentId: nb.id);
        },
      );
      return;
    }
    _showMenu(
      at,
      [
        _mi(
          'sub',
          Icons.create_new_folder_outlined,
          context.tr('New sub-notebook'),
        ),
        _mi('rename', Icons.edit_outlined, context.tr('Rename')),
        const PopupMenuDivider(),
        _mi(
          'delete',
          Icons.delete_outline_rounded,
          context.tr('Delete notebook'),
          color: context.palette.danger,
        ),
      ],
      (v) async {
        final lib = ref.read(libraryProvider.notifier);
        switch (v) {
          case 'sub':
            _newNotebook(parentId: nb.id);
          case 'rename':
            final name = await promptText(
              context,
              title: context.tr('Rename notebook'),
              initial: nb.name,
              hint: context.tr('Notebook name'),
            );
            if (name != null) lib.renameNotebook(nb.id, name);
          case 'delete':
            final ok = await confirmAction(
              context,
              title: context.tr('Delete "{name}"?', {'name': nb.name}),
              message: context.tr(
                'Notes inside will be moved up one level. This cannot be undone.',
              ),
            );
            if (ok) {
              final nav = ref.read(navFilterProvider);
              if (nav.kind == NavKind.notebook && nav.id == nb.id) {
                ref
                    .read(navFilterProvider.notifier)
                    .select(const NavFilter.all());
              }
              lib.deleteNotebook(nb.id);
            }
        }
      },
    );
  }

  /// Rows for a level of the tag tree ("work/client" nests under "work").
  List<Widget> _tagRows(List<TagNode> nodes, NavFilter nav, int depth) {
    final rows = <Widget>[];
    for (final node in nodes) {
      final tag = node.tag;
      final filterId = tag?.id ?? 'path:${node.path}';
      final collapsed = _collapsedTags.contains(node.path);
      final item = _Item(
        depth: depth,
        label: node.name,
        dotColor: tag == null ? null : Color(tag.colorValue),
        icon: tag == null ? Icons.sell_outlined : null,
        count: node.count,
        selected: nav.kind == NavKind.tag && nav.id == filterId,
        expanded: node.children.isEmpty ? null : !collapsed,
        onToggle: () => setState(() {
          collapsed
              ? _collapsedTags.remove(node.path)
              : _collapsedTags.add(node.path);
        }),
        onTap: () => _select(NavFilter.tag(filterId)),
        onMenu: tag == null ? null : (at) => _tagMenu(at, tag),
      );
      rows.add(
        tag == null
            ? item
            : _DropZone(
                onNotes: (ids) {
                  ref.read(libraryProvider.notifier).tagNotes(ids, tag.id);
                  showToast(
                    context,
                    context.tr('Tagged {n} note(s) with {name}', {
                      'n': ids.length,
                      'name': tag.name,
                    }),
                  );
                },
                builder: (active) => _Item(
                  dropActive: active,
                  depth: item.depth,
                  label: item.label,
                  dotColor: item.dotColor,
                  count: item.count,
                  selected: item.selected,
                  expanded: item.expanded,
                  onToggle: item.onToggle,
                  onTap: item.onTap,
                  onMenu: item.onMenu,
                ),
              ),
      );
      if (!collapsed || _tagFilter.trim().isNotEmpty) {
        rows.addAll(_tagRows(node.children, nav, depth + 1));
      }
    }
    return rows;
  }

  Future<void> _mergeTag(Tag tag) async {
    final lib = ref.read(libraryProvider);
    final target = await showSearchablePicker<String>(
      context,
      title: context.tr('Merge "{name}" into', {'name': tag.name}),
      options: [
        for (final t
            in lib.tags.toList()..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            ))
          if (t.id != tag.id)
            PickerOption(t.id, t.name, icon: Icons.sell_outlined),
      ],
    );
    if (target == null || !mounted) return;
    final into = lib.tag(target)!;
    final ok = await confirmAction(
      context,
      title: context.tr('Merge tags?'),
      message: context.tr(
        'Notes tagged "{from}" get "{into}" and "{from}" is deleted.',
        {'from': tag.name, 'into': into.name},
      ),
      confirmLabel: context.tr('Merge'),
      destructive: false,
    );
    if (!ok) return;
    final nav = ref.read(navFilterProvider);
    if (nav.kind == NavKind.tag && nav.id == tag.id) {
      ref.read(navFilterProvider.notifier).select(NavFilter.tag(into.id));
    }
    ref.read(libraryProvider.notifier).mergeTags(tag.id, into.id);
  }

  void _tagMenu(Offset at, Tag tag) {
    _showMenu(
      at,
      [
        _mi('edit', Icons.edit_outlined, context.tr('Rename / change colour')),
        _mi(
          'sub',
          Icons.subdirectory_arrow_right_rounded,
          context.tr('New sub-tag'),
        ),
        _mi(
          'merge',
          Icons.merge_rounded,
          context.tr('Merge into another tag\u2026'),
        ),
        const PopupMenuDivider(),
        _mi(
          'delete',
          Icons.delete_outline_rounded,
          context.tr('Delete tag'),
          color: context.palette.danger,
        ),
      ],
      (v) async {
        final lib = ref.read(libraryProvider.notifier);
        if (v == 'merge') {
          await _mergeTag(tag);
          return;
        }
        if (v == 'sub') {
          final result = await showDialog<(String, int)>(
            context: context,
            builder: (_) => _TagEditDialog(prefix: '${tag.name}/'),
          );
          if (result != null) {
            lib.createTag(result.$1, colorValue: result.$2);
            setState(() => _collapsedTags.remove(tag.name.toLowerCase()));
          }
          return;
        }
        if (v == 'edit') {
          final result = await showDialog<(String, int)>(
            context: context,
            builder: (_) => _TagEditDialog(tag: tag),
          );
          if (result != null) {
            lib.updateTag(tag.id, name: result.$1, colorValue: result.$2);
          }
        } else {
          final ok = await confirmAction(
            context,
            title: context.tr('Delete tag "{name}"?', {'name': tag.name}),
            message: context.tr('It will be removed from all notes.'),
          );
          if (ok) {
            final nav = ref.read(navFilterProvider);
            if (nav.kind == NavKind.tag && nav.id == tag.id) {
              ref
                  .read(navFilterProvider.notifier)
                  .select(const NavFilter.all());
            }
            lib.deleteTag(tag.id);
          }
        }
      },
    );
  }

  void _dropNotes(List<String> ids, Notebook nb) {
    ref.read(libraryProvider.notifier).moveNotes(ids, nb.id);
    showToast(
      context,
      context.tr('Moved {n} note(s) to {name}', {
        'n': ids.length,
        'name': nb.isInbox ? context.tr('General') : nb.name,
      }),
    );
  }

  void _dropNotebook(String id, Notebook? target) {
    final lib = ref.read(libraryProvider.notifier);
    final parent = target == null || target.isInbox ? null : target.id;
    if (lib.moveNotebook(id, parent)) {
      if (parent != null) setState(() => _collapsedNotebooks.remove(parent));
    } else if (parent != null && id != parent) {
      showToast(
        context,
        context.tr('A notebook cannot be moved into its own sub-notebook.'),
      );
    }
  }

  List<Widget> _notebookRows(
    Library lib,
    SidebarCounts counts,
    NavFilter nav,
    String? parent,
    int depth,
  ) {
    final rows = <Widget>[];
    final filter = _notebookFilter.trim().toLowerCase();
    final children = <Notebook>[
      if (parent == null) lib.inbox,
      ...lib.childrenOf(parent),
    ];
    for (final nb in children) {
      final kids = lib.childrenOf(nb.id);
      final collapsed = _collapsedNotebooks.contains(nb.id);
      if (filter.isNotEmpty && !nb.name.toLowerCase().contains(filter)) {
        rows.addAll(_notebookRows(lib, counts, nav, nb.id, depth + 1));
        continue;
      }
      final label = nb.isInbox ? context.tr('General') : nb.name;
      final row = _DropZone(
        onNotes: (ids) => _dropNotes(ids, nb),
        onNotebook: (id) => _dropNotebook(id, nb),
        builder: (active) => _Item(
          dropActive: active,
          depth: depth,
          label: label,
          icon: nb.isInbox
              ? Icons.inbox_outlined
              : (kids.isNotEmpty && !collapsed
                    ? Icons.folder_open_outlined
                    : Icons.folder_outlined),
          count: counts.notebooks[nb.id] ?? 0,
          selected: nav.kind == NavKind.notebook && nav.id == nb.id,
          expanded: kids.isEmpty ? null : !collapsed,
          onToggle: () => setState(() {
            collapsed
                ? _collapsedNotebooks.remove(nb.id)
                : _collapsedNotebooks.add(nb.id);
          }),
          onTap: () => _select(NavFilter.notebook(nb.id)),
          onMenu: (at) => _notebookMenu(at, nb),
        ),
      );
      rows.add(
        nb.isInbox
            ? row
            : NotebookDraggable(notebookId: nb.id, name: label, child: row),
      );
      if (!collapsed || filter.isNotEmpty) {
        rows.addAll(_notebookRows(lib, counts, nav, nb.id, depth + 1));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lib = ref.watch(libraryProvider);
    final counts = ref.watch(sidebarCountsProvider);
    final nav = ref.watch(navFilterProvider);

    bool open(String s) => !_collapsedSections.contains(s);
    void toggle(String s) => setState(() {
      _collapsedSections.contains(s)
          ? _collapsedSections.remove(s)
          : _collapsedSections.add(s);
    });

    final tagTree = TagNode.build(lib, filter: _tagFilter);

    return ColoredBox(
      color: p.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.only(left: Sp.lg, right: Sp.xs),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => _select(const NavFilter.all()),
                      borderRadius: BorderRadius.circular(Rad.md),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/icon/markbit.png',
                              width: 26,
                              height: 26,
                              semanticLabel: 'Markbit',
                            ),
                            const SizedBox(width: Sp.sm),
                            Text(
                              'Markbit',
                              style: TextStyle(
                                color: p.text,
                                fontWeight: FontWeight.w700,
                                fontSize: Fs.title,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Sp.lg),
              children: [
                _Item(
                  label: context.tr('All Notes'),
                  icon: Icons.description_outlined,
                  count: counts.all,
                  selected: nav.kind == NavKind.all,
                  onTap: () => _select(const NavFilter.all()),
                ),
                _Item(
                  label: context.tr('Recently opened'),
                  icon: Icons.history_rounded,
                  selected: nav.kind == NavKind.recent,
                  onTap: () => _select(const NavFilter.recent()),
                ),
                _Item(
                  label: context.tr('Starred'),
                  icon: Icons.star_outline_rounded,
                  count: lib.notes.values
                      .where((n) => n.starred && !n.trashed)
                      .length,
                  selected: nav.kind == NavKind.starred,
                  onTap: () => _select(const NavFilter.starred()),
                ),
                _Item(
                  label: context.tr('Note Templates'),
                  icon: Icons.dashboard_customize_outlined,
                  onTap: () {
                    widget.onNavigate?.call();
                    showTemplatesDialog(context);
                  },
                ),
                _Item(
                  label: context.tr('Tasks'),
                  icon: Icons.checklist_rounded,
                  onTap: () {
                    ref.read(persistenceProvider).flushEditors();
                    showTaskDashboard(context);
                  },
                ),
                _Item(
                  label: context.tr('Calendar'),
                  icon: Icons.calendar_month_outlined,
                  onTap: () {
                    widget.onNavigate?.call();
                    showCalendarView(context);
                  },
                ),
                _Item(
                  label: context.tr('Link graph'),
                  icon: Icons.hub_outlined,
                  onTap: () {
                    widget.onNavigate?.call();
                    showGraphView(context);
                  },
                ),
                _Item(
                  label: context.tr('Daily note'),
                  icon: Icons.today_outlined,
                  onTap: () {
                    final n = ref.read(libraryProvider.notifier).dailyNote();
                    ref.read(openNoteProvider.notifier).open(n.id);
                    widget.onNavigate?.call();
                  },
                ),
                if (ref.watch(collectionsProvider).isNotEmpty)
                  _SectionHeader(title: context.tr('Collections')),
                for (final c in ref.watch(collectionsProvider))
                  _Item(
                    label: c.name,
                    icon: Icons.bookmarks_outlined,
                    onTap: () {
                      final scope = switch (c.scope) {
                        'notebook' when lib.notebook(c.scopeId) != null =>
                          NavFilter.notebook(c.scopeId!),
                        'tag'
                            when c.scopeId != null &&
                                lib.tag(c.scopeId!) != null =>
                          NavFilter.tag(c.scopeId!),
                        'starred' => const NavFilter.starred(),
                        'status' when c.scopeStatus != null => NavFilter.status(
                          NoteStatus.parse(c.scopeStatus),
                        ),
                        _ => const NavFilter.all(),
                      };
                      _select(scope);
                      ref.read(searchTextProvider.notifier).set(c.query);
                    },
                    onMenu: (at) => _showMenu(
                      at,
                      [
                        _mi(
                          'delete',
                          Icons.delete_outline,
                          context.tr('Delete'),
                        ),
                      ],
                      (_) =>
                          ref.read(collectionsProvider.notifier).remove(c.id),
                    ),
                  ),
                _DropZone(
                  onNotebook: (id) => _dropNotebook(id, null),
                  builder: (active) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: active
                          ? p.accent.withValues(alpha: .12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(Rad.md),
                    ),
                    child: _SectionHeader(
                      title: context.tr('Notebooks'),
                      onAdd: () => _newNotebook(),
                      addTooltip: context.tr('New notebook'),
                      searching: _searchNotebooks,
                      onSearch: () => setState(() {
                        _searchNotebooks = !_searchNotebooks;
                        if (!_searchNotebooks) _notebookFilter = '';
                      }),
                    ),
                  ),
                ),
                if (_searchNotebooks)
                  _FilterField(
                    value: _notebookFilter,
                    hint: context.tr('Filter notebooks'),
                    onChanged: (v) => setState(() => _notebookFilter = v),
                  ),
                ..._notebookRows(lib, counts, nav, null, 0),
                _SectionHeader(
                  title: context.tr('Status'),
                  collapsed: !open('status'),
                  onCollapse: () => toggle('status'),
                ),
                Reveal(
                  visible: open('status'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in NoteStatus.values.where(
                        (s) => s != NoteStatus.none,
                      ))
                        _Item(
                          label: context.tr(s.label),
                          icon: statusVisual(s, p).icon,
                          iconColor: statusSidebarColor(s, p),
                          count: counts.statuses[s] ?? 0,
                          selected:
                              nav.kind == NavKind.status && nav.status == s,
                          onTap: () => _select(NavFilter.status(s)),
                        ),
                    ],
                  ),
                ),
                _SectionHeader(
                  title: context.tr('Tags'),
                  onAdd: _newTag,
                  addTooltip: context.tr('New tag'),
                  searching: _searchTags,
                  onSearch: () => setState(() {
                    _searchTags = !_searchTags;
                    if (!_searchTags) _tagFilter = '';
                  }),
                  collapsed: !open('tags'),
                  onCollapse: () => toggle('tags'),
                ),
                Reveal(
                  visible: open('tags'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_searchTags)
                        _FilterField(
                          value: _tagFilter,
                          hint: context.tr('Filter tags'),
                          onChanged: (v) => setState(() => _tagFilter = v),
                        ),
                      ..._tagRows(tagTree.children, nav, 0),
                      if (lib.tags.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            Sp.lg + 4,
                            Sp.xs,
                            Sp.lg,
                            Sp.sm,
                          ),
                          child: Text(
                            context.tr('No tags yet'),
                            style: TextStyle(
                              color: p.textFaint,
                              fontSize: Fs.small,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Sp.sm),
                _Item(
                  label: context.tr('Trash'),
                  icon: Icons.delete_outline_rounded,
                  count: counts.trash,
                  selected: nav.kind == NavKind.trash,
                  onTap: () => _select(const NavFilter.trash()),
                ),
              ],
            ),
          ),
          // A rule separates the pinned footer from the scrolling list, so
          // rows that scroll under it read as cut off on purpose.
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Sp.sm),
                child: _Item(
                  label: context.tr('Settings'),
                  icon: Icons.settings_outlined,
                  onTap: () => showSettingsDialog(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatefulWidget {
  const _Item({
    required this.label,
    required this.onTap,
    this.icon,
    this.iconColor,
    this.dotColor,
    this.count,
    this.selected = false,
    this.depth = 0,
    this.expanded,
    this.onToggle,
    this.onMenu,
    this.dropActive = false,
  });

  final String label;

  /// Something droppable is hovering over this row.
  final bool dropActive;
  final IconData? icon;
  final Color? iconColor;
  final Color? dotColor;
  final int? count;
  final bool selected;
  final int depth;

  /// `null` = no children; otherwise chevron state.
  final bool? expanded;
  final VoidCallback? onToggle;
  final VoidCallback onTap;
  final void Function(Offset globalPosition)? onMenu;

  @override
  State<_Item> createState() => _ItemState();
}

class _ItemState extends State<_Item> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final platform = Theme.of(context).platform;
    final touch =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final height = touch ? 44.0 : 32.0;
    final selected = widget.selected;
    final fg = selected ? p.text : p.textMuted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: widget.onMenu == null
              ? null
              : (d) => widget.onMenu!(d.globalPosition),
          onLongPressStart: widget.onMenu == null
              ? null
              : (d) => widget.onMenu!(d.globalPosition),
          child: Semantics(
            button: true,
            selected: selected,
            label: widget.count == null
                ? widget.label
                : context.tr('{title}, {n} notes', {
                    'title': widget.label,
                    'n': widget.count!,
                  }),
            child: Material(
              color: widget.dropActive
                  ? p.accent.withValues(alpha: .18)
                  : selected
                  ? p.selection
                  : (_hover ? p.hover : Colors.transparent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Rad.md),
                side: widget.dropActive
                    ? BorderSide(color: p.accent, width: 1.5)
                    : BorderSide.none,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(Rad.md),
                onTap: widget.onTap,
                child: SizedBox(
                  height: height,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 8 + widget.depth * 16.0,
                      right: Sp.md,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 20,
                          child: widget.expanded == null
                              ? null
                              : InkWell(
                                  borderRadius: BorderRadius.circular(Rad.sm),
                                  onTap: widget.onToggle,
                                  child: Icon(
                                    widget.expanded!
                                        ? Icons.keyboard_arrow_down_rounded
                                        : Icons.chevron_right_rounded,
                                    size: 18,
                                    color: p.textFaint,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 4),
                        if (widget.dotColor != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: widget.dotColor,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.25),
                                ),
                              ),
                            ),
                          )
                        else if (widget.icon != null)
                          Icon(
                            widget.icon,
                            size: 18,
                            color:
                                widget.iconColor ??
                                (selected ? p.accent : p.textMuted),
                          ),
                        const SizedBox(width: Sp.md),
                        Expanded(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: fg,
                              fontSize: Fs.label,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (widget.count != null)
                          Text(
                            '${widget.count}',
                            style: TextStyle(
                              color: p.textFaint,
                              fontSize: Fs.caption,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      ],
                    ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.onAdd,
    this.addTooltip,
    this.onSearch,
    this.searching = false,
    this.collapsed,
    this.onCollapse,
  });

  final String title;
  final VoidCallback? onAdd;
  final String? addTooltip;
  final VoidCallback? onSearch;
  final bool searching;
  final bool? collapsed;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.xs, 0),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              color: p.sectionLabel,
              fontSize: Fs.caption,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          if (onSearch != null)
            _MiniButton(
              icon: Icons.search_rounded,
              tooltip: context.tr('Filter {title}', {'title': title}),
              active: searching,
              onTap: onSearch!,
            ),
          if (onAdd != null)
            _MiniButton(
              icon: Icons.add_circle_outline_rounded,
              tooltip: addTooltip ?? context.tr('Add'),
              onTap: onAdd!,
            ),
          if (onCollapse != null)
            _MiniButton(
              icon: collapsed == true
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              tooltip: collapsed == true
                  ? context.tr('Expand {title}', {'title': title})
                  : context.tr('Collapse {title}', {'title': title}),
              onTap: onCollapse!,
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(Rad.sm),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 17,
            color: active ? p.accent : p.sectionLabel,
          ),
        ),
      ),
    );
  }
}

class _FilterField extends StatefulWidget {
  const _FilterField({
    required this.value,
    required this.hint,
    required this.onChanged,
  });
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  State<_FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends State<_FilterField> {
  late final _controller = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_FilterField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Rad.pill),
      borderSide: BorderSide(color: p.border),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.md, Sp.sm),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: widget.onChanged,
          style: TextStyle(fontSize: Fs.small, color: p.text),
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(fontSize: Fs.small, color: p.textFaint),
            filled: true,
            fillColor: p.codeBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: Sp.md,
              vertical: 8,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 17,
              color: p.textFaint,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 34,
            ),
            suffixIcon: widget.value.isEmpty
                ? null
                : IconButton(
                    tooltip: context.tr('Clear filter'),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: p.textMuted,
                    ),
                    onPressed: () {
                      _controller.clear();
                      widget.onChanged('');
                    },
                  ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: p.accent, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagEditDialog extends StatefulWidget {
  const _TagEditDialog({this.tag, this.prefix = ''});
  final Tag? tag;

  /// Pre-filled start of a new tag's name (e.g. "work/" for a sub-tag).
  final String prefix;

  @override
  State<_TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends State<_TagEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.tag?.name ?? widget.prefix,
  );
  late Color _color = Color(
    widget.tag?.colorValue ?? AppPalette.tagColors.first.toARGB32(),
  );

  bool _validColor = true;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.sell_outlined,
      iconColor: _validColor ? _color : null,
      title: context.tr(widget.tag == null ? 'New tag' : 'Edit tag'),
      width: 420,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: context.tr('Tag name')),
            ),
            const SizedBox(height: Sp.lg),
            ColorPickerPanel(
              color: _color,
              onChanged: (color) => setState(() => _color = color),
              onValidityChanged: (valid) => setState(() => _validColor = valid),
            ),
          ],
        ),
      ),
      actions: [
        const DialogCancelButton(),
        FilledButton(
          onPressed: !_validColor
              ? null
              : () {
                  final n = _name.text.trim();
                  if (n.isNotEmpty) {
                    RecentColors.remember(_color).catchError((Object _) {});
                    Navigator.pop(context, (n, _color.toARGB32()));
                  }
                },
          child: Text(context.tr(widget.tag == null ? 'Create' : 'Save')),
        ),
      ],
    );
  }
}

/// Accepts dragged notes and/or notebooks and tells [builder] whether
/// something acceptable is hovering, so the row can highlight.
class _DropZone extends StatelessWidget {
  const _DropZone({required this.builder, this.onNotes, this.onNotebook});

  final Widget Function(bool active) builder;
  final void Function(List<String> ids)? onNotes;
  final void Function(String id)? onNotebook;

  bool _accepts(Object? data) =>
      (data is NoteDragData && onNotes != null) ||
      (data is NotebookDragData && onNotebook != null);

  @override
  Widget build(BuildContext context) => DragTarget<Object>(
    onWillAcceptWithDetails: (d) => _accepts(d.data),
    onAcceptWithDetails: (d) {
      final data = d.data;
      if (data is NoteDragData) onNotes?.call(data.ids);
      if (data is NotebookDragData) onNotebook?.call(data.id);
    },
    builder: (context, candidates, _) => builder(candidates.isNotEmpty),
  );
}

/// A level of the tag tree. Tags named "a/b" nest under "a"; a parent that
/// is not a tag itself has [tag] == null.
class TagNode {
  TagNode(this.path, this.name, {this.tag});
  final String path; // lower-case full path
  final String name; // last segment, as written
  Tag? tag;
  final List<TagNode> children = [];

  /// Notes (not trashed) carrying this tag or one below it.
  int count = 0;

  static TagNode build(Library lib, {String filter = ''}) {
    final root = TagNode('', '');
    final byPath = <String, TagNode>{'': root};
    final sorted = [...lib.tags]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final tag in sorted) {
      final parts = [
        for (final p in tag.name.split('/'))
          if (p.trim().isNotEmpty) p.trim(),
      ];
      if (parts.isEmpty) continue;
      var parent = root;
      for (var i = 0; i < parts.length; i++) {
        final path = parts.take(i + 1).join('/').toLowerCase();
        final node = byPath[path] ??= () {
          final created = TagNode(path, parts[i]);
          parent.children.add(created);
          return created;
        }();
        if (i == parts.length - 1) node.tag = tag;
        parent = node;
      }
    }
    final tagPath = {
      for (final t in lib.tags)
        t.id: [
          for (final p in t.name.split('/'))
            if (p.trim().isNotEmpty) p.trim(),
        ].join('/').toLowerCase(),
    };
    for (final n in lib.notes.values) {
      if (n.trashed) continue;
      final paths = <String>{};
      for (final id in n.tagIds) {
        final full = tagPath[id];
        if (full == null || full.isEmpty) continue;
        final parts = full.split('/');
        for (var i = 1; i <= parts.length; i++) {
          paths.add(parts.take(i).join('/'));
        }
      }
      for (final p in paths) {
        byPath[p]?.count++;
      }
    }
    final f = filter.trim().toLowerCase();
    if (f.isNotEmpty) _prune(root, f);
    return root;
  }

  /// Keeps nodes that match [filter] or have a matching descendant.
  static bool _prune(TagNode node, String filter) {
    node.children.removeWhere((c) => !_prune(c, filter));
    return node.path.contains(filter) || node.children.isNotEmpty;
  }
}
