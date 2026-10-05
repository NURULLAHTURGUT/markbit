import '../dialogs/note_picker.dart';
import '../../application/persistence_coordinator.dart';
import '../../core/l10n/app_strings.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;

import '../../application/ai_notifier.dart';
import '../../application/providers.dart';
import '../../application/runner_notifier.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../core/widgets/cover_image.dart';
import '../../domain/ai/ai_client.dart';
import '../../domain/ai/ai_attachment.dart';
import '../../domain/ai/ai_model.dart';
import '../../domain/ai/ai_visuals.dart';
import '../../domain/ai/ai_note_edit.dart';
import '../../domain/markdown_utils.dart';
import '../dialogs/dialogs.dart';
import '../editor/preview/code_block_view.dart';
import '../editor/preview/visual_block_view.dart';
import '../settings/settings_dialog.dart';

/// Chat with any OpenAI-compatible model about the current note.
class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({
    super.key,
    required this.noteContext,
    required this.noteId,
    required this.onInsert,
    required this.onClose,
    this.width = 360,
    this.onToggleWidth,
    this.expanded = false,
    this.noteBody,
    this.onApplyEdit,
    this.noteTitle = '',
  });

  final String Function() noteContext;
  final String noteId;
  final void Function(String text) onInsert;
  final VoidCallback onClose;
  final double width;
  final VoidCallback? onToggleWidth;
  final bool expanded;
  final String Function()? noteBody;
  final bool Function(String expected, String updated)? onApplyEdit;

  /// Shown on the composer's context chip (what the assistant can see).
  final String noteTitle;

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _showLatest = ValueNotifier<bool>(false);
  bool _followTail = true, _tailScheduled = false, _scrollingToTail = false;
  final _bubbleCache =
      <
        AiChatItem,
        ({
          bool streaming,
          bool approve,
          bool retry,
          bool regenerate,
          Widget child,
        })
      >{};
  void _scrollChanged() {
    if (!mounted || !_scroll.hasClients) return;
    if (!_scrollingToTail) _followTail = _scroll.position.extentAfter <= 48;
    _updateLatestButton();
  }

  void _updateLatestButton() {
    if (mounted && _scroll.hasClients) {
      _showLatest.value = _scroll.position.extentAfter > 80;
    }
  }

  Future<void> _jumpToLatest() async {
    if (!_scroll.hasClients) return;
    _followTail = true;
    _scrollingToTail = true;
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        await _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _scrollingToTail = false;
      if (mounted) _updateLatestButton();
    }
  }

  List<Widget> _messages(AiState state) {
    final result = <Widget>[];
    final present = state.items.toSet();
    _bubbleCache.removeWhere((item, _) => !present.contains(item));
    for (var i = 0; i < state.items.length; i++) {
      final item = state.items[i];
      final streaming = state.busy && i == state.items.length - 1;
      final approve = !state.busy && widget.onApplyEdit != null;
      final last = i == state.items.length - 1;
      final retry = !state.busy && last && item.isError;
      final regenerate =
          !state.busy &&
          last &&
          item.role == ChatRole.assistant &&
          !item.isError &&
          item.edit == null;
      var cached = _bubbleCache[item];
      if (cached == null ||
          cached.streaming != streaming ||
          cached.approve != approve ||
          cached.retry != retry ||
          cached.regenerate != regenerate) {
        final index = i;
        cached = (
          streaming: streaming,
          approve: approve,
          retry: retry,
          regenerate: regenerate,
          child: _Bubble(
            item: item,
            noteId: widget.noteId,
            streaming: streaming,
            canApprove: approve,
            onRetry: retry ? _retryLast : null,
            onRegenerate: regenerate ? _retryLast : null,
            onInsert: widget.onInsert,
            onApprove: () => _approveEdit(index),
            onDecline: () => ref
                .read(aiProvider(widget.noteId).notifier)
                .declineNoteEdit(index),
          ),
        );
        _bubbleCache[item] = cached;
      }
      result.add(
        Padding(
          padding: EdgeInsets.only(
            bottom: i == state.items.length - 1 ? 0 : Sp.lg,
          ),
          child: RepaintBoundary(child: cached.child),
        ),
      );
    }
    return result;
  }

  final _focus = FocusNode();
  final Set<String> _sourceIds = {};
  String _contextWithSources() {
    ref.read(persistenceProvider).flushEditors();
    return widget.noteContext();
  }

  String? _references() {
    if (_sourceIds.isEmpty) return null;
    final lib = ref.read(libraryProvider);
    final out = StringBuffer();
    var remaining = 20000;
    for (final id in _sourceIds) {
      final n = lib.notes[id];
      if (n == null || n.trashed || remaining <= 200) continue;
      final heading = '\n[READ-ONLY SOURCE] ${n.displayTitle} (ID: ${n.id})\n';
      remaining -= heading.length;
      final body = n.body.length > remaining
          ? n.body.substring(0, remaining)
          : n.body;
      out.write('$heading$body');
      remaining -= body.length;
    }
    return out.toString();
  }

  Future<void> _pickSources() async {
    final ids = await pickNotes(
      context,
      selected: _sourceIds.toList(),
      exclude: widget.noteId,
    );
    if (ids != null && mounted) {
      setState(() {
        _sourceIds
          ..clear()
          ..addAll(ids);
      });
    }
  }

  bool _picking = false;
  final List<AiAttachment> _attachments = [];
  String? _draftChatId;
  bool _restoringDraft = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_saveDraft);
    _scroll.addListener(_scrollChanged);
  }

  void _saveDraft() {
    if (_restoringDraft || !mounted || _draftChatId == null) return;
    final state = ref.read(aiProvider(widget.noteId));
    if (state.activeId != _draftChatId) return;
    ref
        .read(aiProvider(widget.noteId).notifier)
        .saveDraft(_input.text, _attachments);
  }

  void _restoreDraft() {
    final state = ref.read(aiProvider(widget.noteId));
    if (_draftChatId == state.activeId) return;
    _restoringDraft = true;
    _sourceIds.clear();
    _draftChatId = state.activeId;
    _bubbleCache.clear();
    _followTail = true;
    _toBottom();
    final draft = state.active.draft;
    _input.text = draft?.text ?? '';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _attachments
      ..clear()
      ..addAll(draft?.attachments ?? []);
    _restoringDraft = false;
  }

  AiModel _modelInfo() {
    final settings = ref.read(settingsProvider);
    final id = ref
        .read(aiProvider(widget.noteId))
        .active
        .effectiveModel(settings);
    final models = ref.read(aiModelsProvider).asData?.value ?? <AiModel>[];
    return models.firstWhere(
      (m) => m.id == id,
      orElse: () => AiModel.fallback(id, settings.aiBaseUrl),
    );
  }

  void _newChat() {
    ref.read(aiProvider(widget.noteId).notifier).newChat();
    _restoreDraft();
    setState(() {});
  }

  Future<void> _pickFiles() async {
    final support = _modelInfo();
    final chatId = ref.read(aiProvider(widget.noteId)).activeId;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'txt',
          'md',
          'csv',
          'json',
          'xml',
          'yaml',
          'log',
          if (support.images) ...['png', 'jpg', 'jpeg', 'webp'],
          if (support.pdf) 'pdf',
        ],
      );
      if (result == null ||
          !mounted ||
          ref.read(aiProvider(widget.noteId)).activeId != chatId) {
        return;
      }
      final added = <AiAttachment>[];
      var total = _attachments.fold(0, (sum, a) => sum + a.size);
      for (final file in result.files) {
        total += file.size;
        if (_attachments.length + added.length >= 4 ||
            total > 8 * 1024 * 1024) {
          throw const FormatException('Attach up to 4 files, 8 MB in total.');
        }
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        added.add(AiAttachment.fromBytes(file.name, bytes));
      }
      if (mounted && ref.read(aiProvider(widget.noteId)).activeId == chatId) {
        setState(() => _attachments.addAll(added));
        _saveDraft();
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          e is FormatException
              ? context.tr(e.message)
              : context.tr('Could not open the attachment.'),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _chooseModel() async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _ModelPicker(current: _modelInfo().id),
    );
    if (chosen == null ||
        !mounted ||
        ref.read(aiProvider(widget.noteId)).busy) {
      return;
    }
    ref.read(aiProvider(widget.noteId).notifier).configure(model: chosen);
    setState(() {});
  }

  static const _quick = <(String, String, IconData)>[
    (
      'Explain',
      'Explain this note clearly and briefly.',
      Icons.lightbulb_outline_rounded,
    ),
    (
      'Find bugs',
      'Review the code in this note and point out bugs or risky parts.',
      Icons.bug_report_outlined,
    ),
    (
      'Improve',
      'Suggest improvements to the code or writing in this note.',
      Icons.auto_fix_high_outlined,
    ),
    (
      'Write tests',
      'Write unit tests for the code in this note.',
      Icons.science_outlined,
    ),
    (
      'Summarize',
      'Summarize this note in a few bullet points.',
      Icons.short_text_rounded,
    ),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.removeListener(_scrollChanged);
    _scroll.dispose();
    _showLatest.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _approveEdit(int index) async {
    final before = ref.read(aiProvider(widget.noteId));
    final edit = before.items[index].edit!;
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => _EditApprovalDialog(edit: edit),
    );
    if (!mounted || approved != true) return;
    final current = ref.read(aiProvider(widget.noteId));
    if (current.activeId != before.activeId ||
        index >= current.items.length ||
        !identical(current.items[index].edit, edit)) {
      return;
    }
    final apply = widget.onApplyEdit;
    final body = widget.noteBody;
    if (apply == null || body == null) return;
    ref
        .read(aiProvider(widget.noteId).notifier)
        .applyNoteEdit(index, body(), apply);
  }

  void _retryLast() {
    try {
      ref
          .read(aiProvider(widget.noteId).notifier)
          .retryLast(
            noteContext: _contextWithSources(),
            referenceContext: _references(),
            noteBody: widget.onApplyEdit == null
                ? null
                : widget.noteBody?.call(),
            capabilities: _modelInfo(),
          );
    } catch (e) {
      showToast(context, '$e');
    }
  }

  void _send([String? text]) {
    if (ref.read(aiProvider(widget.noteId)).busy) return;
    final value = (text ?? _input.text).trim();
    if (_picking || value.isEmpty && _attachments.isEmpty) return;
    try {
      ref
          .read(aiProvider(widget.noteId).notifier)
          .send(
            value,
            noteContext: _contextWithSources(),
            referenceContext: _references(),
            noteBody: widget.onApplyEdit == null
                ? null
                : widget.noteBody?.call(),
            attachments: List.of(_attachments),
            capabilities: _modelInfo(),
          );
    } catch (e) {
      showToast(context, '$e');
      return;
    }
    setState(() => _attachments.clear());
    _input.clear();
    _focus.requestFocus();
    _followTail = true;
    _toBottom();
  }

  void _toBottom() {
    if (_tailScheduled) return;
    _tailScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tailScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      if (_followTail && !_scroll.position.isScrollingNotifier.value) {
        _scrollingToTail = true;
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _scrollingToTail = false;
      }
      _updateLatestButton();
    });
  }

  Future<void> _conversationAction(String action) async {
    if (action == 'settings') {
      showSettingsDialog(context, initialTab: 2);
      return;
    }
    final ok = await confirmAction(
      context,
      title: context.tr(
        action == 'delete' ? 'Delete conversation?' : 'Clear conversation?',
      ),
      message: context.tr(
        'This removes the saved messages in this conversation.',
      ),
    );
    if (!ok || !mounted) return;
    final notifier = ref.read(aiProvider(widget.noteId).notifier);
    if (action == 'delete') {
      notifier.deleteChat();
      _restoreDraft();
    } else {
      notifier.clear();
      _attachments.clear();
      _input.clear();
      _saveDraft();
    }
    setState(() {});
  }

  void _selectChat(String id) {
    ref.read(aiProvider(widget.noteId).notifier).selectChat(id);
    _restoreDraft();
    setState(() {});
  }

  void _addAction(String action) {
    switch (action) {
      case 'files':
        _pickFiles();
      case 'sources':
        _pickSources();
      default:
        final quick = _quick.where((q) => q.$1 == action).firstOrNull;
        if (quick != null) _send(context.tr(quick.$2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = ref.watch(aiProvider(widget.noteId));
    _restoreDraft();
    final settings = ref.watch(settingsProvider);
    ref.watch(aiModelsProvider);
    final info = _modelInfo();
    final started = state.items.isNotEmpty;
    ref.listen(aiProvider(widget.noteId), (_, _) => _toBottom());
    final noteTitle = widget.noteTitle;

    final key = ref.read(settingsStoreProvider).aiApiKeyFor(settings.aiBaseUrl);
    final local =
        settings.aiBaseUrl.contains('localhost') ||
        settings.aiBaseUrl.contains('127.0.0.1');
    final needsSetup = key.isEmpty && !local;

    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: p.listBg,
        border: Border(left: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, state, started),
          Divider(height: 1, color: p.border),
          if (needsSetup)
            _SetupBanner(
              onOpen: () => showSettingsDialog(context, initialTab: 2),
            ),
          Expanded(
            child: state.items.isEmpty
                ? _Empty(quick: _quick, onPick: _send)
                : _messageList(context, state),
          ),
          _composer(context, state, info, noteTitle),
        ],
      ),
    );
  }

  /// Conversation switcher (title), new chat, size, options and close.
  Widget _header(BuildContext context, AiState state, bool started) {
    final p = context.palette;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.only(left: Sp.sm, right: Sp.xs),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: PopupMenuButton<String>(
                  key: const ValueKey('ai-conversations'),
                  tooltip: context.tr('Conversations'),
                  borderRadius: BorderRadius.circular(Rad.md),
                  position: PopupMenuPosition.under,
                  constraints: const BoxConstraints(
                    minWidth: 240,
                    maxWidth: 320,
                  ),
                  onSelected: (id) =>
                      id == '\u0000new' ? _newChat() : _selectChat(id),
                  itemBuilder: (_) => [
                    for (final chat in state.conversations.reversed)
                      PopupMenuItem(
                        value: chat.id,
                        height: 40,
                        child: _ConversationRow(
                          title: chat.title,
                          count: chat.id == state.activeId
                              ? state.items.length
                              : chat.items.length,
                          active: chat.id == state.activeId,
                        ),
                      ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: '\u0000new',
                      height: 40,
                      child: Row(
                        children: [
                          Icon(Icons.add_rounded, size: 18, color: p.accent),
                          const SizedBox(width: Sp.sm),
                          Text(
                            context.tr('New chat'),
                            style: TextStyle(color: p.accent),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Sp.sm,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 16,
                          color: p.accent,
                        ),
                        const SizedBox(width: Sp.sm),
                        Flexible(
                          child: Text(
                            started
                                ? state.active.title
                                : context.tr('AI assistant'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: p.text,
                              fontWeight: FontWeight.w700,
                              fontSize: Fs.label,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 18,
                          color: p.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            AppIconButton(
              icon: Icons.edit_square,
              size: 17,
              tooltip: context.tr('New chat'),
              onPressed: started ? _newChat : null,
            ),
            if (widget.onToggleWidth != null)
              AppIconButton(
                icon: widget.expanded
                    ? Icons.close_fullscreen_rounded
                    : Icons.open_in_full_rounded,
                size: 16,
                tooltip: context.tr(
                  widget.expanded ? 'Narrow assistant' : 'Expand assistant',
                ),
                onPressed: widget.onToggleWidth,
              ),
            PopupMenuButton<String>(
              borderRadius: BorderRadius.circular(Rad.md),
              tooltip: context.tr('Conversation options'),
              position: PopupMenuPosition.under,
              icon: Icon(
                Icons.more_horiz_rounded,
                color: p.textMuted,
                size: 18,
              ),
              onSelected: _conversationAction,
              itemBuilder: (_) => [
                _menuItem(
                  context,
                  'clear',
                  Icons.cleaning_services_outlined,
                  'Clear conversation',
                  enabled: started,
                ),
                _menuItem(
                  context,
                  'delete',
                  Icons.delete_outline_rounded,
                  'Delete conversation',
                  danger: true,
                ),
                const PopupMenuDivider(),
                _menuItem(
                  context,
                  'settings',
                  Icons.tune_rounded,
                  'AI settings',
                ),
              ],
            ),
            AppIconButton(
              icon: Icons.close_rounded,
              tooltip: context.tr('Close assistant'),
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageList(BuildContext context, AiState state) {
    final p = context.palette;
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (notification.depth == 0) _toBottom();
              return false;
            },
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: Scrollbar(
                controller: _scroll,
                notificationPredicate: (n) => n.depth == 0,
                child: SingleChildScrollView(
                  key: const ValueKey('ai-message-scroll'),
                  controller: _scroll,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 48),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _messages(state),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 8,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: _showLatest,
            builder: (context, show, _) => AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.normal,
              child: !show
                  ? const SizedBox.shrink()
                  : Center(
                      child: Material(
                        color: p.surface.withValues(alpha: 1),
                        elevation: 3,
                        shadowColor: Colors.black.withValues(alpha: 0.12),
                        shape: CircleBorder(side: BorderSide(color: p.border)),
                        child: IconButton(
                          key: const ValueKey('ai-jump-to-latest'),
                          tooltip: context.tr('Jump to latest message'),
                          onPressed: _jumpToLatest,
                          icon: Icon(
                            Icons.arrow_downward_rounded,
                            color: p.textMuted,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// Context chips, the text field and one toolbar row:
  /// add (files, notes, quick actions) · model · effort · send.
  Widget _composer(
    BuildContext context,
    AiState state,
    AiModel info,
    String noteTitle,
  ) {
    final p = context.palette;
    final busy = state.busy;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedBuilder(
            animation: _focus,
            builder: (context, _) => AnimatedContainer(
              key: const ValueKey('ai-composer'),
              duration: Motion.normal,
              decoration: BoxDecoration(
                color: p.editorBg,
                borderRadius: BorderRadius.circular(Rad.xl),
                border: Border.all(
                  color: _focus.hasFocus
                      ? p.accent.withValues(alpha: 0.6)
                      : p.border,
                  width: _focus.hasFocus ? 1.4 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: p.isDark ? .18 : .05),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.sm, Sp.sm, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 76),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          _ContextChip(
                            icon: Icons.edit_note_rounded,
                            label: noteTitle.isEmpty
                                ? context.tr('This note')
                                : noteTitle,
                            tooltip: context.tr(
                              'The assistant can see the note you are editing.',
                            ),
                            highlight: true,
                          ),
                          for (final id in _sourceIds)
                            _ContextChip(
                              icon: Icons.description_outlined,
                              label:
                                  ref
                                      .watch(libraryProvider)
                                      .notes[id]
                                      ?.displayTitle ??
                                  context.tr('Deleted note'),
                              tooltip: context.tr('Source note (read only)'),
                              onRemove: busy
                                  ? null
                                  : () => setState(() => _sourceIds.remove(id)),
                            ),
                          for (final file in _attachments)
                            _ContextChip(
                              icon: file.isImage
                                  ? Icons.image_outlined
                                  : Icons.attach_file_rounded,
                              label: file.name,
                              tooltip: file.name,
                              onRemove: busy
                                  ? null
                                  : () {
                                      setState(() => _attachments.remove(file));
                                      _saveDraft();
                                    },
                            ),
                        ],
                      ),
                    ),
                  ),
                  CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () =>
                          _send(),
                    },
                    child: TextField(
                      key: const ValueKey('ai-input'),
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 8,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(
                        color: p.text,
                        fontSize: Fs.body,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: context.tr('Ask about this note…'),
                        hintStyle: TextStyle(color: p.textFaint),
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(4, 10, 4, 10),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      PopupMenuButton<String>(
                        key: const ValueKey('ai-add'),
                        tooltip: context.tr('Add context'),
                        enabled: !busy && !_picking,
                        borderRadius: BorderRadius.circular(Rad.md),
                        position: PopupMenuPosition.over,
                        onSelected: _addAction,
                        itemBuilder: (_) => [
                          _menuItem(
                            context,
                            'files',
                            Icons.attach_file_rounded,
                            'Attach files',
                          ),
                          _menuItem(
                            context,
                            'sources',
                            Icons.library_books_outlined,
                            'Choose source notes',
                          ),
                          const PopupMenuDivider(),
                          for (final q in _quick)
                            _menuItem(context, q.$1, q.$3, q.$1),
                        ],
                        child: _ToolbarPill(
                          icon: Icons.add_rounded,
                          enabled: !busy && !_picking,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Tooltip(
                          message: context.tr('Choose model'),
                          child: InkWell(
                            key: const ValueKey('ai-model'),
                            borderRadius: BorderRadius.circular(Rad.pill),
                            onTap: busy ? null : _chooseModel,
                            child: _ToolbarPill(
                              icon: Icons.auto_awesome_outlined,
                              label: info.name,
                              trailing: true,
                              enabled: !busy,
                            ),
                          ),
                        ),
                      ),
                      if (info.efforts.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          borderRadius: BorderRadius.circular(Rad.md),
                          tooltip: context.tr('Reasoning effort'),
                          initialValue: state.active.effort,
                          enabled: !busy,
                          position: PopupMenuPosition.over,
                          constraints: const BoxConstraints(minWidth: 140),
                          onSelected: (effort) => ref
                              .read(aiProvider(widget.noteId).notifier)
                              .configure(effort: effort),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              enabled: false,
                              height: 30,
                              child: Text(
                                context.tr('Reasoning effort'),
                                style: TextStyle(
                                  color: p.textFaint,
                                  fontSize: Fs.caption,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            for (final e in ['', ...info.efforts])
                              CheckedPopupMenuItem(
                                value: e,
                                checked: state.active.effort == e,
                                child: Text(
                                  context.tr(e.isEmpty ? 'Automatic' : e),
                                ),
                              ),
                          ],
                          child: _ToolbarPill(
                            icon: Icons.psychology_outlined,
                            label: context.tr(
                              state.active.effort.isEmpty
                                  ? 'Auto'
                                  : state.active.effort,
                            ),
                            enabled: !busy,
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (busy)
                        IconButton.filled(
                          tooltip: context.tr('Stop'),
                          style: IconButton.styleFrom(
                            backgroundColor: p.text,
                            foregroundColor: p.editorBg,
                            minimumSize: const Size(32, 32),
                            maximumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                            shape: const CircleBorder(),
                          ),
                          onPressed: () => ref
                              .read(aiProvider(widget.noteId).notifier)
                              .stop(),
                          icon: const Icon(Icons.stop_rounded, size: 18),
                        )
                      else
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _input,
                          builder: (context, value, _) => IconButton.filled(
                            tooltip: context.tr('Send'),
                            style: IconButton.styleFrom(
                              backgroundColor: p.accent,
                              foregroundColor: p.onAccent,
                              disabledBackgroundColor: p.selection,
                              disabledForegroundColor: p.textFaint,
                              minimumSize: const Size(32, 32),
                              maximumSize: const Size(32, 32),
                              padding: EdgeInsets.zero,
                              shape: const CircleBorder(),
                            ),
                            onPressed:
                                _picking ||
                                    (value.text.trim().isEmpty &&
                                        _attachments.isEmpty)
                                ? null
                                : _send,
                            icon: const Icon(
                              Icons.arrow_upward_rounded,
                              size: 18,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.tr('Enter to send, Shift+Enter for a new line'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.textFaint, fontSize: Fs.micro),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    bool enabled = true,
    bool danger = false,
  }) {
    final p = context.palette;
    final color = danger ? p.danger : p.text;
    return PopupMenuItem(
      value: value,
      enabled: enabled,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 17, color: danger ? p.danger : p.textMuted),
          const SizedBox(width: Sp.md),
          Flexible(
            child: Text(
              context.tr(label),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: Fs.small),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.title,
    required this.count,
    required this.active,
  });
  final String title;
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Icon(
          active ? Icons.check_rounded : Icons.chat_bubble_outline_rounded,
          size: 16,
          color: active ? p.accent : p.textMuted,
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.text,
              fontSize: Fs.small,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (count > 0)
          Text(
            '${(count + 1) ~/ 2}',
            style: TextStyle(color: p.textFaint, fontSize: Fs.caption),
          ),
      ],
    );
  }
}

/// A small rounded control in the composer toolbar.
class _ToolbarPill extends StatelessWidget {
  const _ToolbarPill({
    required this.icon,
    this.label,
    this.trailing = false,
    this.enabled = true,
  });
  final IconData icon;
  final String? label;
  final bool trailing, enabled;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = enabled ? p.textMuted : p.textFaint;
    return Container(
      height: 30,
      padding: EdgeInsets.symmetric(horizontal: label == null ? 6 : 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: label == null ? color : p.accent),
          if (label != null) ...[
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? p.text : p.textFaint,
                  fontSize: Fs.caption,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (trailing) Icon(Icons.expand_more_rounded, size: 15, color: color),
        ],
      ),
    );
  }
}

/// What the next message will include: the note, source notes, files.
class _ContextChip extends StatelessWidget {
  const _ContextChip({
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onRemove,
    this.highlight = false,
  });
  final IconData icon;
  final String label, tooltip;
  final VoidCallback? onRemove;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 24,
        padding: EdgeInsets.only(left: 6, right: onRemove == null ? 8 : 2),
        decoration: BoxDecoration(
          color: highlight
              ? p.accent.withValues(alpha: p.isDark ? .14 : .08)
              : p.codeBg,
          borderRadius: BorderRadius.circular(Rad.sm),
          border: Border.all(
            color: highlight ? p.accent.withValues(alpha: .25) : p.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: highlight ? p.accent : p.textMuted),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.text, fontSize: Fs.caption),
              ),
            ),
            if (onRemove != null)
              InkWell(
                borderRadius: BorderRadius.circular(Rad.sm),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    Icons.close_rounded,
                    size: 13,
                    color: p.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.all(Sp.md),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: p.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: p.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.key_rounded, size: 18, color: p.warning),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              context.tr('Add an API key to use the assistant.'),
              style: TextStyle(color: p.text, fontSize: Fs.small),
            ),
          ),
          TextButton(onPressed: onOpen, child: Text(context.tr('Settings'))),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.quick, required this.onPick});
  final List<(String, String, IconData)> quick;
  final void Function(String prompt) onPick;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xl, Sp.lg, Sp.lg),
      children: [
        Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: p.isDark ? .16 : .10),
              borderRadius: BorderRadius.circular(Rad.lg),
            ),
            child: Icon(Icons.auto_awesome_rounded, size: 22, color: p.accent),
          ),
        ),
        const SizedBox(height: Sp.md),
        Text(
          context.tr('Ask anything about your note'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: p.text,
            fontSize: Fs.title,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: Sp.xs),
        Text(
          context.tr('The assistant can see the note you are editing.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: p.textMuted, fontSize: Fs.small),
        ),
        const SizedBox(height: Sp.xl),
        Padding(
          padding: const EdgeInsets.only(left: Sp.xs, bottom: Sp.sm),
          child: Text(
            context.tr('Quick actions'),
            style: TextStyle(
              color: p.textFaint,
              fontSize: Fs.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final q in quick)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: p.editorBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Rad.lg),
                side: BorderSide(color: p.border),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(Rad.lg),
                onTap: () => onPick(context.tr(q.$2)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Sp.md,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(q.$3, size: 18, color: p.accent),
                      const SizedBox(width: Sp.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr(q.$1),
                              style: TextStyle(
                                color: p.text,
                                fontSize: Fs.small,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              context.tr(q.$2),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.textMuted,
                                fontSize: Fs.caption,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: p.textFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({
    required this.item,
    required this.noteId,
    required this.streaming,
    required this.onInsert,
    required this.canApprove,
    required this.onApprove,
    required this.onDecline,
    this.onRetry,
    this.onRegenerate,
  });
  final VoidCallback? onRetry, onRegenerate;
  final bool canApprove;
  final VoidCallback onApprove, onDecline;
  final String noteId;
  final AiChatItem item;
  final bool streaming;
  final void Function(String text) onInsert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;

    if (item.role == ChatRole.user) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          margin: const EdgeInsets.only(left: Sp.xl),
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.md,
            vertical: Sp.sm,
          ),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: p.isDark ? .16 : .09),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(Rad.xl),
              topRight: Radius.circular(Rad.xl),
              bottomLeft: Radius.circular(Rad.xl),
              bottomRight: Radius.circular(Rad.xs),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.attachments.isNotEmpty) ...[
                for (final file in item.attachments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: file.isImage
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(Rad.md),
                            child: CoverImage(
                              data: file.data,
                              height: 110,
                              width: 240,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.description_outlined, size: 16),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  file.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                  ),
              ],
              SelectableText(
                item.text,
                style: TextStyle(color: p.text, fontSize: Fs.body),
              ),
            ],
          ),
        ),
      );
    }

    if (item.isError) {
      return Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: p.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Rad.md),
          border: Border.all(color: p.danger.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: p.danger),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: SelectableText(
                    item.text,
                    style: TextStyle(color: p.text, fontSize: Fs.small),
                  ),
                ),
              ],
            ),
            if (onRetry != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(context.tr('Retry this request')),
                ),
              ),
          ],
        ),
      );
    }

    if (item.text.isEmpty) {
      if (!streaming) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.xs),
        child: Row(
          children: [
            _TypingDots(color: p.accent),
            const SizedBox(width: Sp.sm),
            Text(
              context.tr('Thinking\u2026'),
              style: TextStyle(color: p.textMuted, fontSize: Fs.small),
            ),
          ],
        ),
      );
    }

    if (item.edit != null) {
      return _NoteEditCard(
        edit: item.edit!,
        canApprove: canApprove,
        onApprove: onApprove,
        onDecline: onDecline,
      );
    }
    // Incomplete/stopped responses never expose a runnable or insertable action.
    if (item.text.contains('```markbit-edit')) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          context.tr(
            streaming
                ? 'Preparing a note change…'
                : 'The note change was not completed. Ask the assistant to try again.',
          ),
          style: TextStyle(color: p.textMuted),
        ),
      );
    }

    final body = TextStyle(color: p.text, fontSize: Fs.label, height: 1.55);
    final sheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: body,
      code: AppTheme.mono(
        size: 12.5,
        color: p.synString,
        height: 1.4,
      ).copyWith(backgroundColor: p.codeBg),
      a: TextStyle(color: p.accent),
      h1: body.copyWith(fontSize: Fs.dialogTitle, fontWeight: FontWeight.w700),
      h2: body.copyWith(fontSize: 15.5, fontWeight: FontWeight.w700),
      h3: body.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700),
      listBullet: body,
      blockSpacing: 8,
    );

    final segments = splitSegments(item.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in segments)
                switch (s) {
                  TextSegment(:final text) when text.trim().isNotEmpty =>
                    MarkdownBody(
                      data: text,
                      styleSheet: sheet,
                      extensionSet: md.ExtensionSet.gitHubFlavored,
                    ),
                  TextSegment() => const SizedBox.shrink(),
                  CodeSegment(:final info, :final code)
                      when aiVisual(info, code) != null =>
                    VisualBlockView(source: aiVisual(info, code)!.json),
                  CodeSegment(:final info, :final code) => Stack(
                    children: [
                      CodeBlockView(
                        info: info,
                        code: code,
                        noteId: noteId,
                        onRun: (lang, c) => ref
                            .read(noteRunnerProvider(noteId).notifier)
                            .run(
                              languageName: lang,
                              code: c,
                              sourceLabel: context.tr('AI snippet'),
                            ),
                      ),
                    ],
                  ),
                },
            ],
          ),
        ),
        if (!streaming)
          Padding(
            padding: const EdgeInsets.only(top: Sp.xs),
            child: Wrap(
              spacing: 2,
              children: [
                _MessageAction(
                  icon: Icons.copy_rounded,
                  tooltip: context.tr('Copy'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: item.text));
                    showToast(context, context.tr('Copied'));
                  },
                ),
                _MessageAction(
                  icon: Icons.note_add_outlined,
                  label: context.tr('Insert into note'),
                  tooltip: context.tr('Insert into note'),
                  onTap: () => onInsert(prepareAiNote(item.text)),
                ),
                if (onRegenerate != null)
                  _MessageAction(
                    icon: Icons.refresh_rounded,
                    tooltip: context.tr('Regenerate'),
                    onTap: onRegenerate!,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.label,
  });
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final child = InkWell(
      borderRadius: BorderRadius.circular(Rad.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: p.textMuted),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(
                label!,
                style: TextStyle(color: p.textMuted, fontSize: Fs.caption),
              ),
            ],
          ],
        ),
      ),
    );
    return label == null ? Tooltip(message: tooltip, child: child) : child;
  }
}

/// Three pulsing dots while the reply has not started.
class _TypingDots extends StatefulWidget {
  const _TypingDots({required this.color});
  final Color color;

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _alpha(int i) {
    final phase = (_controller.value * 3 - i) % 3;
    return .3 + .7 * (1 - (phase - .5).abs() * 2).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color.withValues(alpha: _alpha(i)),
              ),
            ),
        ],
      ),
    );
  }
}

class _NoteEditCard extends StatelessWidget {
  const _NoteEditCard({
    required this.edit,
    required this.canApprove,
    required this.onApprove,
    required this.onDecline,
  });
  final AiNoteEdit edit;
  final bool canApprove;
  final VoidCallback onApprove, onDecline;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pending = edit.status == AiEditStatus.pending;
    final applied = edit.status == AiEditStatus.applied;
    final label = switch (edit.status) {
      AiEditStatus.pending => 'Approval required',
      AiEditStatus.applied => 'Note updated',
      AiEditStatus.declined => 'Change cancelled',
      AiEditStatus.stale => 'The note changed',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: .92),
        border: Border.all(color: p.accent.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(Rad.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                applied
                    ? Icons.check_circle_outline_rounded
                    : pending
                    ? Icons.edit_note_rounded
                    : Icons.info_outline_rounded,
                size: 20,
                color: p.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr(label),
                  style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(edit.summary, style: TextStyle(color: p.text, height: 1.45)),
          const SizedBox(height: 10),
          Text(
            context.tr(
              edit.operation == 'patch'
                  ? (applied
                        ? 'Selected passages updated'
                        : 'Update selected passages')
                  : applied
                  ? (edit.operation == 'append'
                        ? 'Added to the end of the note'
                        : 'Note content replaced')
                  : (edit.operation == 'append'
                        ? 'Add to the end of the note'
                        : 'Replace the note content'),
            ),
            style: TextStyle(color: p.textMuted, fontSize: Fs.small),
          ),
          if (pending) ...[
            const SizedBox(height: 10),
            Text(
              edit.preview,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 12, color: p.textMuted),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('Nothing will be written before your approval.'),
              style: TextStyle(color: p.textMuted, fontSize: Fs.small),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('ai-review-edit'),
                  onPressed: canApprove ? onApprove : null,
                  icon: const Icon(Icons.fact_check_outlined, size: 16),
                  label: Text(context.tr('Review and apply')),
                ),
                TextButton(
                  onPressed: canApprove ? onDecline : null,
                  child: Text(context.tr('Cancel')),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Text(
              context.tr(
                applied
                    ? (edit.taskCount > 0
                          ? '{n} checkable tasks written to the editor.'
                          : 'The approved content was written to the editor.')
                    : edit.status == AiEditStatus.stale
                    ? 'Your note changed after this proposal. Ask for a new proposal to keep your latest changes.'
                    : 'No changes were made to the note.',
                {'n': edit.taskCount},
              ),
              style: TextStyle(
                color: p.textMuted,
                fontSize: Fs.small,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditApprovalDialog extends StatelessWidget {
  const _EditApprovalDialog({required this.edit});
  final AiNoteEdit edit;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final replace = edit.operation == 'replace';
    return AppDialog(
      icon: Icons.rate_review_outlined,
      iconColor: replace ? p.warning : null,
      title: context.tr('Review note change'),
      subtitle: edit.summary,
      width: 720,
      height: MediaQuery.sizeOf(context).height * .75,
      scrollable: false,
      bodyPadding: const EdgeInsets.all(Sp.lg),
      content: SizedBox(
        width: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                color: (replace ? p.danger : p.info).withValues(
                  alpha: p.isDark ? .12 : .07,
                ),
                borderRadius: BorderRadius.circular(Rad.md),
                border: Border.all(
                  color: (replace ? p.danger : p.info).withValues(alpha: .28),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    replace
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    size: 16,
                    color: replace ? p.danger : p.info,
                  ),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      context.tr(
                        edit.operation == 'patch'
                            ? 'Only the displayed passages will change. All other content will be kept.'
                            : edit.operation == 'append'
                            ? 'This content will be added to the end. Existing content will be kept.'
                            : 'This will replace the entire note content. Review it before approving.',
                      ),
                      style: TextStyle(
                        color: replace ? p.danger : p.textMuted,
                        fontSize: Fs.small,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Sp.md),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: p.editorBg,
                  borderRadius: BorderRadius.circular(Rad.lg),
                  border: Border.all(color: p.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Sp.lg),
                  child: SelectionArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (edit.operation == 'patch')
                          SelectableText(
                            edit.preview,
                            style: AppTheme.mono(
                              size: 13,
                              color: context.palette.text,
                            ),
                          ),
                        if (edit.operation != 'patch')
                          for (final segment in splitSegments(
                            edit.preview,
                          )) ...[
                            if (segment is TextSegment)
                              MarkdownBody(
                                data: segment.text,
                                checkboxBuilder: (checked) => SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Checkbox(
                                    value: checked,
                                    onChanged: null,
                                  ),
                                ),
                                extensionSet: md.ExtensionSet.gitHubFlavored,
                              ),
                            if (segment is CodeSegment)
                              if (aiVisual(segment.info, segment.code) != null)
                                VisualBlockView(
                                  source: aiVisual(
                                    segment.info,
                                    segment.code,
                                  )!.json,
                                )
                              else
                                SelectableText(
                                  segment.code,
                                  style: AppTheme.mono(
                                    size: 13,
                                    color: context.palette.text,
                                  ),
                                ),
                            const SizedBox(height: 12),
                          ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        const DialogCancelButton(label: 'Back', result: false),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(context.tr('Approve and write to note')),
        ),
      ],
    );
  }
}

class _ModelPicker extends ConsumerStatefulWidget {
  const _ModelPicker({required this.current});
  final String current;
  @override
  ConsumerState<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends ConsumerState<_ModelPicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(aiModelsProvider);
    final p = context.palette;
    final query = _query.toLowerCase();
    final models = [
      ...?catalog.asData?.value.where(
        (m) => '${m.id} ${m.name}'.toLowerCase().contains(query),
      ),
    ];
    // The model in use first, then the provider's order.
    final current = models.indexWhere((m) => m.id == widget.current);
    if (current > 0) models.insert(0, models.removeAt(current));
    return AppDialog(
      icon: Icons.auto_awesome_outlined,
      title: context.tr('Choose model'),
      width: 460,
      height: 520,
      scrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: context.tr('Search models'),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: p.textMuted,
                ),
              ),
            ),
            const SizedBox(height: Sp.sm),
            Expanded(
              child: catalog.isLoading
                  ? DialogEmptyState(
                      loading: true,
                      message: context.tr('Loading…'),
                    )
                  : catalog.hasError
                  ? DialogEmptyState(
                      icon: Icons.cloud_off_rounded,
                      message: context.tr(
                        'Could not load models. You can enter a model ID below.',
                      ),
                    )
                  : ListView(
                      children: [
                        for (final model in models)
                          DialogListItem(
                            selected: model.id == widget.current,
                            leading: Icon(
                              model.id == widget.current
                                  ? Icons.check_circle_rounded
                                  : Icons.auto_awesome_outlined,
                              size: 18,
                              color: model.id == widget.current
                                  ? p.accent
                                  : p.textFaint,
                            ),
                            title: Text(
                              model.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              model.id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                if (model.images)
                                  _CapabilityTag(
                                    icon: Icons.image_outlined,
                                    tooltip: context.tr('Images'),
                                  ),
                                if (model.pdf)
                                  _CapabilityTag(
                                    icon: Icons.picture_as_pdf_outlined,
                                    tooltip: 'PDF',
                                  ),
                                if (model.efforts.isNotEmpty)
                                  _CapabilityTag(
                                    icon: Icons.psychology_outlined,
                                    tooltip: context.tr('Reasoning'),
                                  ),
                              ],
                            ),
                            onTap: () => Navigator.pop(context, model.id),
                          ),
                      ],
                    ),
            ),
            if (_query.trim().isNotEmpty)
              TextButton.icon(
                onPressed: () => Navigator.pop(context, _query.trim()),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(
                  context.tr('Use model ID: {id}', {'id': _query.trim()}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
      footerLeading: TextButton.icon(
        onPressed: () => ref.invalidate(aiModelsProvider),
        icon: const Icon(Icons.refresh_rounded),
        label: Text(context.tr('Refresh')),
      ),
      actions: const [DialogCancelButton()],
    );
  }
}

class _CapabilityTag extends StatelessWidget {
  const _CapabilityTag({required this.icon, required this.tooltip});
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.codeBg,
          borderRadius: BorderRadius.circular(Rad.sm),
          border: Border.all(color: p.border),
        ),
        child: Icon(icon, size: 13, color: p.textMuted),
      ),
    );
  }
}
