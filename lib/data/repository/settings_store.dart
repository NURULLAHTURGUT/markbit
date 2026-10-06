import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';

/// Persists [AppSettings] and secrets.
///
/// Secrets live behind their own methods so the backing store can later be
/// swapped for the OS keychain (e.g. `flutter_secure_storage`) without
/// touching any caller.
class SettingsStore {
  SettingsStore(this._prefs, {FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final Map<String, String> _secrets = {};
  final Map<String, String> _aiKeys = {};
  static String endpointKey(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return url.trim();
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: uri.path.replaceAll(RegExp(r'/+$'), ''),
        )
        .removeFragment()
        .toString();
  }

  Future<void> _tail = Future.value();

  /// Remove legacy plaintext only after the secure write has succeeded.
  Future<void> initialize() async {
    final map = await _secure.read(key: _aiKeysKey);
    if (map != null) {
      _aiKeys.addAll(Map<String, String>.from(jsonDecode(map) as Map));
    }
    final old =
        await _secure.read(key: _aiKeyKey) ?? _prefs.getString(_aiKeyKey);
    if (old != null) {
      _aiKeys.putIfAbsent(endpointKey(load().aiBaseUrl), () => old);
      await _secure.write(key: _aiKeysKey, value: jsonEncode(_aiKeys));
      await _secure.delete(key: _aiKeyKey);
      if (_prefs.containsKey(_aiKeyKey) && !await _prefs.remove(_aiKeyKey)) {
        throw StateError('Could not remove the legacy API key');
      }
    }
    for (final key in [_remoteKeyKey]) {
      final stored = await _secure.read(key: key);
      final legacy = _prefs.getString(key);
      final value = stored ?? legacy ?? '';
      if (stored == null && legacy != null) {
        await _secure.write(key: key, value: value);
      }
      if (legacy != null && !await _prefs.remove(key)) {
        throw StateError('Could not remove the legacy API key');
      }
      _secrets[key] = value;
    }
  }

  Future<void> _setSecret(String key, String value) {
    _secrets[key] = value;
    final task = _tail.then(
      (_) => value.isEmpty
          ? _secure.delete(key: key)
          : _secure.write(key: key, value: value),
    );
    _tail = task.catchError((Object _) {});
    return task;
  }

  static const _settingsKey = 'settings_v1';
  static const _aiKeysKey = 'secret_ai_keys_v2';
  static const _aiKeyKey = 'secret_ai_api_key';
  static const _remoteKeyKey = 'secret_remote_exec_key';

  /// Whether settings were ever saved (false on a first launch).
  bool get hasSaved => _prefs.containsKey(_settingsKey);

  AppSettings load() {
    final raw = _prefs.getString(_settingsKey);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    if (!await _prefs.setString(_settingsKey, jsonEncode(s.toJson()))) {
      throw StateError('Could not save settings');
    }
  }

  String get aiApiKey => aiApiKeyFor(load().aiBaseUrl);
  String aiApiKeyFor(String baseUrl) => _aiKeys[endpointKey(baseUrl)] ?? '';
  Future<void> setAiApiKey(String v, {String? baseUrl}) {
    final id = endpointKey(baseUrl ?? load().aiBaseUrl);
    if (v.isEmpty) {
      _aiKeys.remove(id);
    } else {
      _aiKeys[id] = v;
    }
    return _setSecret(_aiKeysKey, jsonEncode(_aiKeys));
  }

  String aiModelFor(String baseUrl) {
    final raw = _prefs.getString('ai_models_v1');
    final map = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    return map[endpointKey(baseUrl)] as String? ??
        (endpointKey(load().aiBaseUrl) == endpointKey(baseUrl)
            ? load().aiModel
            : '');
  }

  Future<void> setAiModelFor(String baseUrl, String model) async {
    final raw = _prefs.getString('ai_models_v1');
    final map = raw == null
        ? <String, dynamic>{}
        : jsonDecode(raw) as Map<String, dynamic>;
    map[endpointKey(baseUrl)] = model;
    if (!await _prefs.setString('ai_models_v1', jsonEncode(map))) {
      throw StateError('Could not save provider model');
    }
  }

  /// Removes every setting, preference and stored secret (API keys).
  Future<void> clearAll() async {
    _aiKeys.clear();
    _secrets.clear();
    await _tail;
    for (final key in [_aiKeysKey, _aiKeyKey, _remoteKeyKey]) {
      await _secure.delete(key: key);
    }
    if (!await _prefs.clear()) {
      throw StateError('Could not clear preferences');
    }
  }

  String get remoteExecKey => _secrets[_remoteKeyKey] ?? '';
  Future<void> setRemoteExecKey(String v) => _setSecret(_remoteKeyKey, v);
}
