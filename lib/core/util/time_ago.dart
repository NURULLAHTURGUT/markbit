import '../l10n/app_strings.dart';

/// Compact relative time, e.g. "2 hours ago".
String timeAgo(DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inSeconds < 45) return trs('just now');
  if (diff.inMinutes < 2) return trs('1 minute ago');
  if (diff.inMinutes < 60) return trs('{n} minutes ago', {'n': diff.inMinutes});
  if (diff.inHours < 2) return trs('1 hour ago');
  if (diff.inHours < 24) return trs('{n} hours ago', {'n': diff.inHours});
  if (diff.inDays < 2) return trs('1 day ago');
  if (diff.inDays < 7) return trs('{n} days ago', {'n': diff.inDays});
  if (diff.inDays < 14) return trs('1 week ago');
  if (diff.inDays < 30) return trs('{n} weeks ago', {'n': diff.inDays ~/ 7});
  if (diff.inDays < 60) return trs('1 month ago');
  if (diff.inDays < 365) return trs('{n} months ago', {'n': diff.inDays ~/ 30});
  final years = diff.inDays ~/ 365;
  return years <= 1 ? trs('1 year ago') : trs('{n} years ago', {'n': years});
}

String formatDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
  if (d.inSeconds < 60) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(2)} s';
  }
  return '${d.inMinutes} min ${d.inSeconds % 60} s';
}

/// "Deleted in 5 days" for a trashed note, or null when the trash is kept.
String? trashCountdown(
  DateTime? trashedAt,
  int retentionDays, {
  DateTime? now,
}) {
  if (retentionDays <= 0) return null;
  final since = trashedAt ?? (now ?? DateTime.now());
  final deleteAt = since.add(Duration(days: retentionDays));
  final left = deleteAt.difference(now ?? DateTime.now());
  if (left.inHours < 24) return trs('Deleted within a day');
  final days = (left.inHours / 24).ceil();
  return days == 1
      ? trs('Deleted in 1 day')
      : trs('Deleted in {n} days', {'n': days});
}
