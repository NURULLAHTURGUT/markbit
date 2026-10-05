import 'dart:convert';
import 'package:markbit/application/ai_notifier.dart';
import 'package:markbit/domain/ai/ai_client.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/data/models/app_settings.dart';
import 'package:markbit/data/repository/settings_store.dart';
import 'package:markbit/features/settings/settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReplyClient extends AiClient {
  _ReplyClient() : super(baseUrl: 'http://test', model: 'test');
  @override
  Stream<String> streamChat(List<ChatMessage> messages) =>
      Stream.value('Reply');
  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const router = 'https://openrouter.ai/api/v1';
  const openai = 'https://api.openai.com/v1';
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });
  test(
    'legacy key moves only to its configured provider and stays out of preferences',
    () async {
      final store = SettingsStore(prefs);
      await store.save(const AppSettings(aiBaseUrl: router));
      await prefs.setString('secret_ai_api_key', 'router-secret');
      await store.initialize();
      expect(store.aiApiKeyFor(router), 'router-secret');
      expect(store.aiApiKeyFor(openai), isEmpty);
      expect(prefs.containsKey('secret_ai_api_key'), isFalse);
      expect(
        await const FlutterSecureStorage().read(key: 'secret_ai_api_key'),
        isNull,
      );
      expect(
        prefs.getKeys().any((k) => '${prefs.get(k)}'.contains('router-secret')),
        isFalse,
      );
    },
  );
  test(
    'independent keys survive restart, rapid writes, deletion and normalized URLs',
    () async {
      final store = SettingsStore(prefs);
      await store.initialize();
      await Future.wait([
        store.setAiApiKey('router-secret', baseUrl: router),
        store.setAiApiKey('openai-secret', baseUrl: openai),
      ]);
      final loaded = SettingsStore(prefs);
      await loaded.initialize();
      expect(loaded.aiApiKeyFor('$router/'), 'router-secret');
      expect(loaded.aiApiKeyFor('https://API.OPENAI.COM/v1'), 'openai-secret');
      expect(loaded.aiApiKeyFor('https://another.host/v1'), isEmpty);
      await loaded.setAiApiKey('', baseUrl: router);
      final again = SettingsStore(prefs);
      await again.initialize();
      expect(again.aiApiKeyFor(router), isEmpty);
      expect(again.aiApiKeyFor(openai), 'openai-secret');
      expect(
        jsonDecode(
          (await const FlutterSecureStorage().read(key: 'secret_ai_keys_v2'))!,
        ).length,
        1,
      );
    },
  );
  test('conversation models are scoped to the selected provider', () {
    final chat = AiConversation(
      id: 'chat',
      title: 'Chat',
      model: 'router/model',
      modelEndpoint: router,
    );
    expect(
      chat.effectiveModel(
        const AppSettings(aiBaseUrl: router, aiModel: 'default'),
      ),
      'router/model',
    );
    expect(
      chat.effectiveModel(
        const AppSettings(aiBaseUrl: openai, aiModel: 'openai-model'),
      ),
      'openai-model',
    );
    expect(AiConversation.fromJson(chat.toJson()).modelEndpoint, router);
  });
  test(
    'requests send only the selected provider credential and model',
    () async {
      final store = SettingsStore(prefs);
      await store.initialize();
      await store.setAiApiKey('router-key', baseUrl: router);
      await store.setAiApiKey('openai-key', baseUrl: openai);
      await store.save(
        const AppSettings(aiBaseUrl: router, aiModel: 'router-default'),
      );
      final calls = <(String, String, String)>[];
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          settingsStoreProvider.overrideWithValue(store),
          aiClientFactoryProvider.overrideWithValue((s, key) {
            calls.add((s.aiBaseUrl, s.aiModel, key));
            return _ReplyClient();
          }),
        ],
      );
      final listener = container.listen(aiProvider('note'), (_, _) {});
      addTearDown(listener.close);
      addTearDown(container.dispose);
      final ai = container.read(aiProvider('note').notifier);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      ai.configure(model: 'router-selected');
      ai.send('Hello');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container
          .read(settingsProvider.notifier)
          .update(
            (s) => s.copyWith(aiBaseUrl: openai, aiModel: 'openai-model'),
          );
      ai.send('Hello again');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(calls, [
        (router, 'router-selected', 'router-key'),
        (openai, 'openai-model', 'openai-key'),
      ]);
    },
  );
  testWidgets(
    'settings provider switches restore only that provider key and model',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = SettingsStore(prefs);
      await store.initialize();
      await store.save(
        const AppSettings(aiBaseUrl: router, aiModel: 'router/model'),
      );
      await store.setAiApiKey('router-secret', baseUrl: router);
      await store.setAiApiKey('openai-secret', baseUrl: openai);
      await store.setAiModelFor(openai, 'openai-model');
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          settingsStoreProvider.overrideWithValue(store),
          aiModelsProvider.overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.light),
            home: const Scaffold(body: SettingsView(initialTab: 2)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      TextField keyField() => tester
          .widgetList<TextField>(find.byType(TextField))
          .firstWhere((w) => w.obscureText);
      expect(keyField().controller!.text, 'router-secret');
      await tester.tap(find.widgetWithText(ChoiceChip, 'OpenAI'));
      await tester.pumpAndSettle();
      expect(keyField().controller!.text, 'openai-secret');
      expect(container.read(settingsProvider).aiModel, 'openai-model');
      await tester.enterText(find.byWidget(keyField()), 'new-openai-secret');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'OpenRouter'));
      await tester.pumpAndSettle();
      expect(keyField().controller!.text, 'router-secret');
      expect(container.read(settingsProvider).aiModel, 'router/model');
      expect(store.aiApiKeyFor(openai), 'new-openai-secret');
      await tester.tap(find.widgetWithText(ChoiceChip, 'DeepSeek'));
      await tester.pumpAndSettle();
      expect(keyField().controller!.text, isEmpty);
      expect(container.read(settingsProvider).aiModel, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
