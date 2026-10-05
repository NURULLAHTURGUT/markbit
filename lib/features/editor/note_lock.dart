import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/note_vault.dart';
import '../../application/persistence_coordinator.dart';
import '../../application/providers.dart';
import '../../application/ui_providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../../domain/note_crypto.dart';
import '../dialogs/dialogs.dart';

/// Minimum password length for locked notes.
const int minNotePasswordLength = 6;

/// Asks for a password and encrypts the note. Returns true when locked.
Future<bool> showLockNoteDialog(BuildContext context, String noteId) async {
  final locked = await showDialog<bool>(
    context: context,
    builder: (_) => _LockDialog(noteId: noteId),
  );
  return locked == true;
}

class _LockDialog extends ConsumerStatefulWidget {
  const _LockDialog({required this.noteId});
  final String noteId;

  @override
  ConsumerState<_LockDialog> createState() => _LockDialogState();
}

class _LockDialogState extends ConsumerState<_LockDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _password.text;
    if (password.length < minNotePasswordLength) {
      setState(
        () => _error = context.tr('Use at least {n} characters.', {
          'n': minNotePasswordLength,
        }),
      );
      return;
    }
    if (password != _confirm.text) {
      setState(() => _error = context.tr('Passwords do not match.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.read(persistenceProvider).flushEditors();
    try {
      await ref
          .read(libraryProvider.notifier)
          .lockNote(widget.noteId, password);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      suffixIcon: IconButton(
        tooltip: context.tr(_show ? 'Hide password' : 'Show password'),
        icon: Icon(
          _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 18,
        ),
        onPressed: () => setState(() => _show = !_show),
      ),
    );
    return AppDialog(
      icon: Icons.lock_outline_rounded,
      title: context.tr('Lock note'),
      subtitle: context.tr(
        'The note is encrypted on this device with your password.',
      ),
      width: 440,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DialogLabel(context.tr('Password')),
          TextField(
            key: const ValueKey('lock-password'),
            controller: _password,
            obscureText: !_show,
            autofocus: true,
            enabled: !_busy,
            decoration: field(context.tr('Password')),
          ),
          const SizedBox(height: Sp.md),
          DialogLabel(context.tr('Confirm password')),
          TextField(
            key: const ValueKey('lock-confirm'),
            controller: _confirm,
            obscureText: !_show,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: field(context.tr('Confirm password')),
          ),
          const SizedBox(height: Sp.md),
          Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: p.warning.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(Rad.md),
              border: Border.all(color: p.warning.withValues(alpha: .4)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: p.warning),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    context.tr(
                      'If you forget the password the note cannot be recovered. The title, cover and AI conversations are not encrypted, and earlier versions of this note are deleted.',
                    ),
                    style: TextStyle(
                      color: p.text,
                      fontSize: Fs.small,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: Sp.sm),
            Text(
              _error!,
              style: TextStyle(color: p.danger, fontSize: Fs.small),
            ),
          ],
        ],
      ),
      actions: [
        DialogCancelButton(label: 'Cancel', result: false),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_outline_rounded),
          label: Text(context.tr('Lock')),
        ),
      ],
    );
  }
}

/// Confirms removing the password from an unlocked note.
Future<void> confirmRemoveLock(
  BuildContext context,
  WidgetRef ref,
  String noteId,
) async {
  final ok = await confirmAction(
    context,
    title: context.tr('Remove lock?'),
    message: context.tr(
      'The note will be stored as plain text again and anyone with access to this device can read it.',
    ),
    confirmLabel: context.tr('Remove lock'),
  );
  if (!ok) return;
  ref.read(persistenceProvider).flushEditors();
  ref.read(libraryProvider.notifier).removeLock(noteId);
}

/// Shown instead of the editor while a locked note is closed.
class LockedNoteView extends ConsumerStatefulWidget {
  const LockedNoteView({super.key, required this.noteId, this.onBack});
  final String noteId;
  final VoidCallback? onBack;

  @override
  ConsumerState<LockedNoteView> createState() => _LockedNoteViewState();
}

class _LockedNoteViewState extends ConsumerState<LockedNoteView> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(noteVaultProvider.notifier)
          .unlock(widget.noteId, _password.text);
    } on WrongPasswordException {
      if (mounted) {
        setState(() => _error = context.tr('Wrong password.'));
        _password.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _password.text.length,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final note = ref.watch(noteProvider(widget.noteId));
    return ColoredBox(
      color: p.editorBg,
      child: Stack(
        children: [
          if (widget.onBack != null)
            Positioned(
              left: Sp.sm,
              top: Sp.sm,
              child: IconButton(
                tooltip: context.tr('Back to notes'),
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              ),
            ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sp.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: p.accent.withValues(
                            alpha: p.isDark ? .16 : .10,
                          ),
                          borderRadius: BorderRadius.circular(Rad.lg),
                        ),
                        child: Icon(
                          Icons.lock_outline_rounded,
                          color: p.accent,
                          size: 26,
                        ),
                      ),
                    ),
                    const SizedBox(height: Sp.lg),
                    Text(
                      note?.displayTitle ?? '',
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: p.text,
                        fontSize: Fs.heading,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: Sp.xs),
                    Text(
                      context.tr('This note is locked.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: p.textMuted, fontSize: Fs.small),
                    ),
                    const SizedBox(height: Sp.lg),
                    TextField(
                      key: const ValueKey('unlock-password'),
                      controller: _password,
                      obscureText: !_show,
                      autofocus: true,
                      enabled: !_busy,
                      onSubmitted: (_) => _unlock(),
                      decoration: InputDecoration(
                        hintText: context.tr('Password'),
                        errorText: _error,
                        prefixIcon: Icon(
                          Icons.key_rounded,
                          size: 18,
                          color: p.textFaint,
                        ),
                        suffixIcon: IconButton(
                          tooltip: context.tr(
                            _show ? 'Hide password' : 'Show password',
                          ),
                          icon: Icon(
                            _show
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _show = !_show),
                        ),
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    FilledButton.icon(
                      onPressed: _busy ? null : _unlock,
                      icon: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_rounded, size: 18),
                      label: Text(context.tr('Unlock')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
