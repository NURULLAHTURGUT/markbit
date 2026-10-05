import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'de_strings.dart';
import 'es_strings.dart';
import 'tr_editor.dart';
import 'tr_misc.dart';
import 'tr_settings.dart';

/// Lightweight localisation: English source strings are the keys, other
/// languages provide a translation table. A missing key falls back to the
/// English text, so a forgotten translation is never a crash.
///
/// In widgets use `context.tr('Cancel')`; interpolate with named
/// placeholders: `context.tr('Exported {n} notes', {'n': count})`.
/// Outside widgets use [trs].
class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  /// Set by the delegate whenever the locale changes; used by code that has
  /// no `BuildContext` (notifiers, services).
  static AppStrings current = AppStrings(const Locale('en'));

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('tr'),
    Locale('de'),
    Locale('es'),
  ];

  /// Languages offered in Settings, by code, with their own names.
  static const Map<String, String> languageNames = {
    'en': 'English',
    'tr': 'Türkçe',
    'de': 'Deutsch',
    'es': 'Español',
  };

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static final Map<String, String> _turkish = {
    ...trEditor,
    ...trSettings,
    ...trMisc,
  };

  static final Map<String, Map<String, String>> _tables = {
    'tr': _turkish,
    'de': deStrings,
    'es': esStrings,
  };

  bool get isTurkish => locale.languageCode == 'tr';

  String tr(String en, [Map<String, Object>? args]) {
    var s = _tables[locale.languageCode]?[en] ?? en;
    if (args != null) {
      args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    }
    return s;
  }
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => AppStrings.supportedLocales.any(
    (l) => l.languageCode == locale.languageCode,
  );

  @override
  Future<AppStrings> load(Locale locale) {
    final strings = AppStrings(locale);
    AppStrings.current = strings;
    return SynchronousFuture(strings);
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension TrContext on BuildContext {
  /// Translates [en] for the current locale. Depends on the locale, so the
  /// widget rebuilds when the language changes.
  String tr(String en, [Map<String, Object>? args]) =>
      (Localizations.of<AppStrings>(this, AppStrings) ?? AppStrings.current).tr(
        en,
        args,
      );
}

/// Translation without a `BuildContext` (services, notifiers).
String trs(String en, [Map<String, Object>? args]) =>
    AppStrings.current.tr(en, args);
