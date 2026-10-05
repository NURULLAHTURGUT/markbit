import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/bare_decoration.dart';
import '../../core/widgets/cover_image.dart';
import '../../data/models/note.dart';
import '../dialogs/dialogs.dart';

class NoteCoverHeader extends StatefulWidget {
  const NoteCoverHeader({
    super.key,
    required this.note,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCoverChanged,
    this.collapsed = false,
  });
  final Note note;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;
  final ValueChanged<String?> onCoverChanged;

  /// Shrinks a cover to a slim band (e.g. once the note is scrolled) so the
  /// content gets the vertical space.
  final bool collapsed;
  @override
  State<NoteCoverHeader> createState() => _NoteCoverHeaderState();
}

class _NoteCoverHeaderState extends State<NoteCoverHeader> {
  bool _picking = false;
  bool _hovered = false;

  /// Touch platforms have no hover, so their cover actions stay visible.
  static final bool _touch = Platform.isAndroid || Platform.isIOS;
  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        dialogTitle: context.tr('Choose cover image'),
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.size > 10 * 1024 * 1024) {
        throw const FormatException('Choose an image smaller than 10 MB.');
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 1600,
        allowUpscaling: false,
      );
      try {
        final frame = await codec.getNextFrame();
        try {
          final data = await frame.image.toByteData(
            format: ui.ImageByteFormat.png,
          );
          if (data == null || data.lengthInBytes > 10 * 1024 * 1024) {
            throw const FormatException('Choose an image smaller than 10 MB.');
          }
          if (mounted) {
            widget.onCoverChanged(
              base64Encode(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              ),
            );
          }
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          context.tr(
            e is FormatException ? e.message : 'Could not open this image.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final covered = widget.note.coverImage != null;
    final disabled = widget.note.trashed;
    final foreground = covered ? Colors.white : p.textMuted;
    final showActions =
        _touch || _hovered || _picking || widget.focusNode.hasFocus;
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 4,
      children: [
        TextButton.icon(
          onPressed: disabled || _picking ? null : _pick,
          style: TextButton.styleFrom(
            foregroundColor: foreground,
            backgroundColor: covered
                ? Colors.black.withValues(alpha: .45)
                : null,
          ),
          icon: _picking
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : const Icon(Icons.image_outlined, size: 17),
          label: Text(context.tr(covered ? 'Change cover' : 'Add cover')),
        ),
        if (covered)
          IconButton(
            onPressed: disabled || _picking
                ? null
                : () => widget.onCoverChanged(null),
            tooltip: context.tr('Remove cover'),
            icon: Icon(Icons.close_rounded, size: 18, color: foreground),
          ),
      ],
    );
    final title = TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      readOnly: disabled,
      textInputAction: TextInputAction.next,
      onChanged: (_) => widget.onChanged(),
      onSubmitted: (_) => widget.onSubmitted(),
      style: TextStyle(
        color: covered ? Colors.white : p.text,
        fontSize: Fs.headline,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      decoration: bareDecoration(
        hint: context.tr(
          widget.note.kind == NoteKind.code ? 'File name' : 'Title',
        ),
        hintStyle: TextStyle(
          color: covered ? Colors.white70 : p.textFaint,
          fontSize: Fs.headline,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    // Actions fade in on hover instead of permanently covering the image.
    final hoverActions = AnimatedOpacity(
      duration: Motion.fast,
      opacity: showActions ? 1 : 0,
      child: actions,
    );
    Widget hoverable(Widget child) => MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: child,
    );
    if (!covered) {
      // Title and actions share one row so an uncovered note does not spend
      // a whole line on the "Add cover" button.
      return hoverable(
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.sm, Sp.lg, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: title),
              const SizedBox(width: Sp.sm),
              hoverActions,
            ],
          ),
        ),
      );
    }
    final collapsed = widget.collapsed && !showActions;
    return hoverable(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.xs),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Rad.lg),
          child: AnimatedContainer(
            duration: Motion.slow,
            curve: Motion.curve,
            height: collapsed ? 64 : 158,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoverImage(data: widget.note.coverImage!),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x77000000), Color(0xCC000000)],
                    ),
                  ),
                ),
                // Positioned children never overflow while the height animates.
                if (!collapsed)
                  Positioned(top: Sp.sm, right: Sp.sm, child: hoverActions),
                Positioned(
                  left: Sp.lg + Sp.xs,
                  right: Sp.lg + Sp.xs,
                  bottom: collapsed ? Sp.xs : Sp.lg,
                  child: title,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
