import 'package:flutter/widgets.dart' show FocusNode;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_settings.dart';
import '../data/models/note.dart';
import '../domain/search_query.dart';

import 'providers.dart';
import 'library_notifier.dart';
import 'note_vault.dart';
import 'persistence_coordinator.dart';

String? _activeNoteId(Ref ref) =>
    ref.exists(openNoteProvider) ? ref.read(activeEditorNoteIdProvider) : null;

// ------------------------------------------------------------ simple toggles

class ToggleNotifier extends Notifier<bool> {
  ToggleNotifier(this._initial);
  final bool _initial;

  @override
  bool build() => _initial;

  void set(bool value) => state = value;
  void toggle() => state = !state;
}

NotifierProvider<ToggleNotifier, bool> _toggle(bool initial) =>
    NotifierProvider<ToggleNotifier, bool>(() => ToggleNotifier(initial));

/// Sidebar visible in the wide layout.
final sidebarVisibleProvider = _toggle(true);

class NoteListVisibilityNotifier extends ToggleNotifier {
  NoteListVisibilityNotifier() : super(true);
  @override
  void set(bool value) {
    if (value && ref.read(aiPanelVisibleProvider)) {
      ref.read(aiPanelVisibleProvider.notifier).set(false);
    }
    if (value && ref.exists(openNoteProvider)) {
      final open = ref.read(openNoteProvider);
      for (final id in {open.current, open.secondaryId}.whereType<String>()) {
        ref.read(noteUiProvider(id).notifier).ai(false);
      }
    }
    super.set(value);
  }

  @override
  void toggle() => set(!state);
}

final noteListVisibleProvider =
    NotifierProvider<NoteListVisibilityNotifier, bool>(
      NoteListVisibilityNotifier.new,
    );

/// Focus mode hides the sidebar and note list.
final focusModeProvider = _toggle(false);

class OutlineVisibilityNotifier extends ToggleNotifier {
  OutlineVisibilityNotifier() : super(false);
  @override
  void set(bool value) {
    super.set(value);
    final id = _activeNoteId(ref);
    if (id != null) ref.read(noteUiProvider(id).notifier).outline(value);
  }

  @override
  void toggle() {
    final id = _activeNoteId(ref);
    set(!(id == null ? state : ref.read(noteUiProvider(id)).outline));
  }
}

final outlineVisibleProvider =
    NotifierProvider<OutlineVisibilityNotifier, bool>(
      OutlineVisibilityNotifier.new,
    );

class AiPanelVisibilityNotifier extends ToggleNotifier {
  AiPanelVisibilityNotifier() : super(false);

  @override
  void set(bool value) {
    if (value) ref.read(noteListVisibleProvider.notifier).set(false);
    super.set(value);
    final id = _activeNoteId(ref);
    if (id != null) ref.read(noteUiProvider(id).notifier).ai(value);
  }

  @override
  void toggle() {
    final id = _activeNoteId(ref);
    set(!(id == null ? state : ref.read(noteUiProvider(id)).ai));
  }
}

final aiPanelVisibleProvider =
    NotifierProvider<AiPanelVisibilityNotifier, bool>(
      AiPanelVisibilityNotifier.new,
    );
final notesOverviewProvider = _toggle(true);
final editorSearchProvider = _toggle(false);
final editorReplaceProvider = _toggle(false);

class AiPanelWidthNotifier extends Notifier<double> {
  @override
  double build() =>
      (ref.read(sharedPrefsProvider).getDouble('ai_panel_width_v1') ?? 360)
          .clamp(320.0, 640.0);
  void set(double value) => state = value.clamp(320.0, 640.0);
  void persist() {
    final prefs = ref.read(sharedPrefsProvider);
    final width = state;
    ref.read(persistenceProvider).write('ai-panel-width', () async {
      if (!await prefs.setDouble('ai_panel_width_v1', width)) {
        throw StateError('Could not save panel width');
      }
    });
  }
}

final aiPanelWidthProvider = NotifierProvider<AiPanelWidthNotifier, double>(
  AiPanelWidthNotifier.new,
);

/// Focus node of the note-list filter field (Ctrl+F focuses it).
final filterFocusProvider = Provider<FocusNode>((ref) {
  final node = FocusNode(debugLabel: 'note-filter');
  ref.onDispose(node.dispose);
  return node;
});

class ViewModeNotifier extends Notifier<ViewMode> {
  @override
  ViewMode build() => ref.read(settingsProvider).defaultViewMode;
  void set(ViewMode mode) {
    state = mode;
    final id = _activeNoteId(ref);
    if (id != null) ref.read(noteUiProvider(id).notifier).mode(mode);
  }
}

final viewModeProvider = NotifierProvider<ViewModeNotifier, ViewMode>(
  ViewModeNotifier.new,
);

// ---------------------------------------------------- note-specific editor UI
class EditorFocusNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String id) {
    if (state != id) state = id;
  }
}

final editorFocusProvider = NotifierProvider<EditorFocusNotifier, String?>(
  EditorFocusNotifier.new,
);
final activeEditorNoteIdProvider = Provider<String?>((ref) {
  final opened = ref.watch(openNoteProvider);
  final focused = ref.watch(editorFocusProvider);
  return focused != null &&
          (focused == opened.current || focused == opened.secondaryId)
      ? focused
      : opened.current;
});

class NoteUiState {
  const NoteUiState({
    required this.mode,
    this.ai = false,
    this.outline = false,
    this.search = false,
    this.replace = false,
    this.aiWidth = 360,
  });
  final ViewMode mode;
  final bool ai, outline, search, replace;
  final double aiWidth;
  NoteUiState copyWith({
    ViewMode? mode,
    bool? ai,
    bool? outline,
    bool? search,
    bool? replace,
    double? aiWidth,
  }) => NoteUiState(
    mode: mode ?? this.mode,
    ai: ai ?? this.ai,
    outline: outline ?? this.outline,
    search: search ?? this.search,
    replace: replace ?? this.replace,
    aiWidth: aiWidth ?? this.aiWidth,
  );
}

class NoteUiNotifier extends Notifier<NoteUiState> {
  NoteUiNotifier(this.noteId);
  final String noteId;
  @override
  NoteUiState build() => NoteUiState(
    mode: ref.read(viewModeProvider),
    aiWidth: ref.read(aiPanelWidthProvider),
  );
  void mode(ViewMode value) => state = state.copyWith(mode: value);
  void ai(bool value) {
    if (value) ref.read(noteListVisibleProvider.notifier).set(false);
    state = state.copyWith(ai: value);
  }

  void toggleAi() => ai(!state.ai);
  void outline(bool value) => state = state.copyWith(outline: value);
  void toggleOutline() => outline(!state.outline);
  void search(bool value, {bool? replace}) =>
      state = state.copyWith(search: value, replace: replace);
  void aiWidth(double value) =>
      state = state.copyWith(aiWidth: value.clamp(320, 640));
  void persistWidth() {
    final sizing = ref.read(aiPanelWidthProvider.notifier);
    sizing.set(state.aiWidth);
    sizing.persist();
  }
}

final noteUiProvider =
    NotifierProvider.family<NoteUiNotifier, NoteUiState, String>(
      NoteUiNotifier.new,
    );

// ------------------------------------------------------------------ nav filter

enum NavKind { all, trash, notebook, status, tag, recent, starred }

class NavFilter {
  const NavFilter(this.kind, {this.id, this.status});
  const NavFilter.all() : this(NavKind.all);
  const NavFilter.trash() : this(NavKind.trash);
  const NavFilter.notebook(String id) : this(NavKind.notebook, id: id);
  const NavFilter.tag(String id) : this(NavKind.tag, id: id);
  const NavFilter.status(NoteStatus s) : this(NavKind.status, status: s);
  const NavFilter.recent() : this(NavKind.recent);
  const NavFilter.starred() : this(NavKind.starred);

  final NavKind kind;
  final String? id;
  final NoteStatus? status;

  @override
  bool operator ==(Object other) =>
      other is NavFilter &&
      other.kind == kind &&
      other.id == id &&
      other.status == status;

  @override
  int get hashCode => Object.hash(kind, id, status);
}

class NavFilterNotifier extends Notifier<NavFilter> {
  @override
  NavFilter build() => const NavFilter.all();
  void select(NavFilter f) => state = f;
}

final navFilterProvider = NotifierProvider<NavFilterNotifier, NavFilter>(
  NavFilterNotifier.new,
);

class SearchTextNotifier extends Notifier<String> {
  Timer? _timer;
  @override
  String build() {
    ref.onDispose(() => _timer?.cancel());
    return '';
  }

  void set(String v) {
    _timer?.cancel();
    state = v;
  }

  void debounce(String v) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 180), () => state = v);
  }

  bool get pending => _timer?.isActive ?? false;
}

final searchTextProvider = NotifierProvider<SearchTextNotifier, String>(
  SearchTextNotifier.new,
);

/// Title for the note-list header.
final navTitleProvider = Provider<String>((ref) {
  final nav = ref.watch(navFilterProvider);
  final lib = ref.watch(libraryProvider);
  return switch (nav.kind) {
    NavKind.all => 'All Notes',
    NavKind.trash => 'Trash',
    NavKind.notebook => lib.notebook(nav.id)?.name ?? 'Notebook',
    NavKind.status => nav.status!.label,
    NavKind.tag => '#${tagPathOf(lib, nav.id!) ?? 'tag'}',
    NavKind.recent => 'Recently opened',
    NavKind.starred => 'Starred',
  };
});

// ------------------------------------------------------------ visible notes

/// Tag filters use a tag id, or `path:<name>` for a parent in the tag tree
/// that is not a tag itself (e.g. "work" when only "work/x" exists).
String? tagPathOf(Library lib, String id) =>
    id.startsWith('path:') ? id.substring(5) : lib.tag(id)?.name;

/// The parsed note-list search, shared by the list and its highlighting.
final searchQueryProvider = Provider<SearchQuery>(
  (ref) => SearchQuery.parse(ref.watch(searchTextProvider)),
);

/// Words to highlight in [note] for the current search (empty when none).
final searchHighlightProvider = Provider.family<Set<String>, Note>((ref, note) {
  final query = ref.watch(searchQueryProvider);
  return query.hasTerms ? query.highlightWords(note) : const {};
});

final visibleNotesProvider = Provider<List<Note>>((ref) {
  final lib = ref.watch(libraryProvider);
  final nav = ref.watch(navFilterProvider);
  final sort = ref.watch(
    settingsProvider.select((s) => (s.sortField, s.sortAscending)),
  );
  final recent = nav.kind == NavKind.recent
      ? ref.watch(recentNotesProvider)
      : const <String>[];

  Set<String>? notebookScope;
  if (nav.kind == NavKind.notebook && nav.id != null) {
    notebookScope = lib.descendantIds(nav.id!);
  }
  // A tag shows its sub-tags too: "work" includes "work/client".
  Set<String>? tagScope;
  if (nav.kind == NavKind.tag && nav.id != null) {
    final path = tagPathOf(lib, nav.id!)?.toLowerCase();
    tagScope = {
      for (final t in lib.tags)
        if (path != null &&
            (t.name.toLowerCase() == path ||
                t.name.toLowerCase().startsWith('$path/')))
          t.id,
    };
  }

  bool inScope(Note n) => switch (nav.kind) {
    NavKind.all => !n.trashed,
    NavKind.trash => n.trashed,
    NavKind.notebook =>
      !n.trashed &&
          n.notebookId != null &&
          notebookScope!.contains(n.notebookId),
    NavKind.status => !n.trashed && n.status == nav.status,
    NavKind.tag => !n.trashed && n.tagIds.any(tagScope!.contains),
    NavKind.recent => !n.trashed && recent.contains(n.id),
    NavKind.starred => !n.trashed && n.starred,
  };

  final query = ref.watch(searchQueryProvider);
  final scored = <(Note, int)>[];
  for (final n in lib.notes.values) {
    if (!inScope(n)) continue;
    if (query.isEmpty) {
      scored.add((n, 0));
      continue;
    }
    final score = query.match(
      n,
      tagNames: [for (final id in n.tagIds) lib.tag(id)?.name ?? ''],
      notebookName: lib.notebook(n.notebookId)?.name,
    );
    if (score >= 0) scored.add((n, score));
  }

  int compare((Note, int) a, (Note, int) b) {
    final x = a.$1;
    final y = b.$1;
    // A text search ranks by relevance; pinning only breaks ties.
    if (query.hasTerms && a.$2 != b.$2) return b.$2.compareTo(a.$2);
    if (nav.kind == NavKind.recent) {
      return recent.indexOf(x.id).compareTo(recent.indexOf(y.id));
    }
    if (nav.kind != NavKind.trash && x.pinned != y.pinned) {
      return x.pinned ? -1 : 1;
    }
    final int c = switch (sort.$1) {
      SortField.updated => x.updatedAt.compareTo(y.updatedAt),
      SortField.created => x.createdAt.compareTo(y.createdAt),
      SortField.title => x.displayTitle.toLowerCase().compareTo(
        y.displayTitle.toLowerCase(),
      ),
    };
    return sort.$2 ? c : -c;
  }

  scored.sort(compare);
  return [for (final e in scored) e.$1];
});

// ------------------------------------------------------------ recent notes

/// Most recently opened notes, newest first; persisted across launches.
class RecentNotesNotifier extends Notifier<List<String>> {
  static const _key = 'recent_notes_v1';
  static const limit = 30;

  @override
  List<String> build() =>
      ref.read(sharedPrefsProvider).getStringList(_key) ?? const [];

  void touch(String id) {
    if (state.isNotEmpty && state.first == id) return;
    state = [id, ...state.where((e) => e != id)].take(limit).toList();
    final snapshot = state;
    final prefs = ref.read(sharedPrefsProvider);
    ref
        .read(persistenceProvider)
        .write('recent-notes', () => prefs.setStringList(_key, snapshot));
  }

  void clear() {
    state = const [];
    final prefs = ref.read(sharedPrefsProvider);
    ref
        .read(persistenceProvider)
        .write('recent-notes', () => prefs.remove(_key));
  }
}

final recentNotesProvider = NotifierProvider<RecentNotesNotifier, List<String>>(
  RecentNotesNotifier.new,
);

// ---------------------------------------------------------------- counts

class SidebarCounts {
  const SidebarCounts({
    required this.all,
    required this.trash,
    required this.notebooks,
    required this.statuses,
    required this.tags,
  });

  final int all;
  final int trash;
  final Map<String, int> notebooks;
  final Map<NoteStatus, int> statuses;
  final Map<String, int> tags;
}

final sidebarCountsProvider = Provider<SidebarCounts>((ref) {
  ref.watch(
    libraryProvider.select(
      (lib) => _SidebarInputs(lib.notebooks, [
        for (final n in lib.notes.values)
          (n.id, n.notebookId, n.status, n.trashed, n.tagIds),
      ]),
    ),
  );
  final lib = ref.read(libraryProvider);
  var all = 0;
  var trash = 0;
  final direct = <String, int>{};
  final statuses = <NoteStatus, int>{};
  final tags = <String, int>{};

  for (final n in lib.notes.values) {
    if (n.trashed) {
      trash++;
      continue;
    }
    all++;
    if (n.notebookId != null) {
      direct[n.notebookId!] = (direct[n.notebookId!] ?? 0) + 1;
    }
    if (n.status != NoteStatus.none) {
      statuses[n.status] = (statuses[n.status] ?? 0) + 1;
    }
    for (final t in n.tagIds) {
      tags[t] = (tags[t] ?? 0) + 1;
    }
  }

  final notebooks = <String, int>{
    for (final nb in lib.notebooks)
      nb.id: lib
          .descendantIds(nb.id)
          .fold<int>(0, (sum, id) => sum + (direct[id] ?? 0)),
  };

  return SidebarCounts(
    all: all,
    trash: trash,
    notebooks: notebooks,
    statuses: statuses,
    tags: tags,
  );
});

class _SidebarInputs {
  const _SidebarInputs(this.notebooks, this.notes);
  final Object notebooks;
  final List<(String, String?, NoteStatus, bool, List<String>)> notes;
  @override
  bool operator ==(Object other) =>
      other is _SidebarInputs &&
      identical(notebooks, other.notebooks) &&
      listEquals(notes, other.notes);
  @override
  int get hashCode => Object.hash(notebooks, Object.hashAll(notes));
}

// ------------------------------------------------------------- open note

class OpenNoteState {
  const OpenNoteState(
    this.history,
    this.index, {
    this.tabs = const [],
    this.secondaryId,
  });
  final List<String> history, tabs;
  final int index;
  final String? secondaryId;
  String? get current =>
      index >= 0 && index < history.length ? history[index] : null;
  bool get canBack => index > 0;
  bool get canForward => index >= 0 && index < history.length - 1;
}

class OpenNoteNotifier extends Notifier<OpenNoteState> {
  @override
  OpenNoteState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final lib = ref.read(libraryProvider);
    final tabs = (prefs.getStringList('note_tabs_v1') ?? [])
        .where((id) => lib.notes.containsKey(id))
        .toList();
    final active = prefs.getString('note_tab_active_v1');
    final id = tabs.contains(active) ? active : tabs.lastOrNull;
    return OpenNoteState(
      id == null ? [] : [id],
      id == null ? -1 : 0,
      tabs: tabs,
    );
  }

  void _persist() {
    final prefs = ref.read(sharedPrefsProvider);
    final tabs = List<String>.of(state.tabs), id = state.current;
    ref.read(persistenceProvider).write('note-tabs', () async {
      await prefs.setStringList('note_tabs_v1', tabs);
      if (id != null) {
        await prefs.setString('note_tab_active_v1', id);
      } else {
        await prefs.remove('note_tab_active_v1');
      }
    });
  }

  void open(String id) {
    ref.read(notesOverviewProvider.notifier).set(false);
    ref.read(recentNotesProvider.notifier).touch(id);
    if (state.current == id) return;
    var history = [...state.history.take(state.index + 1), id];
    if (history.length > 100) history = history.sublist(history.length - 100);
    state = OpenNoteState(
      history,
      history.length - 1,
      tabs: state.tabs.contains(id) ? state.tabs : [...state.tabs, id],
      secondaryId: state.secondaryId == id ? null : state.secondaryId,
    );
    _persist();
  }

  void split(String? id) {
    state = OpenNoteState(
      state.history,
      state.index,
      tabs: state.tabs,
      secondaryId: id == state.current ? null : id,
    );
  }

  void closeTab(String id) {
    final tabs = state.tabs.where((t) => t != id).toList();
    final current = state.current == id ? tabs.lastOrNull : state.current;
    state = OpenNoteState(
      current == null ? [] : [current],
      current == null ? -1 : 0,
      tabs: tabs,
      secondaryId: state.secondaryId == id ? null : state.secondaryId,
    );
    _persist();
  }

  /// Moves tab [id] to position [to] in the tab strip.
  void moveTab(String id, int to) {
    final tabs = [...state.tabs];
    final from = tabs.indexOf(id);
    if (from < 0) return;
    tabs.removeAt(from);
    tabs.insert(to.clamp(0, tabs.length), id);
    state = OpenNoteState(
      state.history,
      state.index,
      tabs: tabs,
      secondaryId: state.secondaryId,
    );
    _persist();
  }

  /// Activates the next (or previous) tab, wrapping around.
  void cycleTab(int delta) {
    final notes = ref.read(libraryProvider).notes;
    final tabs = state.tabs.where(notes.containsKey).toList();
    if (tabs.length < 2) return;
    final at = tabs.indexOf(state.current ?? '');
    open(tabs[((at < 0 ? 0 : at) + delta) % tabs.length]);
  }

  /// Activates the tab at [index] (0-based); the last tab for index >= 8.
  void openTabAt(int index) {
    final notes = ref.read(libraryProvider).notes;
    final tabs = state.tabs.where(notes.containsKey).toList();
    if (tabs.isEmpty) return;
    open(index >= 8 ? tabs.last : tabs[index.clamp(0, tabs.length - 1)]);
  }

  void back() => _step(-1);
  void forward() => _step(1);
  void _step(int dir) {
    final notes = ref.read(libraryProvider).notes;
    var i = state.index + dir;
    while (i >= 0 &&
        i < state.history.length &&
        !notes.containsKey(state.history[i])) {
      i += dir;
    }
    if (i < 0 || i >= state.history.length) return;
    final id = state.history[i];
    state = OpenNoteState(
      state.history,
      i,
      tabs: state.tabs.contains(id) ? state.tabs : [...state.tabs, id],
      secondaryId: state.secondaryId == id ? null : state.secondaryId,
    );
    ref.read(notesOverviewProvider.notifier).set(false);
    ref.read(recentNotesProvider.notifier).touch(id);
    _persist();
  }

  void close() {
    state = const OpenNoteState([], -1);
    _persist();
  }
}

final openNoteProvider = NotifierProvider<OpenNoteNotifier, OpenNoteState>(
  OpenNoteNotifier.new,
);

final openNoteIdProvider = Provider<String?>(
  (ref) => ref.watch(openNoteProvider.select((s) => s.current)),
);

/// A single note by id. Rebuilds only when that note changes. An unlocked
/// locked note includes its decrypted content (held only in memory).
final noteProvider = Provider.family<Note?, String>((ref, id) {
  final note = ref.watch(libraryProvider.select((l) => l.notes[id]));
  if (note == null || !note.isLocked) return note;
  final content = ref.watch(noteVaultProvider.select((v) => v[id]?.content));
  return content == null
      ? note
      : note.copyWith(
          body: content.body,
          images: content.images,
          attachments: content.attachments,
        );
});

/// Ids of notes whose editor holds edits that are not saved yet.
class UnsavedNotesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Deferred so editors may report from build or dispose.
  void mark(String id, bool unsaved) => Future.microtask(() {
    if (!ref.mounted || state.contains(id) == unsaved) return;
    state = unsaved ? {...state, id} : ({...state}..remove(id));
  });
}

final unsavedNotesProvider =
    NotifierProvider<UnsavedNotesNotifier, Set<String>>(
      UnsavedNotesNotifier.new,
    );

/// Bumped when an open editor must drop its unsaved text and show the
/// library version (e.g. the user chose the copy changed on disk).
class NoteReloadNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void reload(String id) => state = {...state, id: (state[id] ?? 0) + 1};
}

final noteReloadProvider =
    NotifierProvider<NoteReloadNotifier, Map<String, int>>(
      NoteReloadNotifier.new,
    );
