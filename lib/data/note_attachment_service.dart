import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models/note.dart';

abstract final class NoteAttachmentService {
  static const maxSize = 20 * 1024 * 1024;
  static Future<NoteAttachment> read(String path) async {
    final file = File(path);
    final size = await file.length();
    if (size > maxSize) {
      throw const FormatException('Choose a file smaller than 20 MB.');
    }
    final bytes = await file.readAsBytes();
    return NoteAttachment(
      name: p.basename(path),
      data: base64Encode(bytes),
      size: bytes.length,
    );
  }

  static Future<void> open(NoteAttachment attachment) async {
    // Private per-attachment directory prevents collisions. Never execute an embedded file.
    final extension = p.extension(attachment.name).toLowerCase();
    if ({
      '.exe',
      '.com',
      '.bat',
      '.cmd',
      '.ps1',
      '.vbs',
      '.msi',
      '.scr',
      '.lnk',
      '.hta',
    }.contains(extension)) {
      throw const FormatException(
        'Executable attachments cannot be opened. Export the file to inspect it.',
      );
    }
    final root = await getTemporaryDirectory();
    final dir = await Directory(
      p.join(root.path, 'markbit-attachment'),
    ).create(recursive: true);
    final safe = p
        .basename(attachment.name)
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final file = File(
      p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}-$safe'),
    );
    await file.writeAsBytes(base64Decode(attachment.data), flush: true);
    if (!await launchUrl(file.uri)) {
      throw const FormatException('Could not open this attachment.');
    }
  }

  static Future<String> exportBody(Note note, File target) async {
    var body = note.body;
    if (note.attachments.isEmpty) return body;
    final dir = Directory(
      p.join(
        target.parent.path,
        '${p.basenameWithoutExtension(target.path)}-files',
      ),
    );
    await dir.create(recursive: true);
    final resolvedParent = await target.parent.resolveSymbolicLinks(),
        resolvedDir = await dir.resolveSymbolicLinks();
    if (!p.isWithin(resolvedParent, resolvedDir)) {
      throw const FormatException(
        'Attachment folder points outside the export directory.',
      );
    }
    for (final entry in note.attachments.entries) {
      final safe = p
          .basename(entry.value.name)
          .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(entry.key)) {
        throw const FormatException('Invalid attachment identifier.');
      }
      final file = File(p.join(dir.path, '${entry.key}-$safe'));
      await file.writeAsBytes(base64Decode(entry.value.data));
      body = body.replaceAll(
        'markbit://attachment/${entry.key}',
        Uri(
          path: p.posix.join(p.basename(dir.path), p.basename(file.path)),
        ).toString(),
      );
    }
    return body;
  }
}
