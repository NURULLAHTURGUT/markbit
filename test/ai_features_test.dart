import 'dart:convert';
import 'dart:async';
import 'package:markbit/application/ai_notifier.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/core/l10n/app_strings.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:markbit/domain/ai/ai_attachment.dart';
import 'package:markbit/domain/ai/ai_client.dart';
import 'package:markbit/domain/ai/ai_model.dart';
import 'package:markbit/domain/ai/ai_visuals.dart';
import 'package:markbit/domain/markdown_utils.dart';
import 'package:markbit/domain/visual_block.dart';
import 'package:markbit/features/ai/ai_panel.dart';
import 'package:markbit/features/editor/preview/visual_block_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const example = '''Intro
```mermaid
mindmap
  root((Sınav Hazırlığı))
    Planlama
      Hedef Belirleme
    Çalışma
      Özetleme
```
Between
```mermaid
pie
  title Haftalık Satış
  "Ürün A" : 30
  "Ürün B" : 20
```
After''';

class _PendingClient extends AiClient {
  _PendingClient() : super(baseUrl: 'http://test', model: 'test');
  final tokens = StreamController<String>();
  @override
  Stream<String> streamChat(List<ChatMessage> messages) => tokens.stream;
  @override
  void close() {
    if (!tokens.isClosed) tokens.close();
  }
}

void main() {
  testWidgets(
    'pending response keeps stop visible and blocks Enter until completion',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final clients = <_PendingClient>[];
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          aiModelsProvider.overrideWith((ref) async => []),
          aiClientFactoryProvider.overrideWithValue((_, _) {
            final c = _PendingClient();
            clients.add(c);
            return c;
          }),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.light),
            localizationsDelegates: const [AppStrings.delegate],
            home: Scaffold(
              body: AiPanel(
                noteId: 'pending',
                noteContext: () => '',
                onInsert: (_) {},
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('ai-input')),
        'Question',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Thinking…'), findsOneWidget);
      expect(find.byTooltip('Stop'), findsOneWidget);
      expect(find.byTooltip('Send'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('ai-input')),
        'Duplicate',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 50));
      expect(clients, hasLength(1));
      clients.single.tokens.close();
      await tester.pumpAndSettle();
      expect(find.text('Thinking…'), findsNothing);
      expect(find.byTooltip('Send'), findsOneWidget);
      expect(container.read(aiProvider('pending')).items.last.isError, isTrue);
      expect(find.byTooltip('Model capabilities'), findsNothing);
      expect(find.text('Retry this request'), findsOneWidget);
      await tester.tap(find.text('Retry this request'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(clients, hasLength(2));
      expect(
        container
            .read(aiProvider('pending'))
            .items
            .where((i) => i.role == ChatRole.user),
        hasLength(1),
      );
      expect(find.byTooltip('Stop'), findsOneWidget);
      clients.last.tokens.add('Recovered');
      clients.last.tokens.close();
      await tester.pumpAndSettle();
      expect(
        container.read(aiProvider('pending')).items.last.text,
        'Recovered',
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('AI insert preserves prose, hierarchy and chart values', () {
    final converted = prepareAiNote(example);
    final blocks = splitSegments(converted).whereType<CodeSegment>().toList();
    expect(blocks.map((b) => b.info), [VisualBlock.fence, VisualBlock.fence]);
    final map = VisualBlock.parse(blocks[0].code)!;
    expect(map.items.map((i) => i.depth), [0, 1, 2, 1, 2]);
    expect(map.items.map((i) => i.label), [
      'Sınav Hazırlığı',
      'Planlama',
      'Hedef Belirleme',
      'Çalışma',
      'Özetleme',
    ]);
    final chart = VisualBlock.parse(blocks[1].code)!;
    expect(chart.style, ChartStyle.donut);
    expect(chart.items.map((i) => i.value), [30, 20]);
    expect(converted, startsWith('Intro\n'));
    expect(converted, contains('\nBetween\n'));
    expect(converted, endsWith('\nAfter'));
    expect(prepareAiNote(converted), converted);
  });

  test(
    'bar and line charts convert; unsupported and incomplete blocks stay intact',
    () {
      for (final style in ['bar', 'line']) {
        final chart = aiVisual(
          'mermaid',
          'xychart-beta\n title "Growth"\n x-axis ["Jan", "Feb"]\n y-axis "Sales" 0 --> 50\n $style [10, 20]',
        )!;
        expect(chart.style.name, style);
        expect(chart.items.map((i) => i.value), [10, 20]);
      }
      for (final source in [
        '```mermaid\nflowchart TD\nA-->B\n```',
        '```mermaid\npie\n"A" : 2',
        '```mermaid\nxychart-beta\nx-axis [a,b]\nbar [1,2]\nline [2,3]\n```',
      ]) {
        expect(prepareAiNote(source), source);
      }
    },
  );

  test('long, multiline and emoji titles remain short valid graphemes', () {
    expect(
      aiChatTitle('  Bir\n\n uzun   mesaj daha fazla kelime ile burada '),
      'Bir uzun mesaj daha fazla kelime…',
    );
    final title = aiChatTitle('👨‍👩‍👧‍👦' * 200);
    expect(title.characters.length, 49);
    expect(title.characters.last, '…');
    expect(aiChatTitle(''), 'Chat 1');
  });

  test(
    'metadata limits effort to supported levels and unknown models stay conservative',
    () {
      final model = AiModel.fromJson({
        'id': 'provider/model',
        'architecture': {
          'input_modalities': ['text', 'image', 'file'],
        },
        'reasoning': {
          'supported_efforts': ['none', 'high'],
          'mandatory': true,
        },
      }, 'https://openrouter.ai/api/v1');
      expect(model.images && model.pdf, isTrue);
      expect(model.efforts, ['high']);
      expect(
        AiModel.fallback('unknown', 'https://example.test/v1').images,
        isFalse,
      );
      expect(
        AiModel.fallback('gpt-4o-mini', 'https://api.openai.com/v1').efforts,
        isEmpty,
      );
      expect(
        AiModel.fallback('gpt-5.2', 'https://api.openai.com/v1').efforts,
        contains('xhigh'),
      );
    },
  );

  test(
    'image, PDF, text and effort serialize correctly for both API dialects',
    () async {
      final files = [
        AiAttachment.fromBytes('image.png', Uint8List.fromList([1, 2, 3])),
        AiAttachment.fromBytes('document.pdf', Uint8List.fromList([4, 5, 6])),
        AiAttachment.fromBytes(
          'notes.txt',
          Uint8List.fromList(utf8.encode('Türkçe belge')),
        ),
      ];
      for (final host in ['api.openai.com', 'openrouter.ai']) {
        Map<String, dynamic>? body;
        final client = AiClient(
          baseUrl: 'https://$host/v1',
          model: 'test',
          createClient: () => MockClient((r) async {
            body = jsonDecode(r.body) as Map<String, dynamic>;
            return http.Response(
              'data: {"choices":[{"delta":{"content":"OK"}}]}\n\ndata: [DONE]\n\n',
              200,
            );
          }),
        )..reasoningEffort = 'high';
        expect(
          await client.streamChat([
            ChatMessage(ChatRole.user, 'Review', attachments: files),
          ]).join(),
          'OK',
        );
        final content = body!['messages'][0]['content'] as List;
        expect(content[1]['image_url']['url'], 'data:image/png;base64,AQID');
        expect(content[2]['file']['filename'], 'document.pdf');
        expect(content[3]['text'], contains('Türkçe belge'));
        if (host == 'openrouter.ai') {
          expect(body!['reasoning'], {'effort': 'high'});
          expect(body!.containsKey('reasoning_effort'), isFalse);
        } else {
          expect(body!['reasoning_effort'], 'high');
        }
      }
    },
  );

  testWidgets(
    'chat header, collapsed history, visual insert and model controls fit',
    (tester) async {
      tester.view.physicalSize = const Size(360, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        'ai_chats_v1_note': jsonEncode({
          'activeId': 'one',
          'conversations': [
            {
              'id': 'one',
              'title': 'First chat',
              'items': [
                {'role': 'user', 'text': 'Question'},
                {'role': 'assistant', 'text': example},
              ],
            },
            {'id': 'two', 'title': 'Second chat', 'items': []},
          ],
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          aiModelsProvider.overrideWith(
            (ref) async => [
              const AiModel(
                id: 'gpt-4o-mini',
                images: true,
                pdf: true,
                efforts: ['low', 'high'],
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      String? inserted;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.light),
            localizationsDelegates: const [
              AppStrings.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppStrings.supportedLocales,
            home: Scaffold(
              body: AiPanel(
                noteId: 'note',
                noteContext: () => '',
                onClose: () {},
                onInsert: (text) => inserted = text,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('AI assistant'), findsNothing);
      expect(find.text('First chat'), findsOneWidget);
      expect(find.text('Second chat'), findsNothing);
      expect(find.byType(VisualBlockView), findsNWidgets(2));
      expect(find.byTooltip('Reasoning effort'), findsOneWidget);
      await tester.ensureVisible(find.text('Insert into note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Insert into note'));
      expect(inserted, prepareAiNote(example));
      expect(find.byTooltip('Regenerate'), findsOneWidget);
      // The title opens the conversation switcher.
      await tester.tap(find.byKey(const ValueKey('ai-conversations')));
      await tester.pumpAndSettle();
      expect(find.text('Second chat'), findsOneWidget);
      await tester.tap(find.text('New chat').last);
      await tester.pumpAndSettle();
      expect(find.text('AI assistant'), findsOneWidget);
      // Quick actions are offered on the empty chat.
      expect(find.text('Quick actions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
