import '../../core/l10n/app_strings.dart';
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'ai_attachment.dart';
import 'ai_model.dart';

enum ChatRole { system, user, assistant }

class ChatMessage {
  const ChatMessage(this.role, this.content, {this.attachments = const []});
  final ChatRole role;
  final String content;
  final List<AiAttachment> attachments;

  Map<String, dynamic> toJson() => {
    'role': role.name,
    'content': attachments.isEmpty
        ? content
        : [
            {'type': 'text', 'text': content},
            for (final file in attachments) file.contentPart,
          ],
  };
}

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Minimal streaming client for any OpenAI-compatible
/// `/chat/completions` endpoint (OpenAI, OpenRouter, Groq, Ollama,
/// LM Studio, llama.cpp server...).
class AiClient {
  AiClient({
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    this.idleTimeout = const Duration(minutes: 3),
    this.connectionTimeout = const Duration(minutes: 2),
    http.Client Function()? createClient,
  }) : _createClient = createClient ?? http.Client.new;

  final String baseUrl;
  final String model;
  final String apiKey;
  final Duration idleTimeout;
  final Duration connectionTimeout;
  int maxOutputTokens = 16384;
  final http.Client Function() _createClient;
  String? reasoningEffort;
  http.Client? _activeClient;

  void close() {
    _activeClient?.close();
    _activeClient = null;
  }

  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  Future<List<AiModel>> models() async {
    final client = _createClient();
    try {
      final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final response = await client
          .get(
            Uri.parse('$base/models'),
            headers: {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw AiException(_describeError(response.statusCode, response.body));
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return (json['data'] as List)
          .map(
            (m) =>
                AiModel.fromJson(Map<String, dynamic>.from(m as Map), baseUrl),
          )
          .toList();
    } finally {
      client.close();
    }
  }

  Stream<String> streamChat(List<ChatMessage> messages) async* {
    if (!isConfigured) {
      throw AiException(
        trs('Set the API base URL and model in Settings first.'),
      );
    }
    final client = _createClient();
    _activeClient = client;
    try {
      final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final request = http.Request('POST', Uri.parse('$base/chat/completions'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'text/event-stream';
      if (apiKey.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $apiKey';
      }
      request.body = jsonEncode({
        'model': model,
        'stream': true,
        if (Uri.tryParse(baseUrl)?.host == 'openrouter.ai')
          'max_tokens': maxOutputTokens,
        'messages': messages.map((m) => m.toJson()).toList(),
        if (reasoningEffort != null)
          if (Uri.tryParse(baseUrl)?.host == 'openrouter.ai')
            'reasoning': {'effort': reasoningEffort}
          else
            'reasoning_effort': reasoningEffort,
      });

      final response = await client.send(request).timeout(connectionTimeout);

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString().timeout(idleTimeout);
        throw AiException(_describeError(response.statusCode, body));
      }

      var hadText = false;
      var hadReasoning = false;
      var done = false;
      String? finishReason;
      String? readContent(dynamic content) {
        if (content is String) return content;
        if (content is List) {
          return content
              .whereType<Map>()
              .map((part) => part['text'])
              .whereType<String>()
              .join();
        }
        return null;
      }

      String? frame(Map<String, dynamic> json) {
        if (json['error'] != null) {
          final error = json['error'];
          final detail = error is Map
              ? error['message']?.toString()
              : error.toString();
          throw AiException(
            trs('AI provider error: {detail}', {
              'detail': detail ?? trs('Unknown error'),
            }),
          );
        }
        final choices = json['choices'];
        if (choices is! List || choices.isEmpty || choices.first is! Map) {
          return null;
        }
        final choice = choices.first as Map;
        if (choice['finish_reason'] is String) {
          finishReason = choice['finish_reason'] as String;
        }
        final delta = choice['delta'] ?? choice['message'];
        if (delta is! Map) return null;
        hadReasoning =
            hadReasoning ||
            delta['reasoning'] != null ||
            delta['reasoning_details'] != null;
        final content =
            readContent(delta['content']) ?? readContent(delta['refusal']);
        if (content != null && content.isNotEmpty) hadText = true;
        return content;
      }

      final type = response.headers['content-type'] ?? '';
      if (type.contains('application/json')) {
        final body = await response.stream.bytesToString().timeout(idleTimeout);
        final json = jsonDecode(body);
        if (json is! Map<String, dynamic>) {
          throw AiException(trs('The AI server returned an invalid response.'));
        }
        final content = frame(json);
        if (content != null && content.isNotEmpty) yield content;
        done = true;
      } else {
        final lines = response.stream
            .timeout(idleTimeout)
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        final dataLines = <String>[];
        String? consume() {
          final data = dataLines.join('\n').trim();
          dataLines.clear();
          if (data.isEmpty) return null;
          if (data == '[DONE]') {
            done = true;
            return null;
          }
          try {
            final json = jsonDecode(data);
            return json is Map<String, dynamic> ? frame(json) : null;
          } on FormatException {
            return null;
          }
        }

        await for (final line in lines) {
          if (line.isEmpty) {
            final content = consume();
            if (content != null && content.isNotEmpty) yield content;
            if (done) break;
          } else if (line.startsWith('data:')) {
            dataLines.add(line.substring(5).trimLeft());
          }
        }
        if (!done && dataLines.isNotEmpty) {
          final content = consume();
          if (content != null && content.isNotEmpty) yield content;
        }
      }
      if (finishReason == 'length') {
        throw AiException(
          trs(
            hadText
                ? 'The response reached the token limit and is incomplete. Retry with a shorter request or lower reasoning effort.'
                : 'The model used its response budget before producing text. Retry with lower reasoning effort or another model.',
          ),
        );
      }
      if (finishReason == 'content_filter') {
        throw AiException(
          trs(
            'The provider filtered the response. Try rephrasing your request.',
          ),
        );
      }
      if (finishReason == 'tool_calls' || finishReason == 'function_call') {
        throw AiException(
          trs(
            'The model requested an unsupported tool instead of replying. Try another model.',
          ),
        );
      }
      if (!done && finishReason == null) {
        throw AiException(
          trs(
            'The AI connection ended before the response completed. Retry this request.',
          ),
        );
      }
      if (!hadText) {
        throw AiException(
          trs(
            hadReasoning
                ? 'The model finished reasoning without producing a text answer. Retry this request or use lower reasoning effort.'
                : 'The model finished without a text response. Try again or choose another model or effort.',
          ),
        );
      }
    } on TimeoutException {
      throw AiException(trs('The AI server did not respond in time.'));
    } on http.ClientException catch (e) {
      throw AiException(trs('Network error: {error}', {'error': e.message}));
    } finally {
      client.close();
      if (identical(_activeClient, client)) _activeClient = null;
    }
  }

  String _describeError(int status, String body) {
    String? detail;
    try {
      final j = jsonDecode(body);
      detail =
          (j['error'] is Map
                  ? j['error']['message']
                  : j['error'] ?? j['message'])
              ?.toString();
    } catch (_) {}
    final hint = switch (status) {
      401 || 403 => trs('Check your API key.'),
      404 => trs('Check the base URL and model name.'),
      429 => trs('Rate limit or quota exceeded.'),
      _ => '',
    };
    return trs('AI request failed (HTTP {status}). {detail} {hint}', {
      'status': status,
      'detail': detail ?? '',
      'hint': hint,
    }).trim();
  }
}
