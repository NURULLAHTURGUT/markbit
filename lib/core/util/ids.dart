import 'dart:math';

final Random _rng = Random.secure();

/// Short, sortable, collision-resistant identifier (time prefix + random).
String newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = List.generate(
    6,
    (_) => _rng.nextInt(36).toRadixString(36),
  ).join();
  return '$time$rand';
}
