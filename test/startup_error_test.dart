import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markbit/app/startup_error.dart';
import 'package:markbit/core/l10n/app_strings.dart';

void main() {
  tearDown(() => AppStrings.current = AppStrings(const Locale('en')));

  testWidgets('startup error is English by default', (tester) async {
    var retried = false;
    await tester.pumpWidget(StartupErrorApp(onRetry: () => retried = true));
    expect(
      find.textContaining('Your data could not be opened'),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('startup error follows the chosen language', (tester) async {
    AppStrings.current = AppStrings(const Locale('tr'));
    await tester.pumpWidget(StartupErrorApp(onRetry: () {}));
    expect(find.textContaining('Veriler açılamadı'), findsOneWidget);
    expect(find.text('Yeniden dene'), findsOneWidget);
    AppStrings.current = AppStrings(const Locale('de'));
    await tester.pumpWidget(StartupErrorApp(onRetry: () {}));
    expect(find.text('Erneut versuchen'), findsOneWidget);
  });
}
