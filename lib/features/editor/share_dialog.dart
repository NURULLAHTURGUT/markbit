import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/platform_info.dart';
import '../../core/widgets/app_dialog.dart';
import '../../data/docx_export.dart';
import '../../data/export_service.dart';
import '../../data/html_export.dart';
import '../../data/models/note.dart';
import '../../data/note_images.dart';
import '../../data/pdf_export_service.dart';
import '../dialogs/dialogs.dart';

/// Export one note as Markdown, HTML, Word or PDF, copy it, or e-mail it.
Future<void> showShareDialog(BuildContext context, Note note) =>
    showDialog<void>(
      context: context,
      builder: (_) => _ShareDialog(note: note),
    );

class _ShareDialog extends ConsumerWidget {
  const _ShareDialog({required this.note});
  final Note note;

  Future<void> _save(
    BuildContext context,
    String extension,
    Uint8List bytes,
  ) async {
    final name = '${ExportService.safeName(note.displayTitle)}.$extension';
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: context.tr('Export note'),
        fileName: name,
        bytes: bytes,
      );
      if (path == null) return;
      // Desktop pickers only return a path; write the file ourselves.
      if (PlatformInfo.isDesktop) await File(path).writeAsBytes(bytes);
      if (context.mounted) {
        Navigator.pop(context);
        showToast(context, context.tr('Exported to {path}', {'path': path}));
      }
    } catch (e) {
      if (context.mounted) {
        showToast(
          context,
          context.tr('Export failed: {error}', {'error': '$e'}),
        );
      }
    }
  }

  void _copy(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    Navigator.pop(context);
    showToast(context, context.tr(message));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final lib = ref.read(libraryProvider);
    final markdown = note.kind == NoteKind.code
        ? note.body
        : '${note.title.trim().isEmpty ? '' : '# ${note.title.trim()}\n\n'}${NoteImages.expand(note)}';
    String html() => HtmlExport.page(
      note,
      resolveNoteId: lib.findNoteIdByTitle,
      language: AppStrings.current.locale.languageCode,
    );
    final plain = note.body
        .replaceAll(RegExp(r'\s*<!-- task:.*? -->'), '')
        .replaceAll(NoteImages.references, '');

    Widget option(
      IconData icon,
      String title,
      String subtitle,
      VoidCallback onTap,
    ) => DialogListItem(
      leading: Icon(icon),
      title: Text(context.tr(title)),
      subtitle: Text(context.tr(subtitle)),
      onTap: onTap,
    );

    return AppDialog(
      icon: Icons.ios_share_rounded,
      title: context.tr('Export and share'),
      subtitle: note.displayTitle,
      width: 520,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogLabel(context.tr('Save as file')),
          option(
            Icons.description_outlined,
            note.kind == NoteKind.code ? 'Source file' : 'Markdown (.md)',
            'Plain text, opens anywhere',
            () {
              Navigator.pop(context);
              ExportService.exportNote(context, note);
            },
          ),
          if (note.kind == NoteKind.markdown) ...[
            option(
              Icons.html_outlined,
              'Web page (.html)',
              'One file with images, math and diagrams',
              () => _save(
                context,
                'html',
                Uint8List.fromList(utf8.encode(html())),
              ),
            ),
            option(
              Icons.article_outlined,
              'Word document (.docx)',
              'Headings, lists, tables and images for Word or Google Docs',
              () => _save(context, 'docx', DocxExport.build(note)),
            ),
          ],
          option(
            Icons.picture_as_pdf_outlined,
            'PDF',
            'For printing and sending',
            () {
              Navigator.pop(context);
              PdfExportService.export(context, note);
            },
          ),
          const SizedBox(height: Sp.md),
          DialogLabel(context.tr('Copy or send')),
          option(
            Icons.content_copy_rounded,
            'Copy as Markdown',
            'Paste into GitHub, Obsidian or another note app',
            () => _copy(context, markdown, 'Copied to clipboard'),
          ),
          if (note.kind == NoteKind.markdown)
            option(
              Icons.code_rounded,
              'Copy as HTML',
              'Paste into a web page or an HTML e-mail',
              () => _copy(
                context,
                HtmlExport.bodyHtml(note, resolveNoteId: lib.findNoteIdByTitle),
                'Copied to clipboard',
              ),
            ),
          option(
            Icons.mail_outline_rounded,
            'Send by e-mail',
            'Opens your mail app with the note as text',
            () async {
              final body = plain.length > 1800
                  ? '${plain.substring(0, 1800)}\n…'
                  : plain;
              final uri = Uri(
                scheme: 'mailto',
                query: [
                  'subject=${Uri.encodeComponent(note.displayTitle)}',
                  'body=${Uri.encodeComponent(body)}',
                ].join('&'),
              );
              Navigator.pop(context);
              if (!await launchUrl(uri) && context.mounted) {
                showToast(context, context.tr('No e-mail app is set up.'));
              } else if (plain.length > 1800 && context.mounted) {
                showToast(
                  context,
                  context.tr(
                    'The e-mail holds the beginning of the note. Attach an exported file for the rest.',
                  ),
                );
              }
            },
          ),
          if (note.isLocked)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text(
                context.tr(
                  'Exports contain the unlocked content as plain text.',
                ),
                style: TextStyle(color: p.warning, fontSize: Fs.small),
              ),
            ),
        ],
      ),
    );
  }
}
