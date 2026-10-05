import 'package:flutter/material.dart';

/// Semantic colour tokens for the whole app. Every widget reads colours from
/// here (via `context.palette`) instead of using raw hex values.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.id,
    required this.name,
    required this.brightness,
    required this.sidebarBg,
    required this.listBg,
    required this.editorBg,
    required this.surface,
    required this.codeBg,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.sectionLabel,
    required this.selection,
    required this.hover,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.synKeyword,
    required this.synString,
    required this.synNumber,
    required this.synComment,
    required this.synType,
    required this.synFunction,
    required this.synHeading,
    required this.synLink,
    required this.synMarker,
  });

  final String id;
  final String name;
  final Brightness brightness;

  // Surfaces
  final Color sidebarBg;
  final Color listBg;
  final Color editorBg;
  final Color surface; // popups, dialogs, floating toolbars
  final Color codeBg;
  final Color border;

  // Content
  final Color text;
  final Color textMuted;
  final Color textFaint;

  // Brand / interaction
  final Color accent;
  final Color onAccent;
  final Color sectionLabel;
  final Color selection;
  final Color hover;

  // Semantic
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  // Syntax
  final Color synKeyword;
  final Color synString;
  final Color synNumber;
  final Color synComment;
  final Color synType;
  final Color synFunction;
  final Color synHeading;
  final Color synLink;
  final Color synMarker;

  bool get isDark => brightness == Brightness.dark;
  bool get isGlass => id == 'zen-glass' || id == 'glass-dark';

  /// Colours offered when creating tags.
  static const List<Color> tagColors = [
    Color(0xFF4C8DF6),
    Color(0xFF4CAF7A),
    Color(0xFFE5534B),
    Color(0xFF8E7CE6),
    Color(0xFFE3963E),
    Color(0xFF2BB3A3),
    Color(0xFFD96AA7),
    Color(0xFFC9A227),
  ];

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    // Identity (id, glass handling) switches at the midpoint; colours blend so
    // theme changes animate instead of jumping.
    final o = other;
    final base = t < 0.5 ? this : o;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      id: base.id,
      name: base.name,
      brightness: base.brightness,
      sidebarBg: c(sidebarBg, o.sidebarBg),
      listBg: c(listBg, o.listBg),
      editorBg: c(editorBg, o.editorBg),
      surface: c(surface, o.surface),
      codeBg: c(codeBg, o.codeBg),
      border: c(border, o.border),
      text: c(text, o.text),
      textMuted: c(textMuted, o.textMuted),
      textFaint: c(textFaint, o.textFaint),
      accent: c(accent, o.accent),
      onAccent: c(onAccent, o.onAccent),
      sectionLabel: c(sectionLabel, o.sectionLabel),
      selection: c(selection, o.selection),
      hover: c(hover, o.hover),
      success: c(success, o.success),
      warning: c(warning, o.warning),
      danger: c(danger, o.danger),
      info: c(info, o.info),
      synKeyword: c(synKeyword, o.synKeyword),
      synString: c(synString, o.synString),
      synNumber: c(synNumber, o.synNumber),
      synComment: c(synComment, o.synComment),
      synType: c(synType, o.synType),
      synFunction: c(synFunction, o.synFunction),
      synHeading: c(synHeading, o.synHeading),
      synLink: c(synLink, o.synLink),
      synMarker: c(synMarker, o.synMarker),
    );
  }
}

/// Built-in palettes.
abstract final class Palettes {
  static const light = AppPalette(
    id: 'light',
    name: 'Light',
    brightness: Brightness.light,
    sidebarBg: Color(0xFFECE9E8),
    listBg: Color(0xFFF5F4F3),
    editorBg: Color(0xFFFCFCFB),
    surface: Color(0xFFFFFFFF),
    codeBg: Color(0xFFF1F1EF),
    border: Color(0xFFDAD7D5),
    text: Color(0xFF1F2328),
    textMuted: Color(0xFF5F6670),
    textFaint: Color(0xFF8A919B),
    accent: Color(0xFF2A6BDB),
    onAccent: Color(0xFFFFFFFF),
    sectionLabel: Color(0xFF6B7078),
    selection: Color(0xFFD5E1F6),
    hover: Color(0x14000000),
    success: Color(0xFF1F9D63),
    warning: Color(0xFFC77700),
    danger: Color(0xFFD03B3B),
    info: Color(0xFF2A6BDB),
    synKeyword: Color(0xFFB0246F),
    synString: Color(0xFF1A7F37),
    synNumber: Color(0xFF0A69C7),
    synComment: Color(0xFF7A828C),
    synType: Color(0xFF8250DF),
    synFunction: Color(0xFF0550AE),
    synHeading: Color(0xFFB0246F),
    synLink: Color(0xFF0A69C7),
    synMarker: Color(0xFF9AA1AA),
  );

  static const dark = AppPalette(
    id: 'dark',
    name: 'Dark',
    brightness: Brightness.dark,
    sidebarBg: Color(0xFF16171A),
    listBg: Color(0xFF1C1D21),
    editorBg: Color(0xFF212227),
    surface: Color(0xFF2A2B31),
    codeBg: Color(0xFF191A1E),
    border: Color(0xFF30323A),
    text: Color(0xFFE6E8EB),
    textMuted: Color(0xFFA0A6B0),
    textFaint: Color(0xFF727885),
    accent: Color(0xFF6EA8FE),
    onAccent: Color(0xFF0B1220),
    sectionLabel: Color(0xFF8A90A0),
    selection: Color(0xFF2C3A52),
    hover: Color(0x14FFFFFF),
    success: Color(0xFF4CC38A),
    warning: Color(0xFFE8A33D),
    danger: Color(0xFFF0605D),
    info: Color(0xFF6EA8FE),
    synKeyword: Color(0xFFFF7AB2),
    synString: Color(0xFF8FD18A),
    synNumber: Color(0xFFD9C97C),
    synComment: Color(0xFF7F8796),
    synType: Color(0xFFB79CFF),
    synFunction: Color(0xFF6EC1FF),
    synHeading: Color(0xFF6EC1FF),
    synLink: Color(0xFF6EA8FE),
    synMarker: Color(0xFF5E6472),
  );

  static const solarizedDark = AppPalette(
    id: 'solarized-dark',
    name: 'Solarized Dark',
    brightness: Brightness.dark,
    sidebarBg: Color(0xFF00212B),
    listBg: Color(0xFF00262F),
    editorBg: Color(0xFF002B36),
    surface: Color(0xFF073642),
    codeBg: Color(0xFF00222C),
    border: Color(0xFF0B3C49),
    text: Color(0xFFA4B2B3),
    textMuted: Color(0xFF7E9599),
    textFaint: Color(0xFF5C7479),
    accent: Color(0xFF3AA0E8),
    onAccent: Color(0xFF00212B),
    sectionLabel: Color(0xFF7C82D6),
    selection: Color(0xFF0C4658),
    hover: Color(0x14FFFFFF),
    success: Color(0xFF3FBF9F),
    warning: Color(0xFFE0A21A),
    danger: Color(0xFFE6504F),
    info: Color(0xFF3AA0E8),
    synKeyword: Color(0xFF9DB02A),
    synString: Color(0xFF3FBFB5),
    synNumber: Color(0xFFDD6E3E),
    synComment: Color(0xFF5F7B82),
    synType: Color(0xFFE0A21A),
    synFunction: Color(0xFF3AA0E8),
    synHeading: Color(0xFF3AA0E8),
    synLink: Color(0xFF7C82D6),
    synMarker: Color(0xFF4E6A70),
  );

  static const solarizedLight = AppPalette(
    id: 'solarized-light',
    name: 'Solarized Light',
    brightness: Brightness.light,
    sidebarBg: Color(0xFFEEE8D5),
    listBg: Color(0xFFF6EFDB),
    editorBg: Color(0xFFFDF6E3),
    surface: Color(0xFFFFFBEF),
    codeBg: Color(0xFFF3ECD8),
    border: Color(0xFFDDD5BC),
    text: Color(0xFF4A5E66),
    textMuted: Color(0xFF6D8088),
    textFaint: Color(0xFF8E9C9C),
    accent: Color(0xFF1F7FC4),
    onAccent: Color(0xFFFFFFFF),
    sectionLabel: Color(0xFF6C71C4),
    selection: Color(0xFFE3DAB9),
    hover: Color(0x14000000),
    success: Color(0xFF2E9E85),
    warning: Color(0xFFB58900),
    danger: Color(0xFFDC322F),
    info: Color(0xFF1F7FC4),
    synKeyword: Color(0xFF859900),
    synString: Color(0xFF2AA198),
    synNumber: Color(0xFFCB4B16),
    synComment: Color(0xFF8E9C9C),
    synType: Color(0xFFB58900),
    synFunction: Color(0xFF1F7FC4),
    synHeading: Color(0xFFCB4B16),
    synLink: Color(0xFF6C71C4),
    synMarker: Color(0xFFA8B2AE),
  );

  static const nord = AppPalette(
    id: 'nord',
    name: 'Nord',
    brightness: Brightness.dark,
    sidebarBg: Color(0xFF242933),
    listBg: Color(0xFF2A303B),
    editorBg: Color(0xFF2E3440),
    surface: Color(0xFF3B4252),
    codeBg: Color(0xFF2A303B),
    border: Color(0xFF3B4252),
    text: Color(0xFFD8DEE9),
    textMuted: Color(0xFF9AA5B8),
    textFaint: Color(0xFF6F7B91),
    accent: Color(0xFF88C0D0),
    onAccent: Color(0xFF242933),
    sectionLabel: Color(0xFF81A1C1),
    selection: Color(0xFF3F4A5E),
    hover: Color(0x14FFFFFF),
    success: Color(0xFFA3BE8C),
    warning: Color(0xFFEBCB8B),
    danger: Color(0xFFBF616A),
    info: Color(0xFF81A1C1),
    synKeyword: Color(0xFF81A1C1),
    synString: Color(0xFFA3BE8C),
    synNumber: Color(0xFFB48EAD),
    synComment: Color(0xFF69758C),
    synType: Color(0xFF8FBCBB),
    synFunction: Color(0xFF88C0D0),
    synHeading: Color(0xFF88C0D0),
    synLink: Color(0xFF81A1C1),
    synMarker: Color(0xFF5B677D),
  );

  static const dracula = AppPalette(
    id: 'dracula',
    name: 'Dracula',
    brightness: Brightness.dark,
    sidebarBg: Color(0xFF1E1F29),
    listBg: Color(0xFF232430),
    editorBg: Color(0xFF282A36),
    surface: Color(0xFF343746),
    codeBg: Color(0xFF21222C),
    border: Color(0xFF373A4D),
    text: Color(0xFFF1F1EC),
    textMuted: Color(0xFFA3A8C8),
    textFaint: Color(0xFF7A80A3),
    accent: Color(0xFFBD93F9),
    onAccent: Color(0xFF1E1F29),
    sectionLabel: Color(0xFF9AA0C8),
    selection: Color(0xFF41445A),
    hover: Color(0x14FFFFFF),
    success: Color(0xFF50FA7B),
    warning: Color(0xFFFFB86C),
    danger: Color(0xFFFF6E6E),
    info: Color(0xFF8BE9FD),
    synKeyword: Color(0xFFFF79C6),
    synString: Color(0xFFF1FA8C),
    synNumber: Color(0xFFBD93F9),
    synComment: Color(0xFF7082B8),
    synType: Color(0xFF8BE9FD),
    synFunction: Color(0xFF50FA7B),
    synHeading: Color(0xFFBD93F9),
    synLink: Color(0xFF8BE9FD),
    synMarker: Color(0xFF5B6085),
  );

  static const zenGlass = AppPalette(
    id: 'zen-glass',
    name: 'Glass Light',
    brightness: Brightness.light,
    sidebarBg: Color(0x14FFFFFF),
    listBg: Color(0x18FFFFFF),
    editorBg: Color(0x08FFFFFF),
    surface: Color(0xF2F8FAFC),
    codeBg: Color(0x30FFFFFF),
    border: Color(0x70FFFFFF),
    text: Color(0xFF1E2329),
    textMuted: Color(0xFF303842),
    textFaint: Color(0xFF46515D),
    accent: Color(0xFF296B9C),
    onAccent: Color(0xFFFFFFFF),
    sectionLabel: Color(0xFF35424F),
    selection: Color(0x403D8AC2),
    hover: Color(0x18000000),
    success: Color(0xFF227349),
    warning: Color(0xFF986000),
    danger: Color(0xFFB12D39),
    info: Color(0xFF296B9C),
    synKeyword: Color(0xFF993768),
    synString: Color(0xFF23723C),
    synNumber: Color(0xFF235D9C),
    synComment: Color(0xFF46515D),
    synType: Color(0xFF6843A3),
    synFunction: Color(0xFF235D9C),
    synHeading: Color(0xFF296B9C),
    synLink: Color(0xFF235D9C),
    synMarker: Color(0xFF46515D),
  );

  static const glassDark = AppPalette(
    id: 'glass-dark',
    name: 'Glass Dark',
    brightness: Brightness.dark,
    sidebarBg: Color(0x14FFFFFF),
    listBg: Color(0x18FFFFFF),
    editorBg: Color(0x08FFFFFF),
    surface: Color(0xF2222830),
    codeBg: Color(0x30222830),
    border: Color(0x70FFFFFF),
    text: Color(0xFFF7F9FC),
    textMuted: Color(0xFFE0E7EF),
    textFaint: Color(0xFFC3CDD9),
    accent: Color(0xFFA4D6F5),
    onAccent: Color(0xFF142A3A),
    sectionLabel: Color(0xFFD4DFEB),
    selection: Color(0x403D8AC2),
    hover: Color(0x18FFFFFF),
    success: Color(0xFFA0DFBA),
    warning: Color(0xFFF3D696),
    danger: Color(0xFFFFA4AD),
    info: Color(0xFFA4D6F5),
    synKeyword: Color(0xFFF1A7D0),
    synString: Color(0xFFA0DFBA),
    synNumber: Color(0xFFA4D6F5),
    synComment: Color(0xFFC3CDD9),
    synType: Color(0xFFD5B8FA),
    synFunction: Color(0xFFA4D6F5),
    synHeading: Color(0xFFA4D6F5),
    synLink: Color(0xFFA4D6F5),
    synMarker: Color(0xFFC3CDD9),
  );

  static const List<AppPalette> all = [
    light,
    dark,
    solarizedLight,
    solarizedDark,
    nord,
    dracula,
    zenGlass,
    glassDark,
  ];

  static AppPalette byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => dark);

  /// Resolves a stored theme id. `system` follows the OS brightness.
  static AppPalette resolve(String themeId, Brightness platform) {
    if (themeId == 'system') {
      return platform == Brightness.dark ? dark : light;
    }
    return byId(themeId);
  }
}

extension PaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
