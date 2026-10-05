import 'dart:io';

/// Central place for platform capability checks.
abstract final class PlatformInfo {
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Only desktop platforms may spawn compilers/interpreters.
  static bool get canRunLocalProcesses => isDesktop;

  /// Primary modifier label for shortcut hints.
  static String get modKey => Platform.isMacOS ? '\u2318' : 'Ctrl';
}
