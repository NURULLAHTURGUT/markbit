import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../application/persistence_coordinator.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';

class NoteTabs extends ConsumerWidget {
  const NoteTabs({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(openNoteProvider),
        lib = ref.watch(libraryProvider),
        p = context.palette;
    final tabs = state.tabs.where((id) => lib.notes.containsKey(id)).toList();
    // A separate note window shows a single note without tabs.
    if (tabs.isEmpty || ref.watch(noteWindowProvider) != null) {
      return const SizedBox.shrink();
    }
    final unsaved = ref.watch(unsavedNotesProvider);
    final persistence = ref.watch(persistenceProvider);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: p.sidebarBg,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: ListenableBuilder(
        listenable: persistence,
        builder: (context, _) => ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 5),
          children: [
            for (final id in tabs)
              _TabSlot(
                id: id,
                title: lib.notes[id]!.displayTitle,
                onDrop: (dragged) => ref
                    .read(openNoteProvider.notifier)
                    .moveTab(dragged, tabs.indexOf(id)),
                child: _NoteTab(
                  title: lib.notes[id]!.displayTitle,
                  locked: lib.notes[id]!.isLocked,
                  saveFailed: persistence.hasFailed('note:$id'),
                  unsaved:
                      unsaved.contains(id) || persistence.isPending('note:$id'),
                  active: id == state.current,
                  onOpen: () {
                    ref.read(persistenceProvider).flushEditors();
                    ref.read(openNoteProvider.notifier).open(id);
                  },
                  onClose: () {
                    ref.read(persistenceProvider).flushEditors();
                    ref.read(openNoteProvider.notifier).closeTab(id);
                  },
                  onSplit: id == state.current
                      ? null
                      : () {
                          ref.read(persistenceProvider).flushEditors();
                          ref.read(openNoteProvider.notifier).split(id);
                        },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One editor tab. The close button only appears on the active or hovered
/// tab so a row of tabs stays calm; middle-click closes and right-click
/// offers the remaining actions.
class _NoteTab extends StatefulWidget {
  const _NoteTab({
    required this.title,
    required this.active,
    required this.onOpen,
    this.locked = false,
    this.unsaved = false,
    this.saveFailed = false,
    required this.onClose,
    required this.onSplit,
  });
  final String title;
  final bool active;
  final bool locked;

  /// Edits not on disk yet (typing or saving) and a failed save.
  final bool unsaved;
  final bool saveFailed;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback? onSplit;

  @override
  State<_NoteTab> createState() => _NoteTabState();
}

class _NoteTabState extends State<_NoteTab> {
  bool _hover = false;

  Future<void> _menu(Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        overlay.globalToLocal(at) & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'split',
          enabled: widget.onSplit != null,
          height: 38,
          child: Text(context.tr('Open side by side')),
        ),
        PopupMenuItem(
          value: 'close',
          height: 38,
          child: Text(context.tr('Close tab')),
        ),
      ],
    );
    if (!mounted) return;
    switch (choice) {
      case 'split':
        widget.onSplit?.call();
      case 'close':
        widget.onClose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = widget.active;
    final showClose = active || _hover;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        // Middle click closes, as in browsers and code editors.
        onPointerDown: (e) {
          if (e.buttons == kMiddleMouseButton) widget.onClose();
        },
        child: GestureDetector(
          onSecondaryTapDown: (d) => _menu(d.globalPosition),
          onLongPressStart: (d) => _menu(d.globalPosition),
          child: Tooltip(
            message: widget.title,
            waitDuration: const Duration(milliseconds: 800),
            child: Material(
              color: active
                  ? p.selection
                  : (_hover ? p.hover : Colors.transparent),
              borderRadius: BorderRadius.circular(Rad.md),
              child: InkWell(
                borderRadius: BorderRadius.circular(Rad.md),
                onTap: widget.onOpen,
                child: Padding(
                  padding: const EdgeInsets.only(left: Sp.md, right: Sp.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.locked) ...[
                        Icon(Icons.lock_rounded, size: 12, color: p.textFaint),
                        const SizedBox(width: Sp.xs),
                      ],
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? p.text : p.textMuted,
                            fontSize: Fs.small,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (widget.unsaved || widget.saveFailed) ...[
                        const SizedBox(width: Sp.xs + 2),
                        Tooltip(
                          message: context.tr(
                            widget.saveFailed ? 'Not saved' : 'Unsaved changes',
                          ),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: widget.saveFailed ? p.danger : p.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: Sp.xs),
                      // Space is kept while hidden so tabs do not shift
                      // when the pointer moves across them.
                      Opacity(
                        opacity: showClose ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !showClose,
                          child: IconButton(
                            tooltip: context.tr('Close tab'),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                              width: 24,
                              height: 24,
                            ),
                            padding: EdgeInsets.zero,
                            iconSize: 14,
                            icon: Icon(Icons.close_rounded, color: p.textMuted),
                            onPressed: widget.onClose,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Makes a tab draggable and a drop position for other tabs: dropping a tab
/// here places it at this tab's position.
class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.id,
    required this.title,
    required this.onDrop,
    required this.child,
  });

  final String id;
  final String title;
  final ValueChanged<String> onDrop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DragTarget<_TabDrag>(
      onWillAcceptWithDetails: (d) => d.data.id != id,
      onAcceptWithDetails: (d) => onDrop(d.data.id),
      builder: (context, candidates, _) => Container(
        padding: const EdgeInsets.only(right: Sp.xs),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: candidates.isEmpty ? Colors.transparent : p.accent,
              width: 2,
            ),
          ),
        ),
        child: Draggable<_TabDrag>(
          data: _TabDrag(id),
          axis: Axis.horizontal,
          feedback: Material(
            color: p.surface.withValues(alpha: 1),
            elevation: 6,
            borderRadius: BorderRadius.circular(Rad.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.md,
                vertical: Sp.sm,
              ),
              child: Text(
                title,
                style: TextStyle(color: p.text, fontSize: Fs.small),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .4, child: child),
          child: child,
        ),
      ),
    );
  }
}

class _TabDrag {
  const _TabDrag(this.id);
  final String id;
}
