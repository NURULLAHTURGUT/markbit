import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import '../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/runner_notifier.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/time_ago.dart';
import '../../core/widgets/app_icon_button.dart';
import '../dialogs/dialogs.dart';

/// Output console shown under the editor while/after code runs.
class RunPanel extends ConsumerStatefulWidget {
  const RunPanel({super.key, this.onRerun, this.onAskAi, this.noteId});
  final String? noteId;

  /// Re-runs the last executed snippet.
  final VoidCallback? onRerun;

  /// Sends the current output to the AI assistant.
  final VoidCallback? onAskAi;

  @override
  ConsumerState<RunPanel> createState() => _RunPanelState();
}

class _RunPanelState extends ConsumerState<RunPanel> {
  final _scroll = ScrollController();
  final _stdin = TextEditingController();
  ProviderListenable<RunState> get _provider => widget.noteId == null
      ? runnerProvider
      : noteRunnerProvider(widget.noteId!);
  RunnerNotifier get _notifier => widget.noteId == null
      ? ref.read(runnerProvider.notifier)
      : ref.read(noteRunnerProvider(widget.noteId!).notifier);
  bool _showInput = false;

  @override
  void initState() {
    super.initState();
    _stdin.text = ref.read(_provider).stdin;
  }

  @override
  void dispose() {
    _scroll.dispose();
    _stdin.dispose();
    super.dispose();
  }

  void _stickToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      if (pos.maxScrollExtent - pos.pixels < 120) {
        _scroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = ref.watch(_provider);
    final notifier = _notifier;
    ref.listen(_provider.select((s) => s.chunks), (_, _) => _stickToBottom());

    final mono = AppTheme.mono(size: 12.5, color: p.text, height: 1.5);

    return Container(
      decoration: BoxDecoration(
        color: p.codeBg,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        children: [
          _Header(
            state: state,
            showInput: _showInput,
            onToggleInput: () => setState(() => _showInput = !_showInput),
            onStop: notifier.cancel,
            onRerun: widget.onRerun,
            onAskAi: widget.onAskAi,
            onCopy: () {
              Clipboard.setData(ClipboardData(text: notifier.outputText));
              showToast(context, context.tr('Output copied'));
            },
            onClear: state.isBusy ? null : notifier.clearOutput,
            onClose: notifier.hidePanel,
          ),
          if (_showInput)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, 0),
              child: TextField(
                controller: _stdin,
                minLines: 1,
                maxLines: 3,
                style: mono,
                onChanged: notifier.setStdin,
                decoration: InputDecoration(
                  labelText: context.tr('Standard input (stdin)'),
                  hintText: context.tr(
                    'Text passed to the program when it runs',
                  ),
                ),
              ),
            ),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(Sp.md),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: state.chunks.isEmpty
                      ? Text(
                          state.isBusy
                              ? (state.status == RunStatus.compiling
                                    ? context.tr('Compiling\u2026')
                                    : context.tr('Running\u2026'))
                              : context.tr('No output.'),
                          style: mono.copyWith(color: p.textFaint),
                        )
                      : SelectableText.rich(
                          TextSpan(
                            style: mono,
                            children: [
                              for (final c in state.chunks)
                                TextSpan(
                                  text: c.text,
                                  style: c.isError
                                      ? TextStyle(color: p.danger)
                                      : null,
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (state.result != null) _Footer(state: state),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.showInput,
    required this.onToggleInput,
    required this.onStop,
    required this.onRerun,
    required this.onAskAi,
    required this.onCopy,
    required this.onClear,
    required this.onClose,
  });

  final RunState state;
  final bool showInput;
  final VoidCallback onToggleInput;
  final VoidCallback onStop;
  final VoidCallback? onRerun;
  final VoidCallback? onAskAi;
  final VoidCallback onCopy;
  final VoidCallback? onClear;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final subtitle = [
      if (state.languageName.isNotEmpty) state.languageName,
      if (state.executorName.isNotEmpty) context.tr(state.executorName),
    ].join(' \u00b7 ');

    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: Sp.md, right: Sp.xs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          if (state.isBusy)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
            )
          else
            Icon(Icons.terminal_rounded, size: 16, color: p.textMuted),
          const SizedBox(width: Sp.sm),
          Text(
            context.tr('Output'),
            style: TextStyle(
              color: p.text,
              fontSize: Fs.small,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(width: Sp.sm),
            Flexible(
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textFaint, fontSize: Fs.caption),
              ),
            ),
          ],
          const Spacer(),
          if (state.isBusy)
            AppIconButton(
              icon: Icons.stop_rounded,
              tooltip: context.tr('Stop'),
              color: p.danger,
              onPressed: onStop,
            )
          else if (onRerun != null)
            AppIconButton(
              icon: Icons.replay_rounded,
              tooltip: context.tr('Run again'),
              onPressed: onRerun,
            ),
          AppIconButton(
            icon: Icons.keyboard_rounded,
            tooltip: context.tr('Standard input'),
            active: showInput,
            onPressed: onToggleInput,
          ),
          if (onAskAi != null && state.result != null)
            AppIconButton(
              icon: Icons.auto_awesome_rounded,
              tooltip: context.tr('Ask AI about this output'),
              onPressed: onAskAi,
            ),
          AppIconButton(
            icon: Icons.copy_rounded,
            tooltip: context.tr('Copy output'),
            onPressed: onCopy,
          ),
          AppIconButton(
            icon: Icons.delete_sweep_rounded,
            tooltip: context.tr('Clear output'),
            onPressed: onClear,
          ),
          AppIconButton(
            icon: Icons.close_rounded,
            tooltip: context.tr('Close panel'),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});
  final RunState state;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = state.result!;
    final IconData icon;
    final Color color;
    final String text;

    if (r.cancelled) {
      icon = Icons.stop_circle_rounded;
      color = p.warning;
      text = context.tr('Stopped');
    } else if (r.timedOut) {
      icon = Icons.timer_off_rounded;
      color = p.warning;
      text = context.tr('Timed out after {time}', {
        'time': formatDuration(r.elapsed),
      });
    } else if (r.failure != null) {
      icon = Icons.error_rounded;
      color = p.danger;
      text = context.tr('Could not run');
    } else if (r.compiledOnly) {
      icon = Icons.check_circle_rounded;
      color = p.success;
      text = context.tr('Compiled successfully (no entry point)');
    } else if ((r.exitCode ?? 0) == 0) {
      icon = Icons.check_circle_rounded;
      color = p.success;
      text = context.tr('Finished in {time}', {
        'time': formatDuration(r.elapsed),
      });
    } else {
      icon = Icons.cancel_rounded;
      color = p.danger;
      text = context.tr('Exited with code {code} · {time}', {
        'code': r.exitCode ?? -1,
        'time': formatDuration(r.elapsed),
      });
    }

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: Fs.caption,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (state.sourceLabel.isNotEmpty)
            Flexible(
              child: Text(
                state.sourceLabel,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: p.textFaint, fontSize: Fs.caption),
              ),
            ),
        ],
      ),
    );
  }
}
