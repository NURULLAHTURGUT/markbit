import 'package:markbit/core/l10n/app_strings.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/widgets/color_picker_panel.dart';
import 'package:markbit/features/editor/format_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/toolbar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'recent colors persist as five unique most recently confirmed values',
    () async {
      for (var i = 1; i <= 7; i++) {
        await RecentColors.remember(Color(0xFF000000 + i));
      }
      await RecentColors.remember(const Color(0xFF000004));
      expect(await RecentColors.load(), [
        const Color(0xFF000004),
        const Color(0xFF000007),
        const Color(0xFF000006),
        const Color(0xFF000005),
        const Color(0xFF000003),
      ]);
    },
  );

  testWidgets(
    'spectrum gestures, HEX validation and recent color recall work in narrow Glass layout',
    (tester) async {
      await RecentColors.remember(const Color(0xFF16A34A));
      Color? chosen;
      bool? valid;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Palettes.zenGlass),
          home: Scaffold(
            body: SizedBox(
              width: 240,
              child: ColorPickerPanel(
                color: const Color(0xFFDC2626),
                onChanged: (c) => chosen = c,
                onValidityChanged: (v) => valid = v,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('recent-color-0')));
      expect(chosen, const Color(0xFF16A34A));
      final square = tester.getRect(
        find.byKey(const ValueKey('color-saturation-value')),
      );
      await tester.tapAt(
        square.topLeft + Offset(square.width * .5, square.height * .5),
      );
      expect(HSVColor.fromColor(chosen!).saturation, closeTo(.5, .01));
      expect(HSVColor.fromColor(chosen!).value, closeTo(.5, .01));
      final hue = tester.getRect(find.byKey(const ValueKey('color-hue')));
      await tester.tapAt(hue.center);
      expect(HSVColor.fromColor(chosen!).hue, closeTo(180, 1));
      await tester.enterText(find.byKey(const ValueKey('color-hex')), 'XX');
      expect(valid, isFalse);
      await tester.enterText(
        find.byKey(const ValueKey('color-hex')),
        '#9333EA',
      );
      expect(valid, isTrue);
      expect(chosen, const Color(0xFF9333EA));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Turkish text dialog applies custom color and disables invalid HEX',
    (tester) async {
      AppStrings.current = AppStrings(const Locale('tr'));
      addTearDown(() => AppStrings.current = AppStrings(const Locale('en')));
      final c = TextEditingController(text: 'Renkli');
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Palettes.zenGlass),
          home: Scaffold(
            body: Column(
              children: [
                TextField(controller: c, focusNode: focus),
                FormatToolbar(
                  controller: c,
                  focusNode: focus,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      await tapToolbarAction(tester, 'Metin rengi');
      await tester.pumpAndSettle();
      expect(find.text('Apply'), findsNothing);
      expect(find.text('Uygula'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('color-hex')), 'bad');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Uygula'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const ValueKey('color-hex')), 'DC2626');
      await tester.pump();
      await tester.tap(find.text('Uygula'));
      await tester.pumpAndSettle();
      expect(c.text, '<span style="color: #DC2626;">Renkli</span>');
      expect((await RecentColors.load()).first, const Color(0xFFDC2626));
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
      focus.dispose();
    },
  );
}
