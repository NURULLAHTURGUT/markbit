import '../../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/runner_notifier.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../domain/languages.dart';
import '../../dialogs/dialogs.dart';
import '../highlight/highlighter.dart';

/// A fenced code block in the preview: language label, copy and Run actions.
class CodeBlockView extends ConsumerWidget {
  const CodeBlockView({
    super.key,
    required this.info,
    required this.code,
    required this.onRun,
    this.noteId,
  });

  final String? noteId;
  final String info;
  final String code;
  final void Function(String? language, String code) onRun;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final lang = Languages.find(info);
    final label = lang?.name ?? (info.isEmpty ? 'text' : info);
    final runnable = lang?.runnable ?? false;
    final busy = ref.watch(
      (noteId == null ? runnerProvider : noteRunnerProvider(noteId!)).select(
        (s) => s.isBusy,
      ),
    );

    final base = AppTheme.mono(size: 13, color: p.text, height: 1.55);
    final span = code.length > 100000
        ? TextSpan(text: code, style: base)
        : buildHighlightedSpan(
            code,
            tokenizeCode(code, lang?.id ?? info),
            base,
            p,
          );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: Sp.sm),
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(Rad.md),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info.toLowerCase() == 'mermaid')
            Padding(
              padding: const EdgeInsets.all(Sp.md),
              child: Text(
                context.tr(
                  'This diagram syntax is not supported. Its source is preserved.',
                ),
                style: TextStyle(color: p.textMuted, fontSize: Fs.small),
              ),
            ),
          Container(
            padding: const EdgeInsets.only(left: Sp.md, right: Sp.xs),
            height: 36,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 14, color: p.textFaint),
                const SizedBox(width: Sp.xs + 2),
                Text(
                  label,
                  style: TextStyle(
                    color: p.textMuted,
                    fontSize: Fs.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.copy_rounded,
                  tooltip: context.tr('Copy code'),
                  size: 16,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    showToast(context, context.tr('Code copied'));
                  },
                ),
                if (runnable)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, right: 2),
                    child: _RunButton(
                      busy: busy,
                      onPressed: busy ? null : () => onRun(lang!.id, code),
                    ),
                  ),
              ],
            ),
          ),
          _HorizontalCode(child: Text.rich(span)),
        ],
      ),
    );
  }
}

/// Horizontally scrolling code with a visible scrollbar and a fade on the
/// clipped edge, so long lines read as "scroll for more" instead of cut off.
class _HorizontalCode extends StatefulWidget {
  const _HorizontalCode({required this.child});
  final Widget child;

  @override
  State<_HorizontalCode> createState() => _HorizontalCodeState();
}

class _HorizontalCodeState extends State<_HorizontalCode> {
  final _controller = ScrollController();
  bool _moreRight = false;
  bool _moreLeft = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted || !_controller.hasClients) return;
    final pos = _controller.position;
    final right = pos.pixels < pos.maxScrollExtent - 1;
    final left = pos.pixels > 1;
    if (right != _moreRight || left != _moreLeft) {
      setState(() {
        _moreRight = right;
        _moreLeft = left;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
        return false;
      },
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: _moreRight || _moreLeft,
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.lg),
          child: widget.child,
        ),
      ),
    );
    if (!_moreRight && !_moreLeft) return view;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        colors: [
          _moreLeft ? Colors.transparent : Colors.black,
          Colors.black,
          Colors.black,
          _moreRight ? Colors.transparent : Colors.black,
        ],
        stops: const [0, .04, .94, 1],
      ).createShader(rect),
      child: view,
    );
  }
}

class _RunButton extends StatelessWidget {
  const _RunButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: context.tr('Run code block'),
      child: Material(
        color: p.success.withValues(alpha: onPressed == null ? 0.08 : 0.16),
        borderRadius: BorderRadius.circular(Rad.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Rad.sm),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (busy)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.success,
                    ),
                  )
                else
                  Icon(Icons.play_arrow_rounded, size: 16, color: p.success),
                const SizedBox(width: 4),
                Text(
                  context.tr('Run'),
                  style: TextStyle(
                    color: p.success,
                    fontSize: Fs.small,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
