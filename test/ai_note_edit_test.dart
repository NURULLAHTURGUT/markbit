import 'dart:async';
import 'dart:convert';
import 'package:markbit/application/ai_notifier.dart';
import 'package:markbit/application/providers.dart';
import 'package:markbit/domain/ai/ai_client.dart';
import 'package:markbit/domain/ai/ai_note_edit.dart';
import 'package:markbit/features/ai/ai_panel.dart';
import 'package:markbit/core/theme/app_palette.dart';
import 'package:markbit/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:markbit/app/app.dart';
import 'package:markbit/application/ui_providers.dart';
import 'package:markbit/data/models/note.dart';
import 'package:markbit/data/models/library_models.dart';
import 'package:markbit/data/repository/library_repository.dart';

const tasks =
    '- [ ] Task one\n- [ ] Task two\n- [ ] Task three\n- [ ] Task four\n- [ ] Task five';
String proposal({String operation = 'append', String content = tasks}) =>
    'Here is the proposed change.\n```markbit-edit\n${jsonEncode({'operation': operation, 'content': content, 'summary': 'Create five checkable tasks.'})}\n```';

class _Response extends Stream<String> {
  void Function(String)? data;
  void Function()? done;
  @override
  StreamSubscription<String> listen(
    void Function(String)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    data = onData;
    done = onDone;
    return const Stream<String>.empty().listen((_) {});
  }
}

class _Client extends AiClient {
  _Client() : super(baseUrl: 'http://test', model: 'test');
  final response = _Response();
  List<ChatMessage> messages = [];
  @override
  Stream<String> streamChat(List<ChatMessage> messages) {
    this.messages = messages;
    return response;
  }

  @override
  void close() {}
}

class _Repository implements LibraryRepository {
  final saved = <String, Note>{};
  @override
  String get location => 'memory';
  @override
  Future<void> saveNote(Note note) async {
    saved[note.id] = note;
  }

  @override
  Future<void> deleteNote(String id) async {
    saved.remove(id);
  }

  @override
  Future<void> saveMeta({
    required List<Notebook> notebooks,
    required List<Tag> tags,
    required List<NoteTemplate> templates,
  }) async {}
  @override
  Future<LibrarySnapshot> load() async => LibrarySnapshot(
    notes: saved.values.toList(),
    notebooks: [],
    tags: [],
    templates: [],
    isFresh: false,
  );
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
        aiModelsProvider.overrideWith((ref) async => []),
        aiClientFactoryProvider.overrideWithValue((_, _) {
          final c = _Client();
          clients.add(c);
          return c;
        }),
      ],
    );
  });
  tearDown(() => container.dispose());

  String patch(List<Map<String, String>> edits) => jsonEncode({
    'operation': 'patch',
    'edits': edits,
    'summary': 'Update the target',
  });
  test(
    'targeted patches preserve a long note and persist without the full body',
    () {
      final body =
          '${List.filled(5000, 'Unchanged text.').join('\n')}\nUnique target\nFooter';
      final result = parseAiNoteEdit(
        patch([
          {'before': 'Unique target', 'after': 'New target'},
        ]),
        body,
      )!.edit;
      expect(
        result.applyTo(body),
        body.replaceFirst('Unique target', 'New target'),
      );
      expect(jsonEncode(result.toJson()).length, lessThan(400));
      expect(
        AiNoteEdit.fromJson(result.toJson())!.applyTo(body),
        result.applyTo(body),
      );
      expect(
        result.withStatus(AiEditStatus.applied).edits.single.after,
        'New target',
      );
    },
  );
  test(
    'patches reject ambiguous, missing and overlapping targets; deletion and independent changes work',
    () {
      expect(
        parseAiNoteEdit(
          patch([
            {'before': 'x', 'after': 'y'},
          ]),
          'x x',
        ),
        isNull,
      );
      expect(
        parseAiNoteEdit(
          patch([
            {'before': 'missing', 'after': 'y'},
          ]),
          'x',
        ),
        isNull,
      );
      expect(
        parseAiNoteEdit(
          patch([
            {'before': 'abc', 'after': 'y'},
            {'before': 'bc', 'after': 'z'},
          ]),
          'abc',
        ),
        isNull,
      );
      final edit = parseAiNoteEdit(
        patch([
          {'before': 'second', 'after': ''},
          {'before': 'first', 'after': 'long replacement'},
        ]),
        'first + second',
      )!.edit;
      expect(edit.applyTo('first + second'), 'long replacement + ');
      expect(edit.matches('first + changed'), isFalse);
      expect(() => edit.applyTo('changed'), throwsStateError);
    },
  );
  test(
    'patch proposal never writes before approval, then updates only its target',
    () async {
      final ai = container.read(aiProvider('patch-note').notifier);
      var body = 'Header\nTarget\nFooter';
      ai.send('Change Target', noteBody: body, noteContext: body);
      expect(
        clients.single.messages.any(
          (m) => m.content.contains('Never use replace for a partial change'),
        ),
        isTrue,
      );
      clients.single.response.data!(
        patch([
          {'before': 'Target', 'after': 'Updated'},
        ]),
      );
      clients.single.response.done!();
      expect(body, 'Header\nTarget\nFooter');
      expect(
        ai.applyNoteEdit(1, body, (expected, updated) {
          body = updated;
          return true;
        }),
        isTrue,
      );
      expect(body, 'Header\nUpdated\nFooter');
    },
  );
  test(
    'validated edit preserves content and creates five actual task boxes',
    () {
      final result = parseAiNoteEdit(proposal(), 'Original')!;
      expect(
        parseAiNoteEdit(
          proposal(operation: 'replace'),
          'Original',
          allowReplace: false,
        ),
        isNull,
      );
      expect(result.edit.taskCount, 5);
      expect(result.edit.applyTo('Original'), 'Original\n\n$tasks');
      expect(result.edit.matches('Changed'), isFalse);
      expect(result.prose, 'Here is the proposed change.');
      expect(AiNoteEdit.fromJson(result.edit.toJson())!.content, tasks);
      expect(
        parseAiNoteEdit(
          proposal(operation: 'replace', content: 'New full body'),
          'Old',
        )!.edit.applyTo('Old'),
        'New full body',
      );
    },
  );

  test(
    'provider JSON fences including screenshot response become approval requests',
    () {
      final screenshot = proposal(
        content:
            '- [ ] Örnek görev 1\n- [ ] Örnek görev 2\n- [ ] Örnek görev 3\n- [ ] Örnek görev 4\n- [ ] Örnek görev 5',
      ).replaceFirst('```markbit-edit', '```json');
      final edit = parseAiNoteEdit(screenshot, '')!.edit;
      expect(edit.taskCount, 5);
      expect(edit.status, AiEditStatus.pending);
      expect(edit.content, startsWith('- [ ] Örnek görev 1\n'));
      expect(
        parseAiNoteEdit(
          screenshot.replaceAll('\n', '\r\n'),
          '',
        )!.edit.taskCount,
        5,
      );
      expect(
        parseAiNoteEdit(
          screenshot.replaceFirst('```json', '```JSON'),
          '',
        )!.edit.taskCount,
        5,
      );
      expect(
        parseAiNoteEdit(
          screenshot.replaceFirst('```json', '```'),
          '',
        )!.edit.taskCount,
        5,
      );
      expect(
        parseAiNoteEdit(
          jsonEncode({
            'operation': 'append',
            'content': tasks,
            'summary': 'Tasks',
          }),
          '',
        )!.edit.taskCount,
        5,
      );
      expect(parseAiNoteEdit('```json\n{"data": "example"}\n```', ''), isNull);
      expect(
        parseAiNoteEdit(
          '```json\n{"operation":"append","content":"x","summary":"x","target":"other-note"}\n```',
          '',
        ),
        isNull,
      );
      expect(parseAiNoteEdit('$screenshot\n$screenshot', ''), isNull);
    },
  );

  test(
    'invalid, incomplete, empty and multiple edit actions never become proposals',
    () {
      expect(parseAiNoteEdit(proposal(operation: 'delete'), ''), isNull);
      expect(parseAiNoteEdit(proposal(content: ''), ''), isNull);
      expect(parseAiNoteEdit('${proposal()}\n${proposal()}', ''), isNull);
      expect(
        parseAiNoteEdit('```markbit-edit\n{"operation":"append"}', ''),
        isNull,
      );
      expect(parseAiNoteEdit('Normal answer', ''), isNull);
    },
  );

  test(
    'stream cannot write; approval applies once, persists and reports real status to follow-up',
    () async {
      final ai = container.read(aiProvider('note').notifier);
      ai.send('Write five tasks', noteBody: 'Original');
      expect(
        clients.single.messages.any(
          (m) => m.content.contains('cannot apply anything yourself'),
        ),
        isTrue,
      );
      clients.single.response.data!(proposal());
      expect(container.read(aiProvider('note')).items.last.edit, isNull);
      clients.single.response.done!();
      var body = 'Original';
      var writes = 0;
      expect(
        container.read(aiProvider('note')).items.last.edit!.status,
        AiEditStatus.pending,
      );
      bool apply(String expected, String updated) {
        expect(expected, body);
        body = updated;
        writes++;
        return true;
      }

      expect(ai.applyNoteEdit(1, body, apply), isTrue);
      expect(body, 'Original\n\n$tasks');
      expect(ai.applyNoteEdit(1, body, apply), isFalse);
      expect(writes, 1);
      await ai.flush();
      container.invalidate(aiProvider('note'));
      final restored = container.read(aiProvider('note'));
      expect(restored.items.last.edit!.status, AiEditStatus.applied);
      container
          .read(aiProvider('note').notifier)
          .send('What did you do?', noteBody: body);
      expect(
        clients.last.messages.any(
          (m) => m.content.contains('Note edit status: applied'),
        ),
        isTrue,
      );
      container.read(aiProvider('note').notifier).stop();
    },
  );

  test('decline, changed note and failed target never overwrite content', () {
    final ai = container.read(aiProvider('note').notifier);
    void complete() {
      ai.send('Write tasks', noteBody: 'Original');
      clients.last.response.data!(proposal());
      clients.last.response.done!();
    }

    complete();
    ai.declineNoteEdit(1);
    expect(
      ai.applyNoteEdit(
        1,
        'Original',
        (_, _) => throw StateError('must not run'),
      ),
      isFalse,
    );
    complete();
    expect(
      ai.applyNoteEdit(
        3,
        'User changes',
        (_, _) => throw StateError('must not run'),
      ),
      isFalse,
    );
    expect(
      container.read(aiProvider('note')).items[3].edit!.status,
      AiEditStatus.stale,
    );
    complete();
    expect(ai.applyNoteEdit(5, 'Original', (_, _) => false), isFalse);
    expect(
      container.read(aiProvider('note')).items[5].edit!.status,
      AiEditStatus.stale,
    );
  });

  test(
    'stopped generation never enables approval, even after delayed completion',
    () {
      final ai = container.read(aiProvider('note').notifier);
      ai.send('Write tasks', noteBody: 'Original');
      clients.single.response.data!(proposal());
      ai.stop();
      clients.single.response.done!();
      expect(container.read(aiProvider('note')).items.last.edit, isNull);
    },
  );

  testWidgets(
    'note is unchanged until explicit review confirmation; applied card explains result',
    (tester) async {
      String body = 'Original';
      var writes = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.build(Palettes.zenGlass),
            home: Scaffold(
              body: Align(
                alignment: Alignment.centerRight,
                child: AiPanel(
                  noteId: 'note',
                  noteContext: () => body,
                  noteBody: () => body,
                  onInsert: (_) =>
                      throw StateError('manual insert must not run'),
                  onClose: () {},
                  onApplyEdit: (expected, updated) {
                    expect(expected, body);
                    body = updated;
                    writes++;
                    return true;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-input')),
        'Write five tasks',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      clients.single.response.data!(
        proposal().replaceFirst('```markbit-edit', '```json'),
      );
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Review and apply'), findsNothing);
      clients.single.response.done!();
      await tester.pumpAndSettle();
      expect(body, 'Original');
      expect(find.text('Approval required'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('ai-review-edit')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('ai-review-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-review-edit')));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsNWidgets(5));
      expect(body, 'Original');
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(body, 'Original');
      await tester.ensureVisible(find.byKey(const ValueKey('ai-review-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-review-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve and write to note'));
      await tester.pumpAndSettle();
      expect(body, 'Original\n\n$tasks');
      expect(writes, 1);
      expect(find.text('Note updated'), findsOneWidget);
      expect(
        find.text('5 checkable tasks written to the editor.'),
        findsOneWidget,
      );
      expect(find.text('Review and apply'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'approval writes through the real editor and task boxes update the persisted note',
    (tester) async {
      tester.view.physicalSize = const Size(1500, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final prefs = await SharedPreferences.getInstance();
      final repository = _Repository();
      final client = _Client();
      final app = ProviderContainer(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          libraryRepositoryProvider.overrideWithValue(repository),
          aiModelsProvider.overrideWith((ref) async => []),
          aiClientFactoryProvider.overrideWithValue((_, _) => client),
          initialLibraryProvider.overrideWithValue(
            LibrarySnapshot(
              notes: [
                Note(
                  id: 'integration',
                  title: 'Tasks',
                  body: 'Original',
                  notebookId: 'inbox',
                  createdAt: DateTime(2026),
                  updatedAt: DateTime(2026),
                ),
              ],
              notebooks: const [
                Notebook(id: 'inbox', name: 'General', isInbox: true),
              ],
              tags: [],
              templates: [],
              isFresh: false,
            ),
          ),
        ],
      );
      app.read(openNoteProvider.notifier).open('integration');
      app.read(notesOverviewProvider.notifier).set(false);
      app.read(aiPanelVisibleProvider.notifier).set(true);
      await tester.pumpWidget(
        UncontrolledProviderScope(container: app, child: const MarkbitApp()),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('ai-input')),
        'Write five tasks',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      client.response.data!(
        proposal().replaceFirst('```markbit-edit', '```json'),
      );
      client.response.done!();
      await tester.pumpAndSettle();
      expect(app.read(noteProvider('integration'))!.body, 'Original');
      await tester.ensureVisible(find.byKey(const ValueKey('ai-review-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ai-review-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve and write to note'));
      await tester.pumpAndSettle();
      expect(app.read(noteProvider('integration'))!.body, 'Original\n\n$tasks');
      expect(repository.saved['integration']!.body, 'Original\n\n$tasks');
      expect(find.byType(Checkbox), findsNWidgets(5));
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(
        app.read(noteProvider('integration'))!.body,
        contains('- [x] Task one'),
      );
      expect(repository.saved['integration']!.body, contains('- [x] Task one'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );
}
