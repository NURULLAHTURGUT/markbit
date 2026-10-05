import 'dart:async';
import 'dart:typed_data';
import 'package:markbit/domain/ai/ai_attachment.dart';
import 'package:markbit/domain/ai/ai_model.dart';
import 'package:markbit/application/ai_notifier.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/domain/ai/ai_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Simulate callbacks already queued by an old request, including after cancel.
class _Response extends Stream<String> {
  void Function(String)? data;
  void Function()? done;
  Function? error;
  bool? cancelOnError;
  @override
  StreamSubscription<String> listen(
    void Function(String)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    data = onData;
    error = onError;
    done = onDone;
    this.cancelOnError = cancelOnError;
    return const Stream<String>.empty().listen((_) {});
  }
}

class _Client extends AiClient {
  _Client() : super(baseUrl: 'http://test', model: 'test');
  final response = _Response();
  bool closed = false;
  List<ChatMessage> messages = [];
  @override
  Stream<String> streamChat(List<ChatMessage> messages) {
    this.messages = messages;
    return response;
  }

  @override
  void close() {
    closed = true;
  }
}

void main() {
  late ProviderContainer container;
  late List<_Client> clients;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    clients = [];
    container = ProviderContainer(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        aiClientFactoryProvider.overrideWithValue((_, _) {
          final client = _Client();
          clients.add(client);
          return client;
        }),
      ],
    );
  });
  tearDown(() => container.dispose());

  test(
    'failed analysis cannot spill into a greeting; retry resends only the failed request',
    () async {
      final a = container.read(aiProvider('note-a').notifier);
      a.send('Ferrari analysis');
      clients.last.response.done!();
      expect(container.read(aiProvider('note-a')).items.first.failed, isTrue);
      a.retryLast();
      expect(
        container
            .read(aiProvider('note-a'))
            .items
            .where((i) => i.role == ChatRole.user),
        hasLength(1),
      );
      expect(
        clients.last.messages
            .where((m) => m.role == ChatRole.user)
            .single
            .content,
        'Ferrari analysis',
      );
      clients.last.response.done!();
      await a.flush();
      container.invalidate(aiProvider('note-a'));
      final restored = container.read(aiProvider('note-a').notifier);
      restored.send('Hello');
      expect(
        clients.last.messages
            .where((m) => m.role == ChatRole.user)
            .map((m) => m.content),
        ['Hello'],
      );
      clients.last.response.data!('Hello back');
      clients.last.response.done!();
      restored.send('How are you?');
      expect(
        clients.last.messages
            .where((m) => m.role == ChatRole.user)
            .map((m) => m.content),
        ['Hello', 'How are you?'],
      );
      restored.stop();
    },
  );

  test('regenerate replaces the last reply and resends its question', () {
    final a = container.read(aiProvider('note-a').notifier);
    a.send('Hello');
    clients.last.response.data!('First answer');
    clients.last.response.done!();
    a.send('Name a colour');
    clients.last.response.data!('Blue');
    clients.last.response.done!();
    a.retryLast();
    final state = container.read(aiProvider('note-a'));
    expect(
      state.items.where((i) => i.role == ChatRole.user).map((i) => i.text),
      ['Hello', 'Name a colour'],
    );
    expect(state.items.any((i) => i.text == 'Blue'), isFalse);
    expect(
      clients.last.messages
          .where((m) => m.role != ChatRole.system)
          .map((m) => m.content),
      ['Hello', 'First answer', 'Name a colour'],
    );
    clients.last.response.data!('Green');
    clients.last.response.done!();
    expect(container.read(aiProvider('note-a')).items.last.text, 'Green');
  });

  test(
    'empty completion reports an error instead of leaving a thinking placeholder',
    () async {
      final a = container.read(aiProvider('note-a').notifier);
      a.send('Question');
      expect(container.read(aiProvider('note-a')).busy, isTrue);
      a.send('Duplicate');
      expect(clients, hasLength(1));
      clients.last.response.done!();
      final completed = container.read(aiProvider('note-a'));
      expect(completed.busy, isFalse);
      expect(completed.items.last.isError, isTrue);
      expect(
        completed.items.where(
          (i) => i.role == ChatRole.assistant && i.text.trim().isEmpty,
        ),
        isEmpty,
      );
      await a.flush();
      container.invalidate(aiProvider('note-a'));
      expect(container.read(aiProvider('note-a')).items.last.isError, isTrue);
    },
  );

  test(
    'stop before first token removes pending placeholder also after reload',
    () async {
      final a = container.read(aiProvider('note-a').notifier);
      a.send('Question');
      a.stop();
      expect(container.read(aiProvider('note-a')).busy, isFalse);
      expect(container.read(aiProvider('note-a')).items, hasLength(1));
      await a.flush();
      container.invalidate(aiProvider('note-a'));
      expect(container.read(aiProvider('note-a')).items, hasLength(1));
      expect(
        container.read(aiProvider('note-a')).items.single.role,
        ChatRole.user,
      );
    },
  );

  test(
    'per-chat model, effort and attachments persist and remain in follow-up context',
    () async {
      final a = container.read(aiProvider('note-a').notifier);
      const support = AiModel(
        id: 'vision-model',
        images: true,
        efforts: ['high'],
      );
      a.configure(model: support.id, effort: 'high');
      final file = AiAttachment.fromBytes(
        'image.png',
        Uint8List.fromList([1, 2, 3]),
      );
      a.send('Look', attachments: [file], capabilities: support);
      expect(clients.last.reasoningEffort, 'high');
      clients.last.response.data!('Answer');
      clients.last.response.done!();
      await a.flush();
      container.invalidate(aiProvider('note-a'));
      final restored = container.read(aiProvider('note-a'));
      expect(restored.active.model, support.id);
      expect(restored.active.effort, 'high');
      expect(restored.items.first.attachments.single.data, file.data);
      container
          .read(aiProvider('note-a').notifier)
          .send('Follow-up', capabilities: support);
      expect(
        clients.last.messages
            .firstWhere((m) => m.role == ChatRole.user)
            .attachments
            .single
            .data,
        file.data,
      );
      clients.last.response.done!();
      final notifier = container.read(aiProvider('note-a').notifier);
      notifier.configure(model: 'text-model');
      expect(() => notifier.send('Unsupported'), throwsA(isA<AiException>()));
      expect(container.read(aiProvider('note-a')).busy, isFalse);
      notifier.deleteChat();
      expect(container.read(aiProvider('note-a')).items, isEmpty);
      expect(container.read(aiProvider('note-a')).conversations, hasLength(1));
    },
  );

  test(
    'each note has isolated chats and multiple conversations survive reload',
    () async {
      final a = container.read(aiProvider('note-a').notifier);
      a.send('A first conversation');
      clients.last.response.data!('A answer');
      clients.last.response.done!();
      final firstChat = container.read(aiProvider('note-a')).activeId!;
      expect(container.read(aiProvider('note-b')).items, isEmpty);
      a.newChat();
      expect(container.read(aiProvider('note-a')).items, isEmpty);
      a.send('A second conversation');
      clients.last.response.data!('Second answer');
      clients.last.response.done!();
      expect(container.read(aiProvider('note-a')).conversations, hasLength(2));
      a.selectChat(firstChat);
      expect(container.read(aiProvider('note-a')).items.last.text, 'A answer');
      await a.flush();
      container.invalidate(aiProvider('note-a'));
      expect(container.read(aiProvider('note-a')).conversations, hasLength(2));
      expect(container.read(aiProvider('note-a')).items.last.text, 'A answer');
      expect(container.read(aiProvider('note-b')).items, isEmpty);
    },
  );

  test(
    'changing conversations stops the old stream and ignores late callbacks',
    () {
      final a = container.read(aiProvider('note-a').notifier);
      a.send('Old');
      final old = clients.last;
      a.newChat();
      a.send('New');
      old.response.data!('late answer');
      old.response.done!();
      expect(old.closed, isTrue);
      expect(container.read(aiProvider('note-a')).busy, isTrue);
      expect(container.read(aiProvider('note-a')).items.last.text, isEmpty);
      clients.last.response.data!('new answer');
      clients.last.response.done!();
    },
  );

  test('send stays locked before first token and throughout the response', () {
    final notifier = container.read(aiProvider('note-a').notifier);
    notifier.send('First');
    notifier.send('Duplicate');
    expect(clients, hasLength(1));
    expect(container.read(aiProvider('note-a')).busy, isTrue);
    clients.single.response.data!('Partial ');
    notifier.send('Still blocked');
    expect(clients, hasLength(1));
    expect(container.read(aiProvider('note-a')).busy, isTrue);
    clients.single.response.data!('answer');
    clients.single.response.done!();
    expect(container.read(aiProvider('note-a')).busy, isFalse);
    expect(
      container.read(aiProvider('note-a')).items.last.text,
      'Partial answer',
    );
  });

  test('stopped request cannot append tokens or unlock a newer response', () {
    final notifier = container.read(aiProvider('note-a').notifier);
    notifier.send('First');
    final old = clients.single;
    notifier.stop();
    expect(old.closed, isTrue);
    notifier.send('Second');
    old.response.data!('stale');
    old.response.done!();
    expect(container.read(aiProvider('note-a')).busy, isTrue);
    expect(container.read(aiProvider('note-a')).items.last.text, isEmpty);
    notifier.send('Duplicate');
    expect(clients, hasLength(2));
    clients.last.response.data!('new answer');
    clients.last.response.done!();
    expect(container.read(aiProvider('note-a')).items.last.text, 'new answer');
    expect(container.read(aiProvider('note-a')).busy, isFalse);
  });

  test('late completion after an error does not finish the next request', () {
    final notifier = container.read(aiProvider('note-a').notifier);
    notifier.send('First');
    final old = clients.single;
    Function.apply(old.response.error!, [StateError('network failed')]);
    expect(old.response.cancelOnError, isTrue);
    expect(container.read(aiProvider('note-a')).busy, isFalse);
    expect(container.read(aiProvider('note-a')).items.last.isError, isTrue);
    notifier.send('Retry');
    old.response.done!();
    expect(container.read(aiProvider('note-a')).busy, isTrue);
    expect(clients, hasLength(2));
  });
}
