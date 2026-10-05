import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/note.dart';
import '../domain/languages.dart';
import 'providers.dart';
import 'ui_providers.dart';

/// Creates a note that inherits the current navigation context (notebook,
/// tag or status the user is browsing) and opens it.
Note createNoteInContext(
  ProviderContainer c, {
  NoteKind kind = NoteKind.markdown,
  String? language,
}) {
  final nav = c.read(navFilterProvider);
  final lib = c.read(libraryProvider.notifier);
  final lang = Languages.find(language);

  final note = lib.createNote(
    kind: kind,
    language: kind == NoteKind.code ? (lang?.id ?? 'python') : null,
    notebookId: nav.kind == NavKind.notebook ? nav.id : null,
    tagIds: nav.kind == NavKind.tag && nav.id != null ? [nav.id!] : const [],
    status: nav.kind == NavKind.status
        ? (nav.status ?? NoteStatus.none)
        : NoteStatus.none,
    title: kind == NoteKind.code ? 'untitled.${lang?.extension ?? 'py'}' : '',
    body: kind == NoteKind.code ? (lang?.sample ?? '') : '',
  );

  // A new note should be visible in the list that is currently shown.
  if (nav.kind == NavKind.trash) {
    c.read(navFilterProvider.notifier).select(const NavFilter.all());
  }
  c.read(searchTextProvider.notifier).set('');
  c.read(openNoteProvider.notifier).open(note.id);
  return note;
}
