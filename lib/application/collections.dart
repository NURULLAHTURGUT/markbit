import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers.dart';
import 'persistence_coordinator.dart';

class SavedCollection {
  const SavedCollection(
    this.id,
    this.name,
    this.query, {
    this.scope = 'all',
    this.scopeId,
    this.scopeStatus,
  });
  final String scope;
  final String? scopeId, scopeStatus;
  factory SavedCollection.fromJson(Map<String, dynamic> j) => SavedCollection(
    j['id'],
    j['name'],
    j['query'],
    scope: j['scope'] ?? 'all',
    scopeId: j['scopeId'],
    scopeStatus: j['scopeStatus'],
  );
  final String id, name, query;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'query': query,
    'scope': scope,
    'scopeId': scopeId,
    'scopeStatus': scopeStatus,
  };
}

class CollectionsNotifier extends Notifier<List<SavedCollection>> {
  @override
  List<SavedCollection> build() {
    try {
      return (jsonDecode(
                ref.read(sharedPrefsProvider).getString('collections_v1') ??
                    '[]',
              )
              as List)
          .map((e) => SavedCollection.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void save(SavedCollection c) {
    state = [...state.where((e) => e.id != c.id), c];
    _persist();
  }

  void remove(String id) {
    state = state.where((e) => e.id != id).toList();
    _persist();
  }

  void _persist() {
    final raw = jsonEncode(state.map((e) => e.toJson()).toList());
    ref.read(persistenceProvider).write('collections', () async {
      if (!await ref
          .read(sharedPrefsProvider)
          .setString('collections_v1', raw)) {
        throw StateError('Could not save collections');
      }
    });
  }
}

final collectionsProvider =
    NotifierProvider<CollectionsNotifier, List<SavedCollection>>(
      CollectionsNotifier.new,
    );
