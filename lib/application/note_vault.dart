import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/note.dart';
import '../domain/note_crypto.dart';
import 'persistence_coordinator.dart';
import 'providers.dart';

/// The secret part of a locked note.
@immutable
class LockedContent {
  const LockedContent({
    required this.body,
    this.images = const {},
    this.attachments = const {},
  });

  final String body;
  final Map<String, String> images;
  final Map<String, NoteAttachment> attachments;

  factory LockedContent.of(Note note) => LockedContent(
    body: note.body,
    images: note.images,
    attachments: note.attachments,
  );

  Map<String, dynamic> toJson() => {
    'body': body,
    'images': images,
    'attachments': attachments.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory LockedContent.fromJson(Map<String, dynamic> j) => LockedContent(
    body: (j['body'] as String?) ?? '',
    images: Map<String, String>.from(j['images'] as Map? ?? const {}),
    attachments: (j['attachments'] as Map? ?? const {}).map(
      (k, v) => MapEntry(
        k as String,
        NoteAttachment.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
  );
}

/// An unlocked note: its derived key and decrypted content, in memory only.
@immutable
class UnlockedNote {
  const UnlockedNote({
    required this.key,
    required this.salt,
    required this.iterations,
    required this.content,
    required this.lastUsed,
  });

  final List<int> key;
  final List<int> salt;
  final int iterations;
  final LockedContent content;
  final DateTime lastUsed;

  UnlockedNote copyWith({LockedContent? content, DateTime? lastUsed}) =>
      UnlockedNote(
        key: key,
        salt: salt,
        iterations: iterations,
        content: content ?? this.content,
        lastUsed: lastUsed ?? this.lastUsed,
      );
}

/// Keys and plaintext of unlocked notes. Nothing here is ever written to
/// disk: the library keeps locked notes encrypted, restarting the app locks
/// everything, and notes lock again after [idleTimeout] without use.
class NoteVault extends Notifier<Map<String, UnlockedNote>> {
  static const idleTimeout = Duration(minutes: 10);
  Timer? _idle;

  @override
  Map<String, UnlockedNote> build() {
    ref.onDispose(() => _idle?.cancel());
    return const {};
  }

  @override
  set state(Map<String, UnlockedNote> value) {
    super.state = value;
    // The idle check only runs while something is unlocked.
    if (value.isEmpty) {
      _idle?.cancel();
      _idle = null;
    } else {
      _idle ??= Timer.periodic(const Duration(minutes: 1), (_) => _lockIdle());
    }
  }

  bool isUnlocked(String id) => state.containsKey(id);
  LockedContent? content(String id) => state[id]?.content;

  /// Opens [id] with [password]. Throws [WrongPasswordException].
  Future<void> unlock(String id, String password) async {
    final lock = ref.read(libraryProvider).notes[id]?.lock;
    if (lock == null) return;
    final key = await NoteCrypto.deriveKey(
      password,
      lock.salt,
      lock.iterations,
    );
    final json = await NoteCrypto.open(key, lock);
    if (!ref.mounted) return;
    state = {
      ...state,
      id: UnlockedNote(
        key: key,
        salt: lock.salt,
        iterations: lock.iterations,
        content: LockedContent.fromJson(json),
        lastUsed: DateTime.now(),
      ),
    };
  }

  /// Registers a newly locked note so it can be sealed with [password].
  Future<void> adopt(
    String id,
    String password,
    LockedContent content, {
    int iterations = NoteCrypto.defaultIterations,
  }) async {
    final salt = NoteCrypto.newSalt();
    final key = await NoteCrypto.deriveKey(password, salt, iterations);
    state = {
      ...state,
      id: UnlockedNote(
        key: key,
        salt: salt,
        iterations: iterations,
        content: content,
        lastUsed: DateTime.now(),
      ),
    };
  }

  /// Replaces the in-memory plaintext after an edit.
  void update(String id, LockedContent content) {
    final entry = state[id];
    if (entry == null) return;
    state = {
      ...state,
      id: entry.copyWith(content: content, lastUsed: DateTime.now()),
    };
  }

  /// Marks activity so an open note is not locked while it is being used.
  void touch(String id) {
    final entry = state[id];
    if (entry == null) return;
    // No notification: the timestamp is not part of what widgets show.
    super.state[id] = entry.copyWith(lastUsed: DateTime.now());
  }

  /// Encrypts the current plaintext. Captures key and content synchronously,
  /// so locking right after a save still seals the latest edit.
  Future<NoteLock>? seal(String id) {
    final entry = state[id];
    if (entry == null) return null;
    return NoteCrypto.seal(
      entry.key,
      entry.salt,
      entry.iterations,
      entry.content.toJson(),
    );
  }

  /// Locks [id] again, saving pending edits first.
  void lock(String id) {
    if (!state.containsKey(id)) return;
    ref.read(persistenceProvider).flushEditors();
    state = {...state}..remove(id);
  }

  void lockAll() {
    if (state.isEmpty) return;
    ref.read(persistenceProvider).flushEditors();
    state = const {};
  }

  /// Drops [id] without flushing (the note was deleted or unlocked for good).
  void forget(String id) {
    if (state.containsKey(id)) state = {...state}..remove(id);
  }

  void _lockIdle() {
    final cutoff = DateTime.now().subtract(idleTimeout);
    final idle = [
      for (final e in state.entries)
        if (e.value.lastUsed.isBefore(cutoff)) e.key,
    ];
    for (final id in idle) {
      lock(id);
    }
  }
}

final noteVaultProvider =
    NotifierProvider<NoteVault, Map<String, UnlockedNote>>(NoteVault.new);
