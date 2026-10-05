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
import '../../core/widgets/tag_chip.dart';
import '../../data/models/library_models.dart';
import '../../data/models/note.dart';
import '../../domain/languages.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/searchable_picker.dart';

List<(Notebook, int)> flattenNotebooks(Library lib) {
  final out = <(Notebook, int)>[];
  void walk(String? parent, int depth) {
    for (final nb in lib.childrenOf(parent)) {
      out.add((nb, depth));
      walk(nb.id, depth + 1);
    }
  }

  out.add((lib.inbox, 0));
  walk(null, 0);
  return out;
}

/// Notebook / status / language / tags row under the note title.
class NoteMetaBar extends ConsumerWidget {
  const NoteMetaBar({super.key, required this.noteId});
  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final note = ref.watch(noteProvider(noteId));
    if (note == null) return const SizedBox.shrink();
    final lib = ref.watch(libraryProvider);
    final notifier = ref.read(libraryProvider.notifier);
    final notebook = lib.notebook(note.notebookId);
    final status = statusVisual(note.status, p);

    return Wrap(
      spacing: Sp.sm,
      runSpacing: Sp.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(Rad.sm),
          onTap: () async {
            final id = await showSearchablePicker<String>(
              context,
              title: context.tr('Move to notebook'),
              selected: note.notebookId,
              options: [
                for (final (nb, depth) in flattenNotebooks(lib))
                  PickerOption(
                    nb.id,
                    '${'  ' * depth}${nb.isInbox ? context.tr('General') : nb.name}',
                    icon: nb.isInbox
                        ? Icons.inbox_outlined
                        : Icons.folder_outlined,
                  ),
              ],
              action: PickerOption(
                '__new__',
                context.tr('New notebook\u2026'),
                icon: Icons.add_rounded,
              ),
            );
            if (id == null || !context.mounted) return;
            if (id == '__new__') {
              final name = await promptText(
                context,
                title: context.tr('New notebook'),
                hint: context.tr('Notebook name'),
                confirmLabel: context.tr('Create'),
              );
              if (name != null) {
                final nb = notifier.createNotebook(name);
                notifier.setNotebook(noteId, nb.id);
              }
              return;
            }
            notifier.setNotebook(noteId, id);
          },
          child: _MetaButton(
            icon: (notebook?.isInbox ?? true)
                ? Icons.inbox_outlined
                : Icons.folder_outlined,
            label: notebook == null
                ? context.tr('No notebook')
                : (notebook.isInbox ? context.tr('General') : notebook.name),
            bold: true,
          ),
        ),
        PopupMenuButton<NoteStatus>(
          borderRadius: BorderRadius.circular(Rad.md),
          tooltip: context.tr('Status'),
          onSelected: (s) => notifier.setStatus(noteId, s),
          itemBuilder: (_) => [
            for (final s in NoteStatus.values)
              PopupMenuItem<NoteStatus>(
                value: s,
                child: Row(
                  children: [
                    Icon(
                      statusVisual(s, p).icon,
                      size: 18,
                      color: statusVisual(s, p).color,
                    ),
                    const SizedBox(width: 10),
                    Text(context.tr(s.label)),
                    if (s == note.status) ...[
                      const Spacer(),
                      Icon(Icons.check_rounded, size: 16, color: p.accent),
                    ],
                  ],
                ),
              ),
          ],
          child: _MetaButton(
            icon: status.icon,
            iconColor: note.status == NoteStatus.none ? null : status.color,
            label: context.tr(note.status.label),
          ),
        ),
        if (note.kind == NoteKind.code)
          InkWell(
            borderRadius: BorderRadius.circular(Rad.sm),
            onTap: () async {
              final id = await showSearchablePicker<String>(
                context,
                title: context.tr('Language'),
                selected: note.language,
                options: [
                  for (final l in Languages.all)
                    PickerOption(
                      l.id,
                      context.tr(l.name),
                      icon: Icons.code_rounded,
                    ),
                ],
              );
              if (id != null && context.mounted) {
                notifier.setLanguage(noteId, id);
              }
            },
            child: _MetaButton(
              icon: Icons.code_rounded,
              label: context.tr(
                Languages.find(note.language)?.name ?? 'Plain text',
              ),
            ),
          ),
        for (final id in note.tagIds)
          if (lib.tag(id) case final tag?)
            TagChip(
              label: tag.name,
              color: Color(tag.colorValue),
              onRemove: () => notifier.toggleTag(noteId, id),
            ),
        InkWell(
          borderRadius: BorderRadius.circular(Rad.sm),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => TagPickerDialog(noteId: noteId),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Text(
              note.tagIds.isEmpty
                  ? context.tr('Add Tags')
                  : context.tr('+ Tag'),
              style: TextStyle(color: p.textFaint, fontSize: Fs.small),
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaButton extends StatelessWidget {
  const _MetaButton({
    required this.icon,
    required this.label,
    this.bold = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final bool bold;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: iconColor ?? p.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: bold ? p.text : p.textMuted,
                fontSize: Fs.small,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: p.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Search, toggle and create tags for a note.
class TagPickerDialog extends ConsumerStatefulWidget {
  const TagPickerDialog({super.key, required this.noteId});
  final String noteId;

  @override
  ConsumerState<TagPickerDialog> createState() => _TagPickerDialogState();
}

class _TagPickerDialogState extends ConsumerState<TagPickerDialog> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _query.trim();
    if (name.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final notifier = ref.read(libraryProvider.notifier);
    final existing = ref.read(libraryProvider).tagByName(name);
    final tag = existing ?? notifier.createTag(name);
    final note = ref.read(noteProvider(widget.noteId));
    if (note != null && !note.tagIds.contains(tag.id)) {
      notifier.toggleTag(widget.noteId, tag.id);
    }
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lib = ref.watch(libraryProvider);
    final note = ref.watch(noteProvider(widget.noteId));
    final q = _query.trim().toLowerCase();
    final matches = lib.tags
        .where((t) => q.isEmpty || t.name.toLowerCase().contains(q))
        .toList();
    final exact = lib.tagByName(_query.trim()) != null;

    return AppDialog(
      icon: Icons.sell_outlined,
      title: context.tr('Tags'),
      width: 400,
      height: 480,
      scrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.tr('Search or create a tag'),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: p.textMuted,
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Sp.sm),
          Expanded(
            child: ListView(
              children: [
                if (_query.trim().isNotEmpty && !exact)
                  DialogListItem(
                    leading: Icon(
                      Icons.add_circle_outline_rounded,
                      color: p.accent,
                    ),
                    title: Text(
                      context.tr('Create "{name}"', {'name': _query.trim()}),
                    ),
                    titleStyle: TextStyle(color: p.accent),
                    onTap: _submit,
                  ),
                if (matches.isEmpty && _query.trim().isEmpty)
                  SizedBox(
                    height: 200,
                    child: DialogEmptyState(
                      icon: Icons.sell_outlined,
                      message: context.tr('Search or create a tag'),
                    ),
                  ),
                for (final t in matches)
                  Builder(
                    builder: (context) {
                      final on = note?.tagIds.contains(t.id) ?? false;
                      return DialogListItem(
                        selected: on,
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color(t.colorValue),
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(t.name),
                        trailing: SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: on,
                            onChanged: (_) => ref
                                .read(libraryProvider.notifier)
                                .toggleTag(widget.noteId, t.id),
                          ),
                        ),
                        onTap: () => ref
                            .read(libraryProvider.notifier)
                            .toggleTag(widget.noteId, t.id),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Done')),
        ),
      ],
    );
  }
}
