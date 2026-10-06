import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markbit/app/app.dart';
import 'package:markbit/application/onboarding.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/core/l10n/app_strings.dart';
import 'package:markbit/data/models/library_models.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/repository/library_repository.dart';
import 'package:markbit/features/onboarding/onboarding_page.dart';
import 'package:markbit/features/onboarding/splash_overlay.dart';
import 'package:markbit/features/shell/workspace_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryRepository implements LibraryRepository {
  @override
  String get location => 'memory';
  @override
  Future<void> saveNote(Note note) async {}
  @override
  Future<void> deleteNote(String id) async {}
  @override
  Future<void> saveMeta({
    required List<Notebook> notebooks,
    required List<Tag> tags,
    required List<NoteTemplate> templates,
  }) async {}
  @override
  Future<LibrarySnapshot> load() async => const LibrarySnapshot(
    notes: [],
    notebooks: [],
    tags: [],
    templates: [],
    isFresh: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => AppStrings.current = AppStrings(const Locale('en')));

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    tester.view.physicalSize = const Size(1280, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({...prefs});
    final c = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        libraryRepositoryProvider.overrideWithValue(_MemoryRepository()),
        initialLibraryProvider.overrideWithValue(
          const LibrarySnapshot(
            notes: [],
            notebooks: [Notebook(id: 'inbox', name: 'General', isInbox: true)],
            tags: [],
            templates: [],
            isFresh: false,
          ),
        ),
        onboardingEnabledProvider.overrideWithValue(true),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const MarkbitApp()),
    );
    // Let the startup animation finish.
    await tester.pump(SplashOverlay.duration);
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
  }

  testWidgets('first launch walks through the tour and remembers it', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    expect(find.byType(OnboardingPage), findsOneWidget);
    expect(find.text('Welcome to Markbit'), findsOneWidget);

    await next(tester);
    // Language applies at once: the tour switches to Turkish.
    await tester.tap(find.byKey(const ValueKey('language-tr')));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).language, 'tr');
    expect(find.text('Dilini seç'), findsOneWidget);

    await next(tester);
    await tester.tap(find.byKey(const ValueKey('theme-nord')));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).themeId, 'nord');

    // Six feature slides; a missing screenshot shows an illustration.
    for (var i = 0; i < tourSlides.length; i++) {
      await next(tester);
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Her şeyi saniyeler içinde bul'), findsOneWidget);

    await next(tester); // preferences
    await tester.tap(find.text('Satır numaraları'));
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).lineNumbers, isFalse);

    await next(tester); // done
    await next(tester); // start
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byType(WorkspacePage), findsOneWidget);
    final prefs = c.read(sharedPrefsProvider);
    expect(prefs.getBool('onboarding_done_v1'), isTrue);
  });

  testWidgets('tour only opens on the first launch, even if left halfway', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    expect(find.byType(OnboardingPage), findsOneWidget);
    // Shown once is enough: closing the app now must not bring it back.
    expect(c.read(sharedPrefsProvider).getBool('onboarding_done_v1'), isTrue);
    expect(find.byType(SplashOverlay), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await pumpApp(tester, prefs: {'onboarding_done_v1': true});
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('skip goes straight to the app; tour does not return', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkspacePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await pumpApp(tester, prefs: {'onboarding_done_v1': true});
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.byType(WorkspacePage), findsOneWidget);
  });
}
