import '../core/widgets/app_notification.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show AppExitResponse;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../application/auto_backup.dart';
import '../application/persistence_coordinator.dart';
import '../core/l10n/app_strings.dart';
import '../core/theme/app_palette.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/window_theme.dart';
import '../features/shell/workspace_page.dart';
import '../features/shell/note_window.dart';
import '../data/repository/library_repository.dart';
import '../features/settings/settings_dialog.dart';

class MarkbitApp extends ConsumerStatefulWidget {
  const MarkbitApp({super.key});

  @override
  ConsumerState<MarkbitApp> createState() => _MarkbitAppState();
}

class _MarkbitAppState extends ConsumerState<MarkbitApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  static const _lifecycle = MethodChannel('markbit/lifecycle');
  AppLifecycleListener? _listener;
  late final AutoBackup _autoBackup;
  late final PersistenceCoordinator _persistence;
  FileLibraryRepository? _warningRepository;
  String? _lastSaveError;
  int _warningCount = 0;
  void _showAppNotice(
    String message,
    NoticeKind kind,
    String action,
    VoidCallback callback,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final overlay = _navigatorKey.currentState?.overlay;
      if (!mounted || overlay == null) return;
      AppNotifications.show(
        overlay.context,
        message,
        overlay: overlay,
        kind: kind,
        duration: const Duration(seconds: 8),
        actionLabel: action,
        onAction: callback,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _saveNotice() {
    final error = _persistence.error;
    if (error == null) {
      _lastSaveError = null;
      return;
    }
    if (_lastSaveError == error) return;
    _lastSaveError = error;
    _showAppNotice(
      context.tr('Changes could not be saved. Keep the app open and retry.'),
      NoticeKind.error,
      context.tr('Retry'),
      () async {
        try {
          await _persistence.flush();
        } catch (_) {
          if (mounted) {
            _lastSaveError = null;
            _saveNotice();
          }
        }
      },
    );
  }

  void _recoveryNotice() {
    final count = _warningRepository?.loadWarnings.value.length ?? 0;
    if (count == 0) {
      _warningCount = 0;
      return;
    }
    if (count == _warningCount) return;
    _warningCount = count;
    _showAppNotice(
      context.tr(
        'Some files required recovery. Review the data recovery details.',
      ),
      NoticeKind.warning,
      context.tr('Data recovery'),
      () {
        final overlay = _navigatorKey.currentState?.overlay;
        if (overlay != null) showSettingsDialog(overlay.context, initialTab: 4);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    final persistence = _persistence = ref.read(persistenceProvider);
    _persistence.addListener(_saveNotice);
    final repository = ref.read(libraryRepositoryProvider);
    if (repository is FileLibraryRepository) {
      _warningRepository = repository;
      repository.loadWarnings.addListener(_recoveryNotice);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _saveNotice();
        _recoveryNotice();
      }
    });
    _lifecycle.setMethodCallHandler((call) async {
      if (call.method == 'requestClose') return persistence.prepareClose();
      throw MissingPluginException();
    });
    _listener = AppLifecycleListener(
      onExitRequested: () async => await persistence.prepareClose()
          ? AppExitResponse.exit
          : AppExitResponse.cancel,
    );
    _ready();
    _autoBackup = ref.read(autoBackupProvider);
    // Separate note windows leave backups to the main window.
    if (ref.read(noteWindowProvider) == null) _autoBackup.start();
  }

  Future<void> _ready() async {
    try {
      await _lifecycle.invokeMethod<void>('ready');
    } on MissingPluginException {
      /* Other platforms use Flutter lifecycle. */
    }
  }

  @override
  void dispose() {
    _persistence.removeListener(_saveNotice);
    _warningRepository?.loadWarnings.removeListener(_recoveryNotice);
    _autoBackup.stop();
    _listener?.dispose();
    _lifecycle.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeId = ref.watch(settingsProvider.select((s) => s.themeId));
    final language = ref.watch(settingsProvider.select((s) => s.language));
    final scale = ref.watch(settingsProvider.select((s) => s.uiScale));

    final ThemeData light;
    final ThemeData dark;
    final ThemeMode mode;
    if (themeId == 'system') {
      light = AppTheme.build(Palettes.light);
      dark = AppTheme.build(Palettes.dark);
      mode = ThemeMode.system;
    } else {
      final palette = Palettes.byId(themeId);
      light = dark = AppTheme.build(palette);
      mode = palette.isDark ? ThemeMode.dark : ThemeMode.light;
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Markbit',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      themeAnimationDuration: const Duration(milliseconds: 200),
      locale: language == 'system' ? null : Locale(language),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: switch (ref.read(noteWindowProvider)) {
        final String id => NoteWindowPage(noteId: id),
        null => const WorkspacePage(),
      },
      builder: (context, child) => WindowTheme(
        child: UiScale(scale: scale, child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Zooms the whole interface (text, icons, spacing, dialogs) by laying it
/// out in a smaller or larger logical size and fitting it to the window.
class UiScale extends StatelessWidget {
  const UiScale({super.key, required this.scale, required this.child});
  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1).abs() < .001) return child;
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.maxWidth / scale,
          constraints.maxHeight / scale,
        );
        return FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: MediaQuery(
              data: media.copyWith(
                size: size,
                devicePixelRatio: media.devicePixelRatio * scale,
                padding: media.padding / scale,
                viewPadding: media.viewPadding / scale,
                viewInsets: media.viewInsets / scale,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
