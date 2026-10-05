import 'package:flutter/material.dart';

/// A text-field decoration with no border, fill or padding.
///
/// `InputDecoration.collapsed` alone is not enough: the app-wide
/// `inputDecorationTheme` defines `enabledBorder`/`focusedBorder`, which win
/// over the collapsed `border`, so every border state is cleared explicitly.
InputDecoration bareDecoration({String? hint, TextStyle? hintStyle}) {
  return InputDecoration(
    isCollapsed: true,
    isDense: true,
    filled: false,
    contentPadding: EdgeInsets.zero,
    hintText: hint,
    hintStyle: hintStyle,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorBorder: InputBorder.none,
    focusedErrorBorder: InputBorder.none,
  );
}
