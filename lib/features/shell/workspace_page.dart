import 'dart:async';

import '../dialogs/task_dashboard.dart';
import '../../core/l10n/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/actions.dart';
import '../../application/providers.dart';
import '../../application/shortcuts.dart';
import '../../application/persistence_coordinator.dart';
import '../../application/ui_providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../core/widgets/resize_handle.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/note.dart';
import '../command_palette/command_palette.dart';
import '../editor/note_editor.dart';
import '../notelist/note_list_pane.dart';
import '../notelist/notes_overview.dart';
import '../settings/settings_dialog.dart';
import '../sidebar/sidebar.dart';
import 'library_host.dart';
import '../../core/widgets/motion.dart';

/// Root screen. Adapts between a three-pane desktop layout, a two-pane
/// tablet layout (sidebar in a drawer) and a single-pane phone layout.
class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key});

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends ConsumerState<WorkspacePage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late double _sidebarW;
  late double _listW;
  bool _editorRouteOpen = false;
  final _scope = FocusScopeNode(debugLabel: 'workspace');

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _sidebarW = s.sidebarWidth;
    _listW = s.listWidth;
    FocusManager.instance.addListener(_keepShortcutFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_keepShortcutFocus);
    _scope.dispose();
    super.dispose();
  }

  /// Keeps keyboard focus at or below [_scope] while this page is on top,
  /// so the app shortcuts above it always receive key events — also after
  /// focus was dropped entirely or moved to the route's own scope.
  void _keepShortcutFocus() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null && !_scope.ancestors.contains(primary)) return;
    scheduleMicrotask(() {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      final now = FocusManager.instance.primaryFocus;
      if (now == null || _scope.ancestors.contains(now)) {
        _scope.requestFocus();
      }
    });
  }

  Map<ShortcutActivator, VoidCallback> _bindings() {
    final container = ProviderScope.containerOf(context);
    final keys = ref.watch(shortcutsProvider);
    void Function() view(ViewMode m) =>
        () => ref.read(viewModeProvider.notifier).set(m);
    // Rebindable actions (Settings -> Keyboard shortcuts); editor-only
    // ones are handled by the editor itself.
    final actions = <AppShortcut, VoidCallback>{
      AppShortcut.newNote: _newNote,
      AppShortcut.newCodeNote: () => createNoteInContext(
        container,
        kind: NoteKind.code,
        language: 'python',
      ),
      AppShortcut.commandPalette: () => showCommandPalette(context),
      AppShortcut.quickOpen: () => showCommandPalette(context),
      AppShortcut.findNotes: () => _find(false),
      AppShortcut.replace: () => _find(true),
      AppShortcut.toggleSidebar: () =>
          ref.read(sidebarVisibleProvider.notifier).toggle(),
      AppShortcut.focusMode: () =>
          ref.read(focusModeProvider.notifier).toggle(),
      AppShortcut.aiAssistant: () =>
          ref.read(aiPanelVisibleProvider.notifier).toggle(),
      AppShortcut.settings: () => showSettingsDialog(context),
      AppShortcut.viewEditor: view(ViewMode.edit),
      AppShortcut.viewSplit: view(ViewMode.split),
      AppShortcut.viewPreview: view(ViewMode.preview),
      AppShortcut.previousNote: () =>
          ref.read(openNoteProvider.notifier).back(),
      AppShortcut.nextNote: () => ref.read(openNoteProvider.notifier).forward(),
      AppShortcut.nextTab: () => _cycleTab(1),
      AppShortcut.previousTab: () => _cycleTab(-1),
      AppShortcut.closeTab: _closeTab,
    };
    // Steps of 10%; null resets to 100%.
    void zoom(double? delta) => ref
        .read(settingsProvider.notifier)
        .update(
          (s) => s.copyWith(
            uiScale: delta == null
                ? 1
                : (((s.uiScale + delta) * 10).round() / 10).clamp(.8, 1.5),
          ),
        );
    return {
      // Interface zoom (fixed; by character so it works on any layout).
      const CharacterActivator('+', control: true): () => zoom(.1),
      const CharacterActivator('=', control: true): () => zoom(.1),
      const CharacterActivator('-', control: true): () => zoom(-.1),
      const SingleActivator(LogicalKeyboardKey.numpadAdd, control: true): () =>
          zoom(.1),
      const SingleActivator(
        LogicalKeyboardKey.numpadSubtract,
        control: true,
      ): () =>
          zoom(-.1),
      const SingleActivator(LogicalKeyboardKey.digit0, control: true): () =>
          zoom(null),
      // Alt+1..9 jump to a tab (fixed).
      for (final (i, key) in const [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ].indexed)
        SingleActivator(key, alt: true): () => _openTab(i),
      for (final e in actions.entries) keys[e.key]!.activator: e.value,
      const SingleActivator(LogicalKeyboardKey.escape): () {
        if (ref.read(focusModeProvider)) {
          ref.read(focusModeProvider.notifier).set(false);
        }
      },
    };
  }

  void _cycleTab(int delta) {
    ref.read(persistenceProvider).flushEditors();
    ref.read(openNoteProvider.notifier).cycleTab(delta);
  }

  void _openTab(int index) {
    ref.read(persistenceProvider).flushEditors();
    ref.read(openNoteProvider.notifier).openTabAt(index);
  }

  void _closeTab() {
    final id = ref.read(openNoteIdProvider);
    if (id == null) return;
    ref.read(persistenceProvider).flushEditors();
    ref.read(openNoteProvider.notifier).closeTab(id);
  }

  void _newNote() {
    createNoteInContext(ProviderScope.containerOf(context));
    if (MediaQuery.sizeOf(context).width < Breakpoints.compact) {
      _openEditorRoute();
    }
  }

  void _find(bool replace) {
    if (ref.read(openNoteIdProvider) == null ||
        ref.read(notesOverviewProvider)) {
      ref.read(filterFocusProvider).requestFocus();
      return;
    }
    final id = ref.read(activeEditorNoteIdProvider);
    if (id == null) return;
    final editor = ref.read(noteUiProvider(id).notifier);
    editor.ai(false);
    editor.mode(ViewMode.edit);
    editor.search(true, replace: replace);
  }

  void _persistWidths() {
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(sidebarWidth: _sidebarW, listWidth: _listW));
  }

  Future<void> _openEditorRoute() async {
    if (_editorRouteOpen) return;
    _editorRouteOpen = true;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const _MobileEditorPage()));
    _editorRouteOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return CallbackShortcuts(
      bindings: _bindings(),
      // A scope (not a plain Focus) so that when a text field gives up focus
      // — clicking outside it, closing a note — focus falls back here, below
      // the shortcuts, instead of to the route's scope above them. Otherwise
      // app shortcuts would only work while an editor has focus.
      child: FocusScope(
        node: _scope,
        autofocus: true,
        child: LibraryHost(
          child: TaskReminderHost(
            child: LayoutBuilder(
              builder: (context, cons) {
                final w = cons.maxWidth;
                if (w < Breakpoints.compact) return _buildCompact(context);

                final focus = ref.watch(focusModeProvider);
                final overview = ref.watch(notesOverviewProvider);
                final noteListVisible = ref.watch(noteListVisibleProvider);
                final sidebarVisible = ref.watch(sidebarVisibleProvider);
                final inline = w >= Breakpoints.medium;
                final showSidebar = inline && sidebarVisible && !focus;

                return Scaffold(
                  key: _scaffoldKey,
                  backgroundColor: p.isGlass ? Colors.transparent : p.editorBg,
                  drawer: inline
                      ? null
                      : Drawer(
                          width: 300,
                          backgroundColor: p.sidebarBg,
                          child: Sidebar(
                            onNavigate: () => Navigator.of(context).maybePop(),
                          ),
                        ),
                  body: Row(
                    children: [
                      _Collapsible(
                        visible: showSidebar,
                        width: _sidebarW,
                        child: Sidebar(),
                      ),
                      if (showSidebar)
                        ResizeHandle(
                          onDrag: (dx) => setState(
                            () => _sidebarW = (_sidebarW + dx).clamp(
                              200.0,
                              360.0,
                            ),
                          ),
                          onEnd: _persistWidths,
                        ),
                      if (!overview)
                        _Collapsible(
                          visible: !focus && noteListVisible,
                          width: _listW,
                          child: NoteListPane(
                            showSidebarToggle: true,
                            onToggleSidebar: inline
                                ? () => ref
                                      .read(sidebarVisibleProvider.notifier)
                                      .toggle()
                                : () => _scaffoldKey.currentState?.openDrawer(),
                          ),
                        ),
                      if (!focus && !overview && noteListVisible)
                        ResizeHandle(
                          onDrag: (dx) => setState(
                            () => _listW = (_listW + dx).clamp(260.0, 520.0),
                          ),
                          onEnd: _persistWidths,
                        ),
                      Expanded(
                        child: FadeIn(
                          key: ValueKey(overview),
                          offset: const Offset(0, .008),
                          child: overview
                              ? NotesOverview(
                                  onNavigation: inline
                                      ? () => ref
                                            .read(
                                              sidebarVisibleProvider.notifier,
                                            )
                                            .toggle()
                                      : () => _scaffoldKey.currentState
                                            ?.openDrawer(),
                                )
                              : const EditorPane(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: p.isGlass ? Colors.transparent : p.listBg,
      drawer: Drawer(
        width: 300,
        backgroundColor: p.sidebarBg,
        child: Sidebar(onNavigate: () => Navigator.of(context).maybePop()),
      ),
      body: ref.watch(notesOverviewProvider)
          ? NotesOverview(
              onNavigation: () => _scaffoldKey.currentState?.openDrawer(),
              onOpen: _openEditorRoute,
            )
          : NoteListPane(
              leading: AppIconButton(
                icon: Icons.menu_rounded,
                tooltip: context.tr('Open navigation'),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              onOpen: _openEditorRoute,
            ),
    );
  }
}

/// Animated show/hide of a fixed-width pane without re-laying out its child.
class _Collapsible extends StatelessWidget {
  const _Collapsible({
    required this.visible,
    required this.width,
    required this.child,
  });
  final bool visible;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.normal,
      curve: Motion.curve,
      width: visible ? width : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: ExcludeFocus(
        excluding: !visible,
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: width,
          maxWidth: width,
          child: child,
        ),
      ),
    );
  }
}

class _MobileEditorPage extends ConsumerWidget {
  const _MobileEditorPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(openNoteIdProvider, (prev, next) {
      if (next == null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return Scaffold(
      backgroundColor: context.palette.isGlass
          ? Colors.transparent
          : context.palette.editorBg,
      body: const SafeArea(child: EditorPane(mobile: true)),
    );
  }
}
