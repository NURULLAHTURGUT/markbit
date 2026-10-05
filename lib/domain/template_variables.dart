import 'package:intl/intl.dart';

import '../core/util/ids.dart';

/// Values available to `{{…}}` variables in note templates.
class TemplateContext {
  const TemplateContext({
    required this.now,
    required this.title,
    required this.notebook,
    this.language = 'en',
  });

  final DateTime now;
  final String title;
  final String notebook;

  /// `en`, `tr`, `de` or `es`, for weekday and month names.
  final String language;
}

/// Result of expanding a template text.
class ExpandedTemplate {
  const ExpandedTemplate(this.text, this.cursor);
  final String text;

  /// Offset of the first `{{cursor}}` (removed from [text]), if any.
  final int? cursor;
}

/// The variables, for help texts: `{{name}}` and what it produces.
const templateVariables = <(String, String)>[
  ('{{title}}', 'Note title'),
  ('{{date}}', 'Today, 2026-10-05'),
  ('{{time}}', 'Current time, 14:30'),
  ('{{datetime}}', 'Date and time'),
  ('{{weekday}}', 'Day of the week'),
  ('{{day}} {{month}} {{year}}', 'Day, month name, year'),
  ('{{week}}', 'ISO week number'),
  ('{{yesterday}} {{tomorrow}}', 'Neighbouring dates'),
  ('{{date:dd.MM.yyyy}}', 'Date in your own format'),
  ('{{notebook}}', 'Notebook the note is created in'),
  ('{{id}}', 'A short unique id'),
  ('{{cursor}}', 'Where the cursor starts'),
];

const _weekdays = {
  'en': [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ],
  'tr': [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ],
  'de': [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ],
  'es': [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ],
};
const _months = {
  'en': [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ],
  'tr': [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ],
  'de': [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', //
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ],
  'es': [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ],
};

String _two(int n) => n.toString().padLeft(2, '0');
String _iso(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// ISO-8601 week number of [date].
int isoWeek(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final firstDay = DateTime.utc(thursday.year, 1, 1);
  return 1 + thursday.difference(firstDay).inDays ~/ 7;
}

final _variable = RegExp(r'\{\{\s*([a-zA-Z]+)(?::([^}]*))?\s*\}\}');

/// Replaces `{{…}}` variables in [text]. Unknown variables stay as written.
ExpandedTemplate expandTemplate(String text, TemplateContext ctx) {
  final lang = _weekdays.containsKey(ctx.language) ? ctx.language : 'en';
  final now = ctx.now;
  int? cursor;
  final out = StringBuffer();
  var last = 0;
  for (final m in _variable.allMatches(text)) {
    out.write(text.substring(last, m.start));
    last = m.end;
    final name = m[1]!.toLowerCase();
    final arg = m[2]?.trim();
    final value = switch (name) {
      'title' => ctx.title,
      'date' when arg != null && arg.isNotEmpty => _format(now, arg, lang),
      'date' || 'today' => _iso(now),
      'time' => '${_two(now.hour)}:${_two(now.minute)}',
      'datetime' => '${_iso(now)} ${_two(now.hour)}:${_two(now.minute)}',
      'weekday' => _weekdays[lang]![now.weekday - 1],
      'day' => '${now.day}',
      'month' => _months[lang]![now.month - 1],
      'year' => '${now.year}',
      'week' => '${isoWeek(now)}',
      'yesterday' => _iso(now.subtract(const Duration(days: 1))),
      'tomorrow' => _iso(now.add(const Duration(days: 1))),
      'notebook' => ctx.notebook,
      'id' || 'uuid' => newId(),
      'cursor' => '',
      _ => null,
    };
    if (name == 'cursor') cursor ??= out.length;
    out.write(value ?? m[0]);
  }
  out.write(text.substring(last));
  return ExpandedTemplate(out.toString(), cursor);
}

String _format(DateTime now, String pattern, String lang) {
  try {
    return DateFormat(pattern, lang).format(now);
  } catch (_) {
    // Locale data not loaded (or a bad pattern): fall back to English.
    try {
      return DateFormat(pattern).format(now);
    } catch (_) {
      return _iso(now);
    }
  }
}
