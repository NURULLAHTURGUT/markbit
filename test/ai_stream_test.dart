import 'dart:async';
import 'dart:convert';
import 'package:markbit/domain/ai/ai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _StreamClient extends http.BaseClient {
  _StreamClient(this.response);
  final Future<http.StreamedResponse> Function() response;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => response();
  @override
  void close() => closed = true;
}

void main() {
  const messages = [ChatMessage(ChatRole.user, 'Analysis')];
  AiClient client(String body, {String type = 'text/event-stream'}) => AiClient(
    baseUrl: 'https://openrouter.ai/api/v1',
    model: 'test',
    createClient: () => MockClient(
      (_) async => http.Response(body, 200, headers: {'content-type': type}),
    ),
  );

  test(
    'HTTP 200 SSE provider errors are surfaced instead of becoming empty completions',
    () async {
      await expectLater(
        client(
          'data: {"error":{"message":"Upstream unavailable"}}\n\ndata: [DONE]\n\n',
        ).streamChat(messages).join(),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('Upstream unavailable'),
          ),
        ),
      );
    },
  );
  test('reasoning-only token exhaustion gives the actual limit reason', () async {
    await expectLater(
      client(
        'data: {"choices":[{"delta":{"reasoning":"hidden thinking"}}]}\n\ndata: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\ndata: [DONE]\n\n',
      ).streamChat(messages).join(),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('response budget'),
        ),
      ),
    );
  });
  test(
    'reasoning frames and keepalives do not finish the request before visible content',
    () async {
      expect(
        await client(
          ': keepalive\n\ndata: {"choices":[{"delta":{"reasoning":"private"}}]}\n\ndata: {"choices":[{"delta":{"content":"Hello"}}]}\n\ndata: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
        ).streamChat(messages).join(),
        'Hello',
      );
    },
  );
  test(
    'partial output at token limit and broken connection are never marked complete',
    () async {
      await expectLater(
        client(
          'data: {"choices":[{"delta":{"content":"Partial"},"finish_reason":"length"}]}\n\ndata: [DONE]\n\n',
        ).streamChat(messages).join(),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('incomplete'),
          ),
        ),
      );
      await expectLater(
        client(
          'data: {"choices":[{"delta":{"content":"Partial"}}]}\n\n',
        ).streamChat(messages).join(),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('connection ended'),
          ),
        ),
      );
    },
  );
  test('JSON fallback and structured text content are supported', () async {
    expect(
      await client(
        '{"choices":[{"message":{"content":[{"type":"text","text":"Hello"}]},"finish_reason":"stop"}]}',
        type: 'application/json',
      ).streamChat(messages).join(),
      'Hello',
    );
  });
  test('OpenRouter request allocates an explicit output budget', () async {
    Map<String, dynamic>? body;
    final c = AiClient(
      baseUrl: 'https://openrouter.ai/api/v1',
      model: 'test',
      createClient: () => MockClient((r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response(
          'data: {"choices":[{"delta":{"content":"OK"}}]}\n\ndata: [DONE]\n\n',
          200,
        );
      }),
    );
    expect(await c.streamChat(messages).join(), 'OK');
    expect(body!['max_tokens'], 16384);
    expect(c.connectionTimeout, const Duration(minutes: 2));
    expect(c.idleTimeout, const Duration(minutes: 3));
  });
  test('stream timeout closes the HTTP client and reports timeout', () async {
    final stream = StreamController<List<int>>();
    final httpClient = _StreamClient(
      () async => http.StreamedResponse(stream.stream, 200),
    );
    final c = AiClient(
      baseUrl: 'http://test',
      model: 'test',
      idleTimeout: const Duration(milliseconds: 15),
      createClient: () => httpClient,
    );
    await expectLater(
      c.streamChat(messages).join(),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('in time'),
        ),
      ),
    );
    expect(httpClient.closed, isTrue);
    await stream.close();
  });
}
