import '../../core/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../application/providers.dart';
import '../../application/persistence_coordinator.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../data/export_service.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/searchable_picker.dart';
import '../editor/note_meta_bar.dart';

class NoteSelection {
  const NoteSelection({this.enabled = false, this.ids = const {}});
  final bool enabled;
  final Set<String> ids;
}

class NoteSelectionNotifier extends Notifier<NoteSelection> {
  @override
  NoteSelection build() => const NoteSelection();
  void enable() => state = const NoteSelection(enabled: true);
  void clear() => state = const NoteSelection();
  void toggleMode() => state.enabled ? clear() : enable();
  void deselectAll() => state = const NoteSelection(enabled: true);
  void toggle(String id) {
    final ids = {...state.ids};
    ids.contains(id) ? ids.remove(id) : ids.add(id);
    state = NoteSelection(enabled: true, ids: ids);
  }

  void selectAll(Iterable<String> ids) =>
      state = NoteSelection(enabled: true, ids: ids.toSet());
}

final noteSelectionProvider =
    NotifierProvider<NoteSelectionNotifier, NoteSelection>(
      NoteSelectionNotifier.new,
    );

class BulkNoteActions extends ConsumerStatefulWidget {
  const BulkNoteActions({super.key, this.visibleIds});
  final List<String>? visibleIds;
  @override
  ConsumerState<BulkNoteActions> createState() => _BulkNoteActionsState();
}

class _BulkNoteActionsState extends ConsumerState<BulkNoteActions> {
  bool _busy = false;
  Future<void> _act(String action) async {
    final lib = ref.read(libraryProvider);
    final ids = ref
        .read(noteSelectionProvider)
        .ids
        .where(lib.notes.containsKey)
        .toList();
    if (ids.isEmpty) return;
    final notifier = ref.read(libraryProvider.notifier);
    setState(() => _busy = true);
    try {
      if (action == 'move') {
        final destination = await showSearchablePicker<String>(
          context,
          title: context.tr('Move to notebook'),
          options: [
            for (final (book, depth) in flattenNotebooks(lib))
              PickerOption(
                book.id,
                '${'  ' * depth}${book.isInbox ? context.tr('General') : book.name}',
              ),
          ],
        );
        if (destination == null) return;
        for (final id in ids) {
          notifier.setNotebook(id, destination);
        }
      } else if (action == 'tag') {
        var tag = await showSearchablePicker<String>(
          context,
          title: context.tr('Add Tags'),
          options: [for (final tag in lib.tags) PickerOption(tag.id, tag.name)],
          action: PickerOption('__new__', context.tr('New tag…')),
        );
        if (tag == '__new__' && mounted) {
          final name = await promptText(
            context,
            title: context.tr('New tag'),
            hint: context.tr('Tag name'),
          );
          tag = name == null ? null : notifier.createTag(name).id;
        }
        if (tag == null) return;
        for (final id in ids) {
          if (!lib.notes[id]!.tagIds.contains(tag)) notifier.toggleTag(id, tag);
        }
      } else if (action == 'trash') {
        final yes = await confirmAction(
          context,
          title: context.tr('Move selected notes to trash?'),
          confirmLabel: context.tr('Move to trash'),
          message: context.tr('{n} notes selected', {'n': ids.length}),
        );
        if (!yes) return;
        for (final id in ids) {
          notifier.trash(id);
        }
      } else if (action == 'restore') {
        for (final id in ids) {
          notifier.restore(id);
        }
      } else if (action == 'export') {
        final folder = await FilePicker.getDirectoryPath(
          dialogTitle: context.tr('Export notes to folder'),
        );
        if (folder == null) return;
        await ref.read(persistenceProvider).flush();
        final count = await ExportService.exportAll(
          ref.read(libraryProvider),
          folder,
          selectedIds: ids.toSet(),
        );
        if (mounted) {
          showToast(context, context.tr('Exported {n} notes', {'n': count}));
        }
      }
      ref.read(noteSelectionProvider.notifier).clear();
    } catch (e) {
      if (mounted) showToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = ref.watch(noteSelectionProvider);
    final trash = ref.watch(navFilterProvider).kind == NavKind.trash;
    if (!selection.enabled) return const SizedBox.shrink();
    final visibleIds =
        widget.visibleIds ??
        ref.watch(visibleNotesProvider).map((n) => n.id).toList();
    final allSelected =
        visibleIds.isNotEmpty && visibleIds.every(selection.ids.contains);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(context.tr('{n} notes selected', {'n': selection.ids.length})),
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    final notifier = ref.read(noteSelectionProvider.notifier);
                    allSelected
                        ? notifier.deselectAll()
                        : notifier.selectAll(visibleIds);
                  },
            child: Text(
              context.tr(allSelected ? 'Deselect all' : 'Select all'),
            ),
          ),
          PopupMenuButton<String>(
            borderRadius: BorderRadius.circular(Rad.md),
            enabled: !_busy && selection.ids.isNotEmpty,
            onSelected: _act,
            itemBuilder: (_) => [
              for (final entry
                  in trash
                      ? [('restore', 'Restore'), ('export', 'Export selected')]
                      : [
                          ('move', 'Move to notebook'),
                          ('tag', 'Add Tags'),
                          ('trash', 'Move to trash'),
                          ('export', 'Export selected'),
                        ])
                PopupMenuItem(
                  value: entry.$1,
                  child: Text(context.tr(entry.$2)),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(context.tr('Actions')),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: context.tr('Cancel selection'),
            onPressed: _busy
                ? null
                : () => ref.read(noteSelectionProvider.notifier).clear(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
