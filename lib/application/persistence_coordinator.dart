import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks asynchronous writes and retains failed operations for an explicit retry.
class PersistenceCoordinator extends ChangeNotifier {
  final Map<String, Future<void> Function()> _failed = {};
  final Set<Future<void>> _pending = {};
  final Map<Object, void Function()> _editors = {};
  final Map<Object, Future<void> Function()> _closers = {};
  final Map<String, int> _versions = {};
  final Map<String, int> _running = {};
  String? error;

  /// Whether a write for [key] (e.g. `note:<id>`) is in progress.
  bool isPending(String key) => (_running[key] ?? 0) > 0;

  /// Whether the last write for [key] failed and awaits a retry.
  bool hasFailed(String key) => _failed.containsKey(key);
  bool closing = false;

  void registerEditor(Object owner, void Function() flush) =>
      _editors[owner] = flush;
  void unregisterEditor(Object owner) => _editors.remove(owner);
  void registerCloser(Object owner, Future<void> Function() flush) =>
      _closers[owner] = flush;
  void unregisterCloser(Object owner) => _closers.remove(owner);

  Future<void> write(String key, Future<void> Function() operation) {
    final version = (_versions[key] ?? 0) + 1;
    _versions[key] = version;
    _running[key] = (_running[key] ?? 0) + 1;
    // Deferred: writes may start while widgets are building.
    scheduleMicrotask(notifyListeners);
    late Future<void> task;
    task = Future<void>.sync(operation)
        .then(
          (_) {
            if (_versions[key] == version) _failed.remove(key);
          },
          onError: (Object e, StackTrace stack) {
            if (_versions[key] == version) _failed[key] = operation;
            error = '$key: $e';
          },
        )
        .whenComplete(() {
          _pending.remove(task);
          final left = (_running[key] ?? 1) - 1;
          if (left <= 0) {
            _running.remove(key);
          } else {
            _running[key] = left;
          }
          if (_failed.isEmpty) error = null;
          notifyListeners();
        });
    _pending.add(task);
    return task;
  }

  void forget(String key) {
    _versions[key] = (_versions[key] ?? 0) + 1;
    _failed.remove(key);
    if (_failed.isEmpty) error = null;
  }

  void flushEditors() {
    for (final callback in List.of(_editors.values)) {
      callback();
    }
  }

  Future<void> flush({bool retry = true}) async {
    flushEditors();
    while (_pending.isNotEmpty) {
      await Future.wait(List.of(_pending));
    }
    if (retry) {
      for (final entry in Map.of(_failed).entries) {
        await write(entry.key, entry.value);
      }
    }
    if (_failed.isNotEmpty) throw StateError(error ?? 'Save failed');
  }

  Future<bool> prepareClose() async {
    if (closing) return false;
    closing = true;
    try {
      flushEditors();
      for (final callback in List.of(_closers.values)) {
        await callback();
      }
      await flush();
      return true;
    } catch (e) {
      error = '$e';
      notifyListeners();
      return false;
    } finally {
      closing = false;
    }
  }
}

final persistenceProvider = Provider<PersistenceCoordinator>((ref) {
  final coordinator = PersistenceCoordinator();
  // Pending writes may finish after a ProviderScope is torn down.
  return coordinator;
});
