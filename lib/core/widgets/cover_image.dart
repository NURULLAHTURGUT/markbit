import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';

/// Decode once per cover change, rather than on every editor keystroke.
class CoverImage extends StatefulWidget {
  const CoverImage({super.key, required this.data, this.height, this.width});
  final String data;
  final double? height;
  final double? width;
  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  Uint8List? _bytes;
  void _decode() {
    if (widget.data.startsWith('file:')) {
      _bytes = null;
      return;
    }
    try {
      _bytes = base64Decode(widget.data);
    } catch (_) {
      _bytes = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) _decode();
  }

  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final requestedWidth = widget.width;
    final finiteWidth = requestedWidth != null && requestedWidth.isFinite
        ? requestedWidth
        : 600.0;
    final decodeWidth = (finiteWidth * pixelRatio).round().clamp(1, 1600);
    if (widget.data.startsWith('file:')) {
      return Image.file(
        File.fromUri(Uri.parse(widget.data)),
        height: widget.height,
        width: widget.width,
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) =>
            SizedBox(height: widget.height, width: widget.width),
      );
    }
    return _bytes == null
        ? SizedBox(height: widget.height, width: widget.width)
        : Image.memory(
            _bytes!,
            cacheWidth: decodeWidth,
            height: widget.height,
            width: widget.width,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) =>
                SizedBox(height: widget.height, width: widget.width),
          );
  }
}
