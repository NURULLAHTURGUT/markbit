import '../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/template_variables.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../data/models/library_models.dart';
import '../dialogs/dialogs.dart';

Future<void> showTemplatesDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _TemplatesDialog(),
);

class _TemplatesDialog extends ConsumerWidget {
  const _TemplatesDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final templates = ref.watch(libraryProvider.select((l) => l.templates));

    return AppDialog(
      icon: Icons.dashboard_customize_outlined,
      title: context.tr('Note templates'),
      width: 560,
      maxHeight: 600,
      scrollable: false,
      bodyPadding: const EdgeInsets.all(Sp.md),
      headerActions: [
        AppIconButton(
          icon: Icons.add_rounded,
          tooltip: context.tr('New template'),
          onPressed: () => _edit(context, ref, null),
        ),
      ],
      content: templates.isEmpty
          ? DialogEmptyState(
              icon: Icons.dashboard_customize_outlined,
              message: context.tr(
                'No templates yet. Use "Save as template" from a note\'s menu, or tap +.',
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              itemCount: templates.length,
              itemBuilder: (context, i) {
                final t = templates[i];
                return DialogListItem(
                  leading: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: p.codeBg,
                      borderRadius: BorderRadius.circular(Rad.md),
                      border: Border.all(color: p.border),
                    ),
                    child: Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: p.textMuted,
                    ),
                  ),
                  title: Text(t.name),
                  titleStyle: const TextStyle(fontWeight: FontWeight.w600),
                  subtitle: Text(
                    t.body.replaceAll('\n', ' ').trim(),
                    maxLines: 1,
                  ),
                  onTap: () => _use(context, ref, t),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIconButton(
                        icon: Icons.edit_outlined,
                        size: 16,
                        tooltip: context.tr('Edit template'),
                        onPressed: () => _edit(context, ref, t),
                      ),
                      AppIconButton(
                        icon: Icons.delete_outline_rounded,
                        size: 16,
                        tooltip: context.tr('Delete template'),
                        onPressed: () async {
                          final ok = await confirmAction(
                            context,
                            title: context.tr('Delete template "{name}"?', {
                              'name': t.name,
                            }),
                            message: context.tr(
                              'Notes created from it are not affected.',
                            ),
                          );
                          if (ok) {
                            ref
                                .read(libraryProvider.notifier)
                                .deleteTemplate(t.id);
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  void _use(BuildContext context, WidgetRef ref, NoteTemplate t) {
    final nav = ref.read(navFilterProvider);
    final note = ref
        .read(libraryProvider.notifier)
        .createFromTemplate(
          t,
          notebookId: nav.kind == NavKind.notebook ? nav.id : null,
        );
    if (note != null) ref.read(openNoteProvider.notifier).open(note.id);
    Navigator.pop(context);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    NoteTemplate? t,
  ) async {
    final result = await showDialog<NoteTemplate>(
      context: context,
      builder: (_) => _TemplateEditor(template: t),
    );
    if (result != null) {
      ref
          .read(libraryProvider.notifier)
          .saveTemplate(
            id: result.id.isEmpty ? null : result.id,
            name: result.name,
            title: result.title,
            body: result.body,
            notebookId: result.notebookId,
            tagIds: result.tagIds,
            images: result.images,
            attachments: result.attachments,
          );
    }
  }
}

class _TemplateEditor extends ConsumerStatefulWidget {
  const _TemplateEditor({this.template});
  final NoteTemplate? template;

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  late final _name = TextEditingController(text: widget.template?.name ?? '');
  late final _title = TextEditingController(text: widget.template?.title ?? '');
  late final _body = TextEditingController(text: widget.template?.body ?? '');

  late String? _notebookId = widget.template?.notebookId;
  late final Set<String> _tags = (widget.template?.tagIds ?? []).toSet();
  @override
  void dispose() {
    _name.dispose();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lib = ref.watch(libraryProvider);
    return AppDialog(
      icon: widget.template == null
          ? Icons.note_add_outlined
          : Icons.edit_note_rounded,
      title: widget.template == null
          ? context.tr('New template')
          : context.tr('Edit template'),
      width: 560,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.tr('Template name'),
              ),
            ),
            const SizedBox(height: Sp.md),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                labelText: context.tr('Default note title'),
              ),
            ),
            const SizedBox(height: Sp.md),
            TextField(
              controller: _body,
              minLines: 8,
              maxLines: 14,
              style: AppTheme.mono(size: 12.5, color: p.text),
              decoration: InputDecoration(
                labelText: context.tr('Markdown body'),
                helperText: context.tr(
                  'Variables: {{title}}, {{date}}, {{weekday}}, {{notebook}}, {{cursor}}… (see the list below)',
                ),
              ),
            ),
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  context.tr('Available variables'),
                  style: const TextStyle(fontSize: Fs.small),
                ),
                children: [
                  Wrap(
                    spacing: Sp.sm,
                    runSpacing: Sp.sm,
                    children: [
                      for (final (variable, meaning) in templateVariables)
                        Tooltip(
                          message: context.tr(meaning),
                          child: ActionChip(
                            label: Text(
                              variable,
                              style: AppTheme.mono(size: 11.5, color: p.text),
                            ),
                            onPressed: () {
                              // Insert at the caret of the body field.
                              final v = variable.split(' ').first;
                              final sel = _body.selection;
                              final at = sel.isValid
                                  ? sel.start
                                  : _body.text.length;
                              final end = sel.isValid ? sel.end : at;
                              _body.value = TextEditingValue(
                                text: _body.text.replaceRange(at, end, v),
                                selection: TextSelection.collapsed(
                                  offset: at + v.length,
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: Sp.sm),
                ],
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              dropdownColor: p.surface.withValues(alpha: 1),
              borderRadius: BorderRadius.circular(Rad.md),
              initialValue: lib.notebook(_notebookId) == null
                  ? null
                  : _notebookId,
              decoration: InputDecoration(
                labelText: context.tr('Default notebook'),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(context.tr('Current notebook')),
                ),
                for (final n in lib.notebooks)
                  DropdownMenuItem(value: n.id, child: Text(n.name)),
              ],
              onChanged: (v) => setState(() => _notebookId = v),
            ),
            const SizedBox(height: Sp.lg),
            if (lib.tags.isNotEmpty) DialogLabel(context.tr('Tags')),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in lib.tags)
                  FilterChip(
                    label: Text(t.name),
                    selected: _tags.contains(t.id),
                    onSelected: (v) => setState(() {
                      v ? _tags.add(t.id) : _tags.remove(t.id);
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        const DialogCancelButton(),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(
              context,
              NoteTemplate(
                id: widget.template?.id ?? '',
                name: name,
                title: _title.text,
                body: _body.text,
                notebookId: _notebookId,
                tagIds: _tags.toList(),
                images: widget.template?.images ?? {},
                attachments: widget.template?.attachments ?? {},
              ),
            );
          },
          child: Text(context.tr('Save')),
        ),
      ],
    );
  }
}
