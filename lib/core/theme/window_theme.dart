import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_palette.dart';

class WindowTheme extends StatefulWidget {
  const WindowTheme({super.key, required this.child});
  final Widget child;
  @override
  State<WindowTheme> createState() => _WindowThemeState();
}

class _WindowThemeState extends State<WindowTheme> {
  static const channel = MethodChannel('markbit/window_theme');
  (int, int, bool, bool)? _lastTheme;
  bool _nativeGlass = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = context.palette;
    final color = p.editorBg.toARGB32();
    final theme = (color, p.text.toARGB32(), p.isDark, p.isGlass);
    if (Platform.isWindows && theme != _lastTheme) {
      _lastTheme = theme;
      _applyNativeTheme(p, theme);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!context.palette.isGlass) return widget.child;
    return DecoratedBox(
      key: const ValueKey('zen-glass-backdrop'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _nativeGlass
              ? const [Color(0x20FFFFFF), Color(0x18F2F6FA)]
              : context.palette.isDark
              ? const [Color(0xFF222830), Color(0xFF171D24)]
              : const [Color(0xFFF0F4F8), Color(0xFFE2E9F0)],
        ),
      ),
      child: widget.child,
    );
  }

  Future<void> _applyNativeTheme(
    AppPalette palette,
    (int, int, bool, bool) theme,
  ) async {
    var supported = false;
    try {
      supported =
          await channel.invokeMethod<bool>('setTheme', {
            'background': palette.editorBg.toARGB32(),
            'foreground': palette.text.toARGB32(),
            'dark': palette.isDark,
            'glass': palette.isGlass,
          }) ??
          false;
    } on PlatformException {
      // An opaque gradient keeps the theme readable without a native backdrop.
    } on MissingPluginException {
      // Widget tests and platforms without the Windows runner.
    }
    if (mounted && theme == _lastTheme && supported != _nativeGlass) {
      setState(() => _nativeGlass = supported);
    }
  }
}
