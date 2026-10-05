import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import '../../application/providers.dart';

abstract interface class ChatStore {
  Future<String?> read(String id);
  Future<void> write(String id, Map<String, dynamic> json);
  Future<void> delete(String id);
}

class PreferenceChatStore implements ChatStore {
  PreferenceChatStore(this.prefs);
  final SharedPreferences prefs;
  String? readNow(String id) => prefs.getString('ai_chats_v1_$id');
  @override
  Future<String?> read(String id) async => readNow(id);
  @override
  Future<void> write(String id, Map<String, dynamic> json) async {
    if (!await prefs.setString('ai_chats_v1_$id', jsonEncode(json))) {
      throw StateError('Could not save chat');
    }
  }

  @override
  Future<void> delete(String id) async {
    if (!await prefs.remove('ai_chats_v1_$id')) {
      throw StateError('Could not delete chat');
    }
  }
}

class FileChatStore implements ChatStore {
  FileChatStore(this.directory);
  final Directory directory;
  Future<void> _tail = Future.value();
  final Set<String> _deleted = {};
  SharedPreferences? _legacyPrefs;
  final List<String> migrationWarnings = [];
  final Map<String, String> _attachmentCache = {};
  static void _validate(Map<String, dynamic> json) {
    if (json['conversations'] is! List) {
      throw const FormatException('Invalid conversations');
    }
    for (final chat in json['conversations'] as List) {
      if (chat is! Map ||
          chat['id'] is! String ||
          chat['title'] is! String ||
          chat['items'] is! List) {
        throw const FormatException('Invalid conversation');
      }
      for (final item in [
        ...chat['items'] as List,
        if (chat['draft'] != null) chat['draft'],
      ]) {
        if (item is! Map ||
            !['system', 'user', 'assistant'].contains(item['role']) ||
            item['text'] is! String) {
          throw const FormatException('Invalid chat message');
        }
        if (item['attachments'] != null && item['attachments'] is! List) {
          throw const FormatException('Invalid attachments');
        }
        for (final attachment in item['attachments'] as List? ?? []) {
          if (attachment is! Map ||
              attachment['name'] is! String ||
              attachment['mime'] is! String ||
              attachment['data'] is! String ||
              attachment['size'] is! int ||
              (attachment['text'] != null && attachment['text'] is! String)) {
            throw const FormatException('Invalid attachment');
          }
        }
      }
    }
  }

  File file(String id) {
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid note ID');
    }
    return File(p.join(directory.path, '$id.json'));
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final next = _tail.then((_) => task());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<String?> read(String id) => _enqueue(() async {
    final target = file(id);
    Object? error;
    for (final candidate in [
      target,
      File('${target.path}.tmp'),
      File('${target.path}.bak'),
    ]) {
      if (!await candidate.exists()) continue;
      try {
        final raw = await candidate.readAsString();
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _validate(decoded);
        if (decoded['conversations'] is! List) {
          throw const FormatException('Invalid conversations');
        }
        if (candidate.path != target.path) {
          if (await target.exists()) {
            await target.copy('${target.path}.corrupt');
          }
          await target.writeAsString(raw, flush: true);
        }
        for (final chat in decoded['conversations'] as List) {
          for (final item in [
            ...(chat as Map)['items'] as List,
            if (chat['draft'] != null) chat['draft'],
          ]) {
            for (final attachment
                in (item as Map)['attachments'] as List? ?? []) {
              final data = attachment as Map;
              final asset = data.remove('asset') as String?;
              if (asset == null) continue;
              if (!RegExp(r'^[a-f0-9]{64}\.bin$').hasMatch(asset)) {
                throw const FormatException('Invalid attachment path');
              }
              final bytes = await File(
                p.join(directory.path, 'attachments', id, asset),
              ).readAsBytes();
              data['data'] = base64Encode(bytes);
            }
          }
        }
        return await compute(jsonEncode, decoded);
      } catch (e) {
        error = e;
      }
    }
    final legacy = _legacyPrefs?.getString('ai_chats_v1_$id');
    if (error == null && legacy != null && !_deleted.contains(id)) {
      final decoded = jsonDecode(legacy) as Map<String, dynamic>;
      _validate(decoded);
      if (decoded['conversations'] is! List) {
        throw const FormatException('Unreadable legacy conversations');
      }
      return legacy;
    }
    if (error != null) {
      throw FormatException('Chat recovery failed: ${target.path}: $error');
    }
    return null;
  });

  @override
  Future<void> write(
    String id,
    Map<String, dynamic> json,
  ) => _enqueue(() async {
    if (_deleted.contains(id)) return;
    _validate(json);
    await directory.create(recursive: true);
    final target = file(id);
    final tmp = File('${target.path}.tmp');
    // Clone only containers; attachments stay out of the main conversation file.
    final normalized = {...json, 'conversations': <Map<String, dynamic>>[]};
    final conversations =
        normalized['conversations'] as List<Map<String, dynamic>>;
    for (final originalChat in json['conversations'] as List) {
      final chat = Map<String, dynamic>.from(originalChat as Map);
      final items = <Map<String, dynamic>>[];
      for (final originalItem in [
        ...chat['items'] as List,
        if (chat['draft'] != null) chat['draft'],
      ]) {
        final item = Map<String, dynamic>.from(originalItem as Map);
        final attachments = <Map<String, dynamic>>[];
        for (final originalAttachment in item['attachments'] as List? ?? []) {
          final attachment = Map<String, dynamic>.from(
            originalAttachment as Map,
          );
          final data = attachment['data'] as String? ?? '';
          if (data.isNotEmpty) {
            // Cache only the current note's payloads, bounded to avoid retaining history.
            final cacheKey = '$id:$data';
            var asset = _attachmentCache[cacheKey];
            if (asset == null) {
              final bytes = await compute(base64Decode, data);
              asset = '${sha256.convert(bytes)}.bin';
              final folder = Directory(
                p.join(directory.path, 'attachments', id),
              );
              await folder.create(recursive: true);
              final binary = File(p.join(folder.path, asset));
              if (!await binary.exists()) {
                await binary.writeAsBytes(bytes, flush: true);
              }
              if (_attachmentCache.length >= 4) _attachmentCache.clear();
              _attachmentCache[cacheKey] = asset;
            }
            attachment['asset'] = asset;
            attachment['data'] = '';
          }
          attachments.add(attachment);
        }
        if (attachments.isNotEmpty) item['attachments'] = attachments;
        items.add(item);
      }
      if (chat['draft'] != null) chat['draft'] = items.removeLast();
      chat['items'] = items;
      conversations.add(chat);
    }
    final content = await compute(jsonEncode, normalized);
    await tmp.writeAsString(content, flush: true);
    if (await target.exists()) {
      try {
        jsonDecode(await target.readAsString());
        await target.copy('${target.path}.bak');
      } on FormatException {
        await target.copy('${target.path}.corrupt');
      }
    }
    await tmp.rename(target.path);
    final legacyKey = 'ai_chats_v1_$id';
    if (_legacyPrefs?.containsKey(legacyKey) == true &&
        !await _legacyPrefs!.remove(legacyKey)) {
      throw StateError('Could not remove migrated conversation');
    }
    // A .bak may reference older attachments; retain them until note deletion.
  });
  @override
  Future<void> delete(String id) {
    _deleted.add(id);
    return _enqueue(() async {
      final target = file(id);
      for (final suffix in ['', '.tmp', '.bak', '.corrupt']) {
        final candidate = File('${target.path}$suffix');
        if (await candidate.exists()) await candidate.delete();
      }
      final attachments = Directory(p.join(directory.path, 'attachments', id));
      final expectedRoot = p.normalize(p.absolute(directory.path));
      final resolved = p.normalize(p.absolute(attachments.path));
      if (!p.isWithin(expectedRoot, resolved)) {
        throw const FormatException('Invalid attachment directory');
      }
      if (await attachments.exists()) await attachments.delete(recursive: true);
      _attachmentCache.removeWhere((key, _) => key.startsWith('$id:'));
      final key = 'ai_chats_v1_$id';
      if (_legacyPrefs?.containsKey(key) == true &&
          !await _legacyPrefs!.remove(key)) {
        throw StateError('Could not delete legacy conversation');
      }
    });
  }

  void allowRestored(String id) => _deleted.remove(id);
  Future<void> migrate(SharedPreferences prefs) async {
    _legacyPrefs = prefs;
    migrationWarnings.clear();
    for (final key
        in prefs
            .getKeys()
            .where((key) => key.startsWith('ai_chats_v1_'))
            .toList()) {
      final id = key.substring('ai_chats_v1_'.length);
      try {
        if (!await file(id).exists()) {
          await write(
            id,
            jsonDecode(prefs.getString(key)!) as Map<String, dynamic>,
          );
        } else {
          await read(id);
        }
        if (!await prefs.remove(key)) {
          throw StateError('Could not migrate chat');
        }
      } catch (_) {
        migrationWarnings.add('Conversation migration requires recovery: $id');
      }
    }
  }

  Future<void> flush() => _tail;
}

final chatStoreProvider = Provider<ChatStore>(
  (ref) => PreferenceChatStore(ref.read(sharedPrefsProvider)),
);
