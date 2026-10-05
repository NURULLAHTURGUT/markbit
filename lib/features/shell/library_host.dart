import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/persistence_coordinator.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/widgets/app_notification.dart';
import '../../data/repository/library_repository.dart';

/// Background library upkeep for the workspace: deletes notes whose trash
/// period has expired and applies changes other programs make to the
/// library folder (sync clients, text editors, scripts).
class LibraryHost extends ConsumerStatefulWidget {
  const LibraryHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LibraryHost> createState() => _LibraryHostState();
}

class _LibraryHostState extends ConsumerState<LibraryHost> {
  Timer? _purge;
  StreamSubscription<ExternalChange>? _external;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _purgeTrash());
    _purge = Timer.periodic(const Duration(hours: 1), (_) => _purgeTrash());
    final repository = ref.read(libraryRepositoryProvider);
    if (repository is FileLibraryRepository) {
      repository.history.limit = ref.read(settingsProvider).historyLimit;
      ref.listenManual(
        settingsProvider.select((s) => s.historyLimit),
        (_, limit) => repository.history.limit = limit,
      );
    }
    if (ref.read(libraryWatchEnabledProvider) &&
        repository is FileLibraryRepository) {
      _external = repository.watchExternalChanges().listen(_onExternal);
    }
  }

  @override
  void dispose() {
    _purge?.cancel();
    _external?.cancel();
    super.dispose();
  }

  void _purgeTrash() {
    if (!mounted) return;
    final days = ref.read(settingsProvider).trashRetentionDays;
    ref.read(libraryProvider.notifier).purgeExpiredTrash(days);
  }

  bool _hasLocalEdits(String id) =>
      ref.read(unsavedNotesProvider).contains(id) ||
      ref.read(persistenceProvider).isPending('note:$id');

  bool _isOpen(String id) {
    final open = ref.read(openNoteProvider);
    return open.tabs.contains(id) || open.secondaryId == id;
  }

  void _onExternal(ExternalChange change) {
    if (!mounted) return;
    final library = ref.read(libraryProvider.notifier);
    switch (change) {
      case ExternalNoteChanged(:final note):
        if (_hasLocalEdits(note.id)) {
          // Keep the user's edits: their save overwrites the file and the
          // repository moves the changed copy into version history.
          AppNotifications.show(
            context,
            context.tr(
              '"{title}" was changed outside Markbit. Your unsaved edits are kept; the other version goes to version history.',
              {'title': note.displayTitle},
            ),
            kind: NoticeKind.warning,
            duration: const Duration(seconds: 10),
            actionLabel: context.tr('Load disk version'),
            onAction: () {
              ref.read(unsavedNotesProvider.notifier).mark(note.id, false);
              library.applyExternalNote(note);
              ref.read(noteReloadProvider.notifier).reload(note.id);
            },
          );
          return;
        }
        final known = ref.read(libraryProvider).notes.containsKey(note.id);
        library.applyExternalNote(note);
        if (known && _isOpen(note.id)) {
          AppNotifications.show(
            context,
            context.tr('"{title}" was changed outside Markbit and reloaded.', {
              'title': note.displayTitle,
            }),
          );
        }
      case ExternalNoteRemoved(:final id):
        final note = ref.read(libraryProvider).notes[id];
        if (note == null) return;
        if (_hasLocalEdits(id)) {
          AppNotifications.show(
            context,
            context.tr(
              '"{title}" was deleted outside Markbit. It will be saved again with your edits.',
              {'title': note.displayTitle},
            ),
            kind: NoticeKind.warning,
            duration: const Duration(seconds: 10),
          );
          return;
        }
        final wasOpen = _isOpen(id);
        library.applyExternalRemoval(id);
        if (wasOpen) {
          AppNotifications.show(
            context,
            context.tr('"{title}" was deleted outside Markbit.', {
              'title': note.displayTitle,
            }),
            kind: NoticeKind.warning,
          );
        }
      case ExternalMetaChanged(:final notebooks, :final tags, :final templates):
        library.applyExternalMeta(
          notebooks: notebooks,
          tags: tags,
          templates: templates,
        );
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
