import 'package:flutter/material.dart';

import '../../data/models/note.dart';
import '../theme/app_palette.dart';

/// Icon + colour for a [NoteStatus]. Status is always conveyed by both shape
/// and colour (never colour alone).
({IconData icon, Color color}) statusVisual(
  NoteStatus s,
  AppPalette p,
) => switch (s) {
  NoteStatus.none => (
    icon: Icons.radio_button_unchecked_rounded,
    color: p.textFaint,
  ),
  NoteStatus.active => (icon: Icons.play_circle_rounded, color: p.textMuted),
  NoteStatus.onHold => (icon: Icons.pause_circle_rounded, color: p.warning),
  NoteStatus.completed => (icon: Icons.check_circle_rounded, color: p.success),
  NoteStatus.dropped => (icon: Icons.cancel_rounded, color: p.danger),
};

/// Sidebar variant: Active uses the accent colour.
Color statusSidebarColor(NoteStatus s, AppPalette p) =>
    s == NoteStatus.active ? p.info : statusVisual(s, p).color;
