import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// A key with modifiers, e.g. Ctrl+Shift+K. Stored as `ctrl+shift+k`.
@immutable
class KeyCombo {
  const KeyCombo(
    this.key, {
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// Ctrl on Windows/Linux, Cmd on macOS.
  factory KeyCombo.mod(
    LogicalKeyboardKey key, {
    bool shift = false,
    bool alt = false,
  }) {
    final mac = !kIsWeb && Platform.isMacOS;
    return KeyCombo(key, control: !mac, meta: mac, shift: shift, alt: alt);
  }

  final LogicalKeyboardKey key;
  final bool control, shift, alt, meta;

  SingleActivator get activator => SingleActivator(
    key,
    control: control,
    shift: shift,
    alt: alt,
    meta: meta,
  );

  bool get hasModifier => control || alt || meta;

  /// Whether [event] (a key down) is this combination.
  bool accepts(KeyEvent event, HardwareKeyboard keyboard) =>
      event.logicalKey == key &&
      keyboard.isControlPressed == control &&
      keyboard.isShiftPressed == shift &&
      keyboard.isAltPressed == alt &&
      keyboard.isMetaPressed == meta;

  String serialize() => [
    if (control) 'ctrl',
    if (meta) 'meta',
    if (alt) 'alt',
    if (shift) 'shift',
    '${key.keyId}',
  ].join('+');

  static KeyCombo? parse(String raw) {
    final parts = raw.split('+');
    final id = int.tryParse(parts.last);
    if (id == null) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(id);
    if (key == null) return null;
    return KeyCombo(
      key,
      control: parts.contains('ctrl'),
      meta: parts.contains('meta'),
      alt: parts.contains('alt'),
      shift: parts.contains('shift'),
    );
  }

  /// Human readable, e.g. "Ctrl+Shift+K".
  String get label {
    final mac = !kIsWeb && Platform.isMacOS;
    final name = switch (key) {
      LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.tab => 'Tab',
      LogicalKeyboardKey.escape => 'Esc',
      LogicalKeyboardKey.backslash => r'\',
      LogicalKeyboardKey.comma => ',',
      LogicalKeyboardKey.period => '.',
      LogicalKeyboardKey.slash => '/',
      LogicalKeyboardKey.arrowLeft => '←',
      LogicalKeyboardKey.arrowRight => '→',
      LogicalKeyboardKey.arrowUp => '↑',
      LogicalKeyboardKey.arrowDown => '↓',
      _ => key.keyLabel.length == 1 ? key.keyLabel.toUpperCase() : key.keyLabel,
    };
    return [
      if (control) 'Ctrl',
      if (meta) mac ? 'Cmd' : 'Win',
      if (alt) mac ? 'Option' : 'Alt',
      if (shift) 'Shift',
      name,
    ].join('+');
  }

  @override
  bool operator ==(Object other) =>
      other is KeyCombo &&
      other.key == key &&
      other.control == control &&
      other.shift == shift &&
      other.alt == alt &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(key, control, shift, alt, meta);
}

/// Every rebindable action, with its English label and default keys.
enum AppShortcut {
  newNote('New note'),
  newCodeNote('New Python code note'),
  commandPalette('Command palette'),
  quickOpen('Quick open'),
  findNotes('Find (notes or in note)'),
  replace('Find and replace in note'),
  toggleSidebar('Toggle sidebar'),
  focusMode('Toggle focus mode'),
  aiAssistant('Toggle AI assistant'),
  settings('Settings'),
  viewEditor('View: Editor'),
  viewSplit('View: Split'),
  viewPreview('View: Preview'),
  previousNote('Previous note'),
  nextNote('Next note'),
  nextTab('Next tab'),
  previousTab('Previous tab'),
  closeTab('Close tab'),
  bold('Bold'),
  italic('Italic'),
  inlineCode('Inline code'),
  runCode('Run code block'),
  suggestions('Show Markdown suggestions');

  const AppShortcut(this.label);
  final String label;

  /// Editor-only shortcuts act while the note text has focus.
  bool get editorOnly => const {
    AppShortcut.bold,
    AppShortcut.italic,
    AppShortcut.inlineCode,
    AppShortcut.runCode,
    AppShortcut.suggestions,
  }.contains(this);

  KeyCombo get defaultCombo => switch (this) {
    newNote => KeyCombo.mod(LogicalKeyboardKey.keyN),
    newCodeNote => KeyCombo.mod(LogicalKeyboardKey.keyN, shift: true),
    commandPalette => KeyCombo.mod(LogicalKeyboardKey.keyK),
    quickOpen => KeyCombo.mod(LogicalKeyboardKey.keyP),
    findNotes => KeyCombo.mod(LogicalKeyboardKey.keyF),
    replace => KeyCombo.mod(LogicalKeyboardKey.keyH),
    toggleSidebar => KeyCombo.mod(LogicalKeyboardKey.backslash),
    focusMode => KeyCombo.mod(LogicalKeyboardKey.keyF, shift: true),
    aiAssistant => KeyCombo.mod(LogicalKeyboardKey.keyJ),
    settings => KeyCombo.mod(LogicalKeyboardKey.comma),
    viewEditor => KeyCombo.mod(LogicalKeyboardKey.digit1),
    viewSplit => KeyCombo.mod(LogicalKeyboardKey.digit2),
    viewPreview => KeyCombo.mod(LogicalKeyboardKey.digit3),
    previousNote => const KeyCombo(LogicalKeyboardKey.arrowLeft, alt: true),
    nextNote => const KeyCombo(LogicalKeyboardKey.arrowRight, alt: true),
    nextTab => const KeyCombo(LogicalKeyboardKey.tab, control: true),
    previousTab => const KeyCombo(
      LogicalKeyboardKey.tab,
      control: true,
      shift: true,
    ),
    closeTab => KeyCombo.mod(LogicalKeyboardKey.keyW),
    bold => KeyCombo.mod(LogicalKeyboardKey.keyB),
    italic => KeyCombo.mod(LogicalKeyboardKey.keyI),
    inlineCode => KeyCombo.mod(LogicalKeyboardKey.keyE),
    runCode => KeyCombo.mod(LogicalKeyboardKey.enter),
    // Ctrl+Space everywhere: on macOS, Cmd+Space opens Spotlight.
    suggestions => const KeyCombo(LogicalKeyboardKey.space, control: true),
  };
}

/// Current key for every action: the user's choice or the default.
final shortcutsProvider = Provider<Map<AppShortcut, KeyCombo>>((ref) {
  final custom = ref.watch(settingsProvider.select((s) => s.shortcuts));
  return {
    for (final action in AppShortcut.values)
      action:
          (custom[action.name] == null
              ? null
              : KeyCombo.parse(custom[action.name]!)) ??
          action.defaultCombo,
  };
});
