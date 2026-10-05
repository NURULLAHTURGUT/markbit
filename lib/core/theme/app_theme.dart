import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'tokens.dart';

/// Builds a [ThemeData] from an [AppPalette].
abstract final class AppTheme {
  /// UI font. Theme text styles that are applied through DefaultTextStyle
  /// (chips, list tiles, dialogs, tooltips) replace the inherited style, so
  /// each one names the family explicitly instead of falling back to the
  /// platform font.
  static const String uiFont = 'Inter';

  static const List<String> monoFallback = [
    'Cascadia Code',
    'JetBrains Mono',
    'Fira Code',
    'Consolas',
    'SF Mono',
    'Menlo',
    'Roboto Mono',
    'DejaVu Sans Mono',
    'Ubuntu Mono',
    'monospace',
  ];

  /// Monospace text style used by the editor, code blocks and output.
  static TextStyle mono({
    double size = 13,
    Color? color,
    double height = 1.6,
  }) => TextStyle(
    fontFamily: monoFallback.first,
    fontFamilyFallback: monoFallback.sublist(1),
    fontSize: size,
    height: height,
    color: color,
  );

  static ThemeData build(AppPalette p) {
    final base = ThemeData(
      brightness: p.brightness,
      useMaterial3: true,
      fontFamily: uiFont,
    );
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.accent,
      onSecondary: p.onAccent,
      error: p.danger,
      onError: Colors.white,
      surface: p.editorBg,
      onSurface: p.text,
      surfaceContainerHighest: p.surface,
      outline: p.border,
      outlineVariant: p.border,
    );

    final colored = base.textTheme.apply(
      bodyColor: p.text,
      displayColor: p.text,
    );
    final textTheme = colored.copyWith(
      bodyMedium: colored.bodyMedium?.copyWith(fontSize: Fs.body, height: 1.4),
      bodySmall: colored.bodySmall?.copyWith(fontSize: Fs.small, height: 1.35),
      titleMedium: colored.titleMedium?.copyWith(
        fontSize: Fs.title,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: p.isGlass ? Colors.transparent : p.editorBg,
      // Dropdown routes use canvasColor when no dropdownColor is specified.
      canvasColor: p.isGlass ? p.surface.withValues(alpha: 1) : p.editorBg,
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border, space: 1, thickness: 1),
      textTheme: textTheme,
      iconTheme: IconThemeData(color: p.textMuted, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.md),
          ),
          hoverColor: p.hover,
          highlightColor: p.hover,
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
        ),
        iconColor: p.textMuted,
        textColor: p.text,
        selectedColor: p.accent,
        selectedTileColor: p.selection,
        subtitleTextStyle: TextStyle(
          fontFamily: uiFont,
          color: p.textFaint,
          fontSize: Fs.small,
        ),
        minLeadingWidth: 20,
        horizontalTitleGap: Sp.md,
      ),
      splashFactory: NoSplash.splashFactory,
      hoverColor: p.hover,
      highlightColor: p.hover,
      focusColor: p.accent.withValues(alpha: 0.25),
      visualDensity: VisualDensity.standard,
      extensions: [p],
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.30),
        selectionHandleColor: p.accent,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(6),
        radius: const Radius.circular(Rad.pill),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final hovered =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged);
          return p.textFaint.withValues(alpha: hovered ? 0.75 : 0.45);
        }),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.isGlass ? p.surface.withValues(alpha: 1) : p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: BorderSide(color: p.border),
        ),
        textStyle: TextStyle(
          fontFamily: uiFont,
          color: p.text,
          fontSize: Fs.body,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.isGlass ? p.surface.withValues(alpha: 1) : p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shadowColor: Colors.black.withValues(alpha: p.isDark ? .55 : .22),
        barrierColor: Colors.black.withValues(alpha: p.isDark ? .55 : .32),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: Sp.lg,
          vertical: Sp.xl,
        ),
        titleTextStyle: TextStyle(
          fontFamily: uiFont,
          color: p.text,
          fontSize: Fs.dialogTitle,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
        contentTextStyle: TextStyle(
          fontFamily: uiFont,
          color: p.textMuted,
          fontSize: Fs.body,
          height: 1.5,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg + 2),
          side: BorderSide(color: p.border),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.isGlass ? p.surface.withValues(alpha: 1) : p.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: p.codeBg,
        headerForegroundColor: p.text,
        dividerColor: p.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg + 2),
          side: BorderSide(color: p.border),
        ),
        todayBorder: BorderSide(color: p.accent),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? p.onAccent
              : s.contains(WidgetState.disabled)
              ? p.textFaint
              : p.text,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : null,
        ),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAccent : p.text,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : null,
        ),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.textMuted),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: p.isGlass ? p.surface.withValues(alpha: 1) : p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.lg + 2),
          side: BorderSide(color: p.border),
        ),
        dialBackgroundColor: p.codeBg,
        hourMinuteColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? p.accent.withValues(alpha: p.isDark ? .22 : .12)
              : p.codeBg,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.text,
        ),
        dayPeriodBorderSide: BorderSide(color: p.border),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.textMuted),
        confirmButtonStyle: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.isGlass ? p.surface.withValues(alpha: 1) : p.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: p.isDark ? .55 : .32),
        showDragHandle: true,
        dragHandleColor: p.textFaint.withValues(alpha: .5),
        dragHandleSize: const Size(36, 4),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Rad.lg + 4),
          ),
          side: BorderSide(color: p.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.codeBg,
        selectedColor: p.accent.withValues(alpha: p.isDark ? .22 : .12),
        disabledColor: p.codeBg,
        checkmarkColor: p.accent,
        side: WidgetStateBorderSide.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.selected)
                ? p.accent.withValues(alpha: .55)
                : p.border,
          ),
        ),
        labelStyle: TextStyle(
          fontFamily: uiFont,
          color: p.text,
          fontSize: Fs.small,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: uiFont,
          color: p.accent,
          fontSize: Fs.small,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
        ),
        showCheckmark: false,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.border,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: .12),
        trackHeight: 3,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.border,
        circularTrackColor: Colors.transparent,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: p.textMuted,
        collapsedIconColor: p.textMuted,
        textColor: p.text,
        collapsedTextColor: p.text,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        decoration: BoxDecoration(
          color: p.isDark ? const Color(0xFF0E0F12) : const Color(0xFF24272C),
          borderRadius: BorderRadius.circular(Rad.sm),
        ),
        textStyle: const TextStyle(
          fontFamily: uiFont,
          color: Colors.white,
          fontSize: Fs.caption,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: p.surface,
        contentTextStyle: TextStyle(
          fontFamily: uiFont,
          color: p.text,
          fontSize: Fs.body,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          side: BorderSide(color: p.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: p.codeBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Sp.md,
          vertical: Sp.md,
        ),
        hintStyle: TextStyle(fontFamily: uiFont, color: p.textFaint),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Rad.md),
          borderSide: BorderSide(color: p.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          minimumSize: const Size(44, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          side: BorderSide(color: p.border),
          minimumSize: const Size(44, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.accent,
          minimumSize: const Size(44, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Rad.md),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAccent : p.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.codeBg,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.border,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? p.accent : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.onAccent),
        side: BorderSide(color: p.textFaint, width: 1.5),
      ),
    );
  }
}
