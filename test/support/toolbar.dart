import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Taps a format toolbar action by its label. Actions that do not fit on
/// the single toolbar row live in the "More formatting" menu.
Future<void> tapToolbarAction(WidgetTester tester, String label) async {
  final direct = find.byTooltip(label);
  if (direct.evaluate().isNotEmpty) {
    await tester.tap(direct.first);
    return;
  }
  final more = find.byTooltip('More formatting').evaluate().isNotEmpty
      ? find.byTooltip('More formatting')
      : find.byTooltip('Diğer biçimlendirme');
  await tester.tap(more.first);
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byWidgetPredicate((w) => w is PopupMenuItem),
      matching: find.text(label),
    ),
  );
  // Let the menu close so the action runs before the test continues.
  await tester.pumpAndSettle();
}
