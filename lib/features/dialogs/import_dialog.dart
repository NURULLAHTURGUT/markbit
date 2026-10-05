import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../application/persistence_coordinator.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../../data/importers.dart';
import '../../data/note_import_service.dart';
import '../editor/note_meta_bar.dart';
import 'searchable_picker.dart';
import 'dialogs.dart';

/// Lets the user choose what to import from, then shows the preview.
Future<void> showImportSourcePicker(BuildContext context) async {
  final source = await showDialog<ImportSource>(
    context: context,
    builder: (context) => AppDialog(
      icon: Icons.file_download_outlined,
      title: context.tr('Import notes'),
      subtitle: context.tr('Nothing changes until you confirm the preview.'),
      width: 480,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (source, icon, hint) in const [
            (
              ImportSource.files,
              Icons.description_outlined,
              '.md, .txt and source files',
            ),
            (
              ImportSource.folder,
              Icons.folder_outlined,
              'Sub-folders become notebooks',
            ),
            (
              ImportSource.obsidian,
              Icons.diamond_outlined,
              'Links, embedded images and #tags',
            ),
            (
              ImportSource.notion,
              Icons.view_quilt_outlined,
              'Export as "Markdown & CSV", then pick the .zip',
            ),
            (
              ImportSource.evernote,
              Icons.eco_outlined,
              'Notes, tags, images and attachments',
            ),
            (
              ImportSource.joplin,
              Icons.book_outlined,
              'Export as JEX; notebooks and tags are kept',
            ),
          ])
            DialogListItem(
              leading: Icon(icon),
              title: Text(context.tr(source.label)),
              subtitle: Text(context.tr(hint)),
              onTap: () => Navigator.pop(context, source),
            ),
        ],
      ),
    ),
  );
  if (source != null && context.mounted) {
    await showImportDialog(context, source: source);
  }
}

Future<void> showImportDialog(
  BuildContext context, {
  bool folder = false,
  ImportSource? source,
}) async {
  final kind = source ?? (folder ? ImportSource.folder : ImportSource.files);
  String? root;
  List<String> paths = [];
  switch (kind) {
    case ImportSource.folder || ImportSource.obsidian:
      root = await FilePicker.getDirectoryPath(
        dialogTitle: context.tr(kind.label),
      );
      if (root == null) return;
    case ImportSource.files:
      final files = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        dialogTitle: context.tr('Import files'),
      );
      if (files == null) return;
      paths = files.paths.whereType<String>().toList();
    case ImportSource.notion || ImportSource.evernote || ImportSource.joplin:
      final files = await FilePicker.pickFiles(
        allowMultiple: kind == ImportSource.evernote,
        type: FileType.custom,
        allowedExtensions: [
          switch (kind) {
            ImportSource.notion => 'zip',
            ImportSource.evernote => 'enex',
            _ => 'jex',
          },
        ],
        dialogTitle: context.tr(kind.label),
      );
      if (files == null) return;
      paths = files.paths.whereType<String>().toList();
      if (paths.isEmpty) return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImportDialog(paths: paths, root: root, source: kind),
  );
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({required this.paths, this.root, required this.source});
  final List<String> paths;
  final String? root;
  final ImportSource source;
  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  ImportPlan? _plan;
  String? _error;
  String? _target;
  final _selected = <int>{};
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final lib = ref.read(libraryProvider);
    final keepsFolders =
        widget.root != null ||
        widget.source == ImportSource.evernote ||
        widget.source == ImportSource.joplin ||
        widget.source == ImportSource.notion;
    _target = keepsFolders ? null : lib.inbox.id;
    final scan = switch (widget.source) {
      ImportSource.files => NoteImportService.prepare(widget.paths, lib),
      ImportSource.folder => NoteImportService.folder(widget.root!, lib),
      ImportSource.obsidian => importObsidian(widget.root!, lib),
      ImportSource.notion => importNotion(widget.paths.single, lib),
      ImportSource.evernote => importEvernote(widget.paths, lib),
      ImportSource.joplin => importJoplin(widget.paths.single, lib),
    };
    scan
        .then((plan) {
          if (!mounted) return;
          setState(() {
            _plan = plan;
            for (var i = 0; i < plan.files.length; i++) {
              if (!plan.files[i].duplicate) _selected.add(i);
            }
          });
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = '$e');
        });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final plan = _plan!;
      final count = NoteImportService.apply(
        ref.read(libraryProvider.notifier),
        ref.read(libraryProvider),
        _selected.map((i) => plan.files[i]),
        notebookId: _target,
      );
      await ref.read(persistenceProvider).flush();
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, context.tr('Imported {n} notes', {'n': count}));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final plan = _plan;
    final p = context.palette;
    final files = plan?.files ?? const [];
    return AppDialog(
      icon: Icons.file_download_outlined,
      title: context.tr('Import preview'),
      subtitle: plan == null
          ? null
          : context.tr(
              '{selected} selected · {duplicates} duplicates · {skipped} skipped',
              {
                'selected': _selected.length,
                'duplicates': files.where((f) => f.duplicate).length,
                'skipped': plan.skipped.length,
              },
            ),
      width: 740,
      height: 680,
      scrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.md),
      content: plan == null
          ? DialogEmptyState(
              loading: _error == null,
              icon: Icons.error_outline_rounded,
              message: _error ?? context.tr('Loading…'),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DialogLabel(context.tr('Destination notebook')),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                    minimumSize: const Size.fromHeight(40),
                  ),
                  icon: Icon(Icons.folder_outlined, size: 18, color: p.accent),
                  label: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _target == null
                              ? context.tr('Keep folder structure')
                              : lib.notebook(_target)?.isInbox == true
                              ? context.tr('General')
                              : lib.notebook(_target)?.name ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 18,
                        color: p.textMuted,
                      ),
                    ],
                  ),
                  onPressed: _saving
                      ? null
                      : () async {
                          final value = await showSearchablePicker<String>(
                            context,
                            title: context.tr('Destination notebook'),
                            selected: _target ?? '__folders__',
                            options: [
                              if (widget.source != ImportSource.files)
                                PickerOption(
                                  '__folders__',
                                  context.tr('Keep folder structure'),
                                ),
                              for (final (book, depth) in flattenNotebooks(lib))
                                PickerOption(
                                  book.id,
                                  '${'  ' * depth}${book.isInbox ? context.tr('General') : book.name}',
                                ),
                            ],
                          );
                          if (value != null && mounted) {
                            setState(
                              () => _target = value == '__folders__'
                                  ? null
                                  : value,
                            );
                          }
                        },
                ),
                const SizedBox(height: Sp.md),
                Container(
                  padding: const EdgeInsets.all(Sp.md),
                  decoration: BoxDecoration(
                    color: p.info.withValues(alpha: p.isDark ? .12 : .07),
                    borderRadius: BorderRadius.circular(Rad.md),
                    border: Border.all(color: p.info.withValues(alpha: .25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: p.info),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: Text(
                          context.tr(
                            'Duplicates are unchecked. Select one only to import another copy.',
                          ),
                          style: TextStyle(
                            color: p.textMuted,
                            fontSize: Fs.small,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: Sp.sm),
                  Text(
                    _error!,
                    style: TextStyle(color: p.danger, fontSize: Fs.small),
                  ),
                ],
                const SizedBox(height: Sp.md),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.codeBg,
                      borderRadius: BorderRadius.circular(Rad.lg),
                      border: Border.all(color: p.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Material(
                      type: MaterialType.transparency,
                      child: ListView(
                        padding: const EdgeInsets.all(Sp.xs),
                        children: [
                          for (var i = 0; i < files.length; i++)
                            DialogListItem(
                              selected: _selected.contains(i),
                              leading: SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: _selected.contains(i),
                                  onChanged: _saving
                                      ? null
                                      : (value) => setState(() {
                                          value == true
                                              ? _selected.add(i)
                                              : _selected.remove(i);
                                        }),
                                ),
                              ),
                              title: Text(files[i].note.displayTitle),
                              subtitle: Text(
                                '${files[i].path}${files[i].duplicate ? '\n${context.tr('Already imported')}' : ''}${files[i].warnings.isNotEmpty ? '\n${context.tr('Images could not be imported')}: ${files[i].warnings.join(', ')}' : ''}',
                              ),
                              trailing: Icon(
                                files[i].duplicate
                                    ? Icons.content_copy_rounded
                                    : Icons.description_outlined,
                                size: 16,
                                color: files[i].duplicate
                                    ? p.warning
                                    : p.textFaint,
                              ),
                              onTap: _saving
                                  ? null
                                  : () => setState(() {
                                      _selected.contains(i)
                                          ? _selected.remove(i)
                                          : _selected.add(i);
                                    }),
                            ),
                          if (plan.skipped.isNotEmpty)
                            ExpansionTile(
                              dense: true,
                              leading: Icon(
                                Icons.block_rounded,
                                size: 18,
                                color: p.textFaint,
                              ),
                              title: Text(
                                '${context.tr('Skipped files')} (${plan.skipped.length})',
                                style: const TextStyle(fontSize: Fs.small),
                              ),
                              children: [
                                for (final path in plan.skipped.take(100))
                                  ListTile(
                                    dense: true,
                                    title: Text(
                                      path,
                                      style: const TextStyle(
                                        fontSize: Fs.small,
                                      ),
                                    ),
                                    subtitle: Text(
                                      context.tr(
                                        'Unsupported, unreadable or too large',
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
      showClose: !_saving,
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: plan == null || _selected.isEmpty || _saving
              ? null
              : _save,
          child: Text(context.tr(_saving ? 'Saving…' : 'Import selected')),
        ),
      ],
    );
  }
}
