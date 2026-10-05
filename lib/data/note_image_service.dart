import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NoteImage {
  const NoteImage(this.name, this.uri);
  final String name, uri;
}

final noteImagePickerProvider = Provider<Future<NoteImage?> Function(String)>(
  (ref) => NoteImageService.pick,
);

final noteImagesPickerProvider =
    Provider<Future<List<NoteImage>> Function(String)>(
      (ref) => NoteImageService.pickMany,
    );

abstract final class NoteImageService {
  static Future<List<NoteImage>> pickMany(String title) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      allowMultiple: true,
    );
    if (result == null) return [];
    if (result.files.length > 6) {
      throw const FormatException('Choose up to 6 images at a time.');
    }
    final images = <NoteImage>[];
    for (final file in result.files) {
      if (file.size > 10 * 1024 * 1024) {
        throw const FormatException('Choose an image smaller than 10 MB.');
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      images.add(NoteImage(file.name, await embed(bytes)));
    }
    return images;
  }

  static Future<NoteImage?> pick(String title) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > 10 * 1024 * 1024) {
      throw const FormatException('Choose an image smaller than 10 MB.');
    }
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    return NoteImage(file.name, await embed(bytes));
  }

  /// Portable image content uses the same data URI format as Markdown imports.
  /// Decode first to reject damaged files, and limit resolution before insertion.
  static Future<String> embed(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('Choose an image smaller than 10 MB.');
    }
    String? mime;
    if (bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71) {
      mime = 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) {
      mime = 'image/jpeg';
    }
    if (bytes.length >= 6 &&
        ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'GIF') {
      mime = 'image/gif';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      mime = 'image/webp';
    }
    if (mime == null) throw const FormatException('Could not open this image.');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = longest > 1600 ? 1600 / longest : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, 1600),
        targetHeight: (descriptor.height * scale).round().clamp(1, 1600),
      );
      final frame = await codec.getNextFrame();
      try {
        if (scale < 1) {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null || data.lengthInBytes > 10 * 1024 * 1024) {
            throw const FormatException('Choose an image smaller than 10 MB.');
          }
          bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          mime = 'image/png';
        }
      } finally {
        frame.image.dispose();
      }
      return 'data:$mime;base64,${await compute(base64Encode, bytes)}';
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
