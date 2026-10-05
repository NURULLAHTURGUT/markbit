import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bulk_note_actions.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';

/// Notes being dragged (onto a notebook or tag in the sidebar).
class NoteDragData {
  const NoteDragData(this.ids);
  final List<String> ids;
}

/// A notebook being dragged onto another notebook (re-nesting).
class NotebookDragData {
  const NotebookDragData(this.id);
  final String id;
}

bool _pointerPlatform(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform != TargetPlatform.android && platform != TargetPlatform.iOS;
}

/// Makes a note row or card draggable with the mouse. When the note is part
/// of the current multi-selection, the whole selection is dragged. Touch
/// platforms keep long-press for the context menu instead.
class NoteDraggable extends ConsumerWidget {
  const NoteDraggable({
    super.key,
    required this.noteId,
    required this.title,
    required this.child,
  });

  final String noteId;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_pointerPlatform(context)) return child;
    final selection = ref.watch(noteSelectionProvider);
    final ids = selection.enabled && selection.ids.contains(noteId)
        ? selection.ids.toList()
        : [noteId];
    return Draggable<NoteDragData>(
      data: NoteDragData(ids),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: DragFeedback(
        icon: Icons.description_outlined,
        label: ids.length == 1
            ? title
            : context.tr('{n} notes', {'n': ids.length}),
      ),
      childWhenDragging: Opacity(opacity: .45, child: child),
      child: child,
    );
  }
}

/// Makes a sidebar notebook draggable so it can be nested elsewhere.
class NotebookDraggable extends StatelessWidget {
  const NotebookDraggable({
    super.key,
    required this.notebookId,
    required this.name,
    required this.child,
  });

  final String notebookId;
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!_pointerPlatform(context)) return child;
    return Draggable<NotebookDragData>(
      data: NotebookDragData(notebookId),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: DragFeedback(icon: Icons.folder_outlined, label: name),
      childWhenDragging: Opacity(opacity: .45, child: child),
      child: child,
    );
  }
}

/// The small label that follows the pointer while dragging.
class DragFeedback extends StatelessWidget {
  const DragFeedback({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Transform.translate(
      offset: const Offset(12, 8),
      child: Material(
        color: p.surface.withValues(alpha: 1),
        elevation: 6,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: BorderSide(color: p.accent.withValues(alpha: .6)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.md,
            vertical: Sp.sm,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: p.accent),
                const SizedBox(width: Sp.sm),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.text,
                      fontSize: Fs.small,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
