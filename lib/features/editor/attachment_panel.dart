import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../application/persistence_coordinator.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/note.dart';
import '../../data/note_attachment_service.dart';
import '../dialogs/dialogs.dart';

class AttachmentPanel extends ConsumerWidget {
  const AttachmentPanel({super.key, required this.note});
  final Note note;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final e in note.attachments.entries)
            Padding(
              padding: const EdgeInsets.only(right: Sp.sm),
              child: Builder(
                builder: (chipContext) => ActionChip(
                  avatar: Icon(
                    Icons.attach_file_rounded,
                    size: 15,
                    color: context.palette.textMuted,
                  ),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      '${e.value.name} • ${(e.value.size / 1024).ceil()} KB',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onPressed: () async {
                    final p = context.palette;
                    final box = chipContext.findRenderObject() as RenderBox?;
                    final overlay =
                        Overlay.of(chipContext).context.findRenderObject()
                            as RenderBox?;
                    if (box == null || overlay == null) return;
                    final topLeft = box.localToGlobal(
                      Offset(0, box.size.height + 4),
                      ancestor: overlay,
                    );
                    PopupMenuItem<String> item(
                      String value,
                      IconData icon,
                      String label, {
                      Color? color,
                    }) => PopupMenuItem<String>(
                      value: value,
                      height: 38,
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: color ?? p.textMuted),
                          const SizedBox(width: 10),
                          Text(label, style: TextStyle(color: color ?? p.text)),
                        ],
                      ),
                    );
                    final action = await showMenu<String>(
                      context: context,
                      position: RelativeRect.fromLTRB(
                        topLeft.dx,
                        topLeft.dy,
                        overlay.size.width - topLeft.dx,
                        0,
                      ),
                      items: [
                        item(
                          'open',
                          Icons.open_in_new_rounded,
                          context.tr('Open'),
                        ),
                        item(
                          'export',
                          Icons.save_alt_rounded,
                          context.tr('Export'),
                        ),
                        if (!note.trashed) ...[
                          const PopupMenuDivider(height: 8),
                          item(
                            'delete',
                            Icons.delete_outline_rounded,
                            context.tr('Remove attachment'),
                            color: p.danger,
                          ),
                        ],
                      ],
                    );
                    if (action == null || !context.mounted) return;
                    try {
                      if (action == 'open') {
                        await NoteAttachmentService.open(e.value);
                      } else if (action == 'export') {
                        final path = await FilePicker.saveFile(
                          fileName: e.value.name,
                        );
                        if (path != null) {
                          await File(
                            path,
                          ).writeAsBytes(base64Decode(e.value.data));
                        }
                      } else {
                        ref.read(persistenceProvider).flushEditors();
                        final current = ref
                            .read(libraryProvider)
                            .notes[note.id];
                        if (current == null) return;
                        final ok = await confirmAction(
                          context,
                          title: context.tr('Remove attachment'),
                          message: e.value.name,
                        );
                        if (ok) {
                          final latest = ref
                              .read(libraryProvider)
                              .notes[note.id];
                          if (latest == null || latest.trashed) return;
                          final files = {...latest.attachments}..remove(e.key);
                          final body = latest.body.replaceAll(
                            RegExp(
                              r'\[[^\]]*\]\(markbit://attachment/' +
                                  RegExp.escape(e.key) +
                                  r'\)',
                            ),
                            '',
                          );
                          ref
                              .read(libraryProvider.notifier)
                              .updateContent(
                                note.id,
                                body: body,
                                attachments: files,
                              );
                        }
                      }
                    } catch (error) {
                      if (context.mounted) {
                        showToast(
                          context,
                          context.tr(
                            error is FormatException
                                ? error.message
                                : 'Could not open this attachment.',
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
