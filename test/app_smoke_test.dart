import 'dart:io';

import 'package:markbit/app/app.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/data/seed.dart';
import 'package:markbit/features/notelist/notes_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _buildApp(WidgetTester tester, Directory dir) async {
  SharedPreferences.setMockInitialValues({
    'settings_v1': '{"themeId":"solarized-dark"}',
  });
  final prefs = await SharedPreferences.getInstance();
  final repo = await FileLibraryRepository.open(root: dir);
  final snap = await loadOrSeed(repo);
  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      libraryRepositoryProvider.overrideWithValue(repo),
      initialLibraryProvider.overrideWithValue(snap),
    ],
    child: const MarkbitApp(),
  );
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('markbit_ui_');
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets(
    'native caption receives matching dark and light theme colors',
    // The themed title bar is a Windows feature.
    skip: !Platform.isWindows,
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const channel = MethodChannel('markbit/window_theme');
      final calls = <MethodCall>[];
      var nativeGlassSupported = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return call.arguments['glass'] == true && nativeGlassSupported;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final app = (await tester.runAsync(() => _buildApp(tester, dir)))!;
      await tester.pumpWidget(app);
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls.last.arguments['dark'], isTrue);
      final context = tester.element(find.byType(NotesOverview));
      ProviderScope.containerOf(context)
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(themeId: 'light'));
      await tester.pumpAndSettle();
      expect(
        calls.last.arguments['background'],
        Palettes.light.editorBg.toARGB32(),
      );
      expect(
        calls.last.arguments['foreground'],
        Palettes.light.text.toARGB32(),
      );
      expect(calls.last.arguments['dark'], isFalse);
      final settings = ProviderScope.containerOf(
        context,
      ).read(settingsProvider.notifier);
      settings.update((s) => s.copyWith(themeId: 'zen-glass'));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['glass'], isTrue);
      expect(calls.last.arguments['dark'], isFalse);
      final glass = find.byKey(const ValueKey('zen-glass-backdrop'));
      var decoration =
          tester.widget<DecoratedBox>(glass).decoration as BoxDecoration;
      expect(decoration.gradient!.colors.first.a, lessThan(1));
      await tester.tap(find.text('Welcome to Markbit').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      settings.update((s) => s.copyWith(themeId: 'light'));
      await tester.pumpAndSettle();
      expect(calls.last.arguments['glass'], isFalse);
      expect(glass, findsNothing);
      nativeGlassSupported = false;
      settings.update((s) => s.copyWith(themeId: 'zen-glass'));
      await tester.pumpAndSettle();
      decoration =
          tester.widget<DecoratedBox>(glass).decoration as BoxDecoration;
      expect(decoration.gradient!.colors.first.a, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in const [Size(1400, 900), Size(900, 700), Size(390, 800)]) {
    testWidgets('renders and opens a note at ${size.width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final app = (await tester.runAsync(() => _buildApp(tester, dir)))!;
      await tester.pumpWidget(app);
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      expect(find.byType(NotesOverview), findsOneWidget);
      expect(find.text('Welcome to Markbit'), findsWidgets);

      await tester.tap(find.text('Welcome to Markbit').first);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);

      // Route transitions (phone layout) need a few frames to finish.
      await tester.pump(const Duration(milliseconds: 500));
      // The editor title field and the status bar are visible.
      expect(find.textContaining('words'), findsWidgets);
      expect(tester.takeException(), isNull);
      if (size.width == 1400) {
        await tester.tap(find.text('All Notes').first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(NotesOverview), findsOneWidget);
        await tester.tap(find.text('Welcome to Markbit').first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(NotesOverview), findsNothing);
        await tester.tap(find.text('Markbit').first);
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(NotesOverview), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
