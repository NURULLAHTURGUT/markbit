import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../application/shortcuts.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';

/// Settings -> Keyboard shortcuts: every action with its key, rebindable.
class ShortcutsTab extends ConsumerWidget {
  const ShortcutsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final keys = ref.watch(shortcutsProvider);
    final custom = ref.watch(settingsProvider.select((s) => s.shortcuts));

    Future<void> edit(AppShortcut action) async {
      final combo = await showDialog<KeyCombo>(
        context: context,
        builder: (_) => _CaptureDialog(action: action, current: keys),
      );
      if (combo == null) return;
      ref.read(settingsProvider.notifier).update((s) {
        final next = {...s.shortcuts};
        if (combo == action.defaultCombo) {
          next.remove(action.name);
        } else {
          next[action.name] = combo.serialize();
        }
        return s.copyWith(shortcuts: next);
      });
    }

    Widget row(AppShortcut action) {
      final changed = custom.containsKey(action.name);
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Rad.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(Rad.md),
            onTap: () => edit(action),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.sm,
                vertical: Sp.xs + 2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr(action.label),
                      style: const TextStyle(fontSize: Fs.label),
                    ),
                  ),
                  if (changed)
                    IconButton(
                      tooltip: context.tr('Reset to default'),
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      icon: Icon(Icons.undo_rounded, color: p.textFaint),
                      onPressed: () => ref
                          .read(settingsProvider.notifier)
                          .update(
                            (s) => s.copyWith(
                              shortcuts: {...s.shortcuts}..remove(action.name),
                            ),
                          ),
                    ),
                  KeyCap(keys[action]!.label, highlighted: changed),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget group(String title, Iterable<AppShortcut> actions) => Padding(
      padding: const EdgeInsets.only(bottom: Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [DialogLabel(title), for (final a in actions) row(a)],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.lg, right: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Keyboard shortcuts'),
                style: const TextStyle(
                  fontSize: Fs.heading + 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: Sp.xs),
              Text(
                context.tr(
                  'Click an action and press the new key combination.',
                ),
                style: TextStyle(color: p.textMuted, fontSize: Fs.small),
              ),
            ],
          ),
        ),
        group(
          context.tr('General'),
          AppShortcut.values.where((a) => !a.editorOnly),
        ),
        group(
          context.tr('Editor'),
          AppShortcut.values.where((a) => a.editorOnly),
        ),
        DialogLabel(context.tr('Fixed')),
        for (final (keysLabel, action) in [
          ('Alt+1…9', context.tr('Go to tab 1–9 (9 = last)')),
          ('Tab', context.tr('Next table cell, next template field')),
          ('Shift+Tab', context.tr('Previous table cell or field')),
          ('Esc', context.tr('Leave focus mode, hide suggestions')),
          ('Ctrl++ / Ctrl+-', context.tr('Zoom the interface in / out')),
          ('Ctrl+0', context.tr('Reset interface zoom')),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sp.sm,
              vertical: Sp.xs + 2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    action,
                    style: TextStyle(color: p.textMuted, fontSize: Fs.label),
                  ),
                ),
                KeyCap(keysLabel),
              ],
            ),
          ),
        const SizedBox(height: Sp.lg),
        if (custom.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(shortcuts: const {})),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(context.tr('Reset all shortcuts')),
          ),
      ],
    );
  }
}

/// A key combination drawn like keyboard keys.
class KeyCap extends StatelessWidget {
  const KeyCap(this.label, {super.key, this.highlighted = false});
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Wrap(
      spacing: 3,
      children: [
        for (final part in label.split('+'))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: highlighted ? p.accent.withValues(alpha: .14) : p.codeBg,
              borderRadius: BorderRadius.circular(Rad.xs + 1),
              border: Border(
                top: BorderSide(color: p.border),
                left: BorderSide(color: p.border),
                right: BorderSide(color: p.border),
                bottom: BorderSide(color: p.border, width: 2),
              ),
            ),
            child: Text(
              part,
              style: TextStyle(
                color: highlighted ? p.accent : p.text,
                fontSize: Fs.caption,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// Waits for a key combination and reports conflicts.
class _CaptureDialog extends StatefulWidget {
  const _CaptureDialog({required this.action, required this.current});
  final AppShortcut action;
  final Map<AppShortcut, KeyCombo> current;

  @override
  State<_CaptureDialog> createState() => _CaptureDialogState();
}

class _CaptureDialogState extends State<_CaptureDialog> {
  final _focus = FocusNode();
  KeyCombo? _combo;

  static final _modifiers = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.alt,
    LogicalKeyboardKey.meta,
  };

  static bool _functionKey(LogicalKeyboardKey key) =>
      key.keyLabel.startsWith('F') && key.keyLabel.length <= 3;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    final key = event.logicalKey;
    if (_modifiers.contains(key)) return KeyEventResult.handled;
    final kb = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.escape && !kb.isControlPressed) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    setState(
      () => _combo = KeyCombo(
        key,
        control: kb.isControlPressed,
        shift: kb.isShiftPressed,
        alt: kb.isAltPressed,
        meta: kb.isMetaPressed,
      ),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final combo = _combo;
    // Plain letters would stop typing; require a modifier or function key.
    final usable =
        combo != null && (combo.hasModifier || _functionKey(combo.key));
    final conflict = combo == null
        ? null
        : widget.current.entries
              .where((e) => e.key != widget.action && e.value == combo)
              .map((e) => e.key)
              .firstOrNull;
    return AppDialog(
      icon: Icons.keyboard_outlined,
      title: context.tr(widget.action.label),
      subtitle: context.tr('Press the new key combination. Esc cancels.'),
      width: 420,
      content: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.codeBg,
                borderRadius: BorderRadius.circular(Rad.md),
                border: Border.all(color: p.accent.withValues(alpha: .5)),
              ),
              child: combo == null
                  ? Text(
                      context.tr('Waiting for keys…'),
                      style: TextStyle(color: p.textFaint),
                    )
                  : KeyCap(combo.label, highlighted: true),
            ),
            const SizedBox(height: Sp.sm),
            if (combo != null && !usable)
              Text(
                context.tr(
                  'Add Ctrl, Alt or Cmd so the key can still be typed.',
                ),
                style: TextStyle(color: p.danger, fontSize: Fs.small),
              )
            else if (conflict != null)
              Text(
                context.tr('Also used by "{action}". Both will be triggered.', {
                  'action': context.tr(conflict.label),
                }),
                style: TextStyle(color: p.warning, fontSize: Fs.small),
              ),
          ],
        ),
      ),
      footerLeading: TextButton(
        onPressed: () => Navigator.pop(context, widget.action.defaultCombo),
        child: Text(context.tr('Default')),
      ),
      actions: [
        const DialogCancelButton(),
        FilledButton(
          onPressed: usable ? () => Navigator.pop(context, combo) : null,
          child: Text(context.tr('Save')),
        ),
      ],
    );
  }
}
