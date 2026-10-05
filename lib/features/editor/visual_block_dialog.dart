import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/widgets/app_dialog.dart';
import '../../domain/visual_block.dart';
import 'preview/visual_block_view.dart';
import '../../core/theme/tokens.dart';

Future<VisualBlock?> showVisualBlockDialog(
  BuildContext context, {
  VisualBlock? initial,
  VisualKind kind = VisualKind.mindmap,
}) => showDialog<VisualBlock>(
  context: context,
  builder: (_) => _VisualBlockDialog(initial: initial, kind: kind),
);

class _VisualBlockDialog extends StatefulWidget {
  const _VisualBlockDialog({this.initial, required this.kind});
  final VisualBlock? initial;
  final VisualKind kind;
  @override
  State<_VisualBlockDialog> createState() => _VisualBlockDialogState();
}

class _VisualBlockDialogState extends State<_VisualBlockDialog> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _input = TextEditingController(text: widget.initial?.input ?? '');
  late ChartStyle _style = widget.initial?.style ?? ChartStyle.bar;
  String? _error;
  VisualKind get kind => widget.initial?.kind ?? widget.kind;
  @override
  void dispose() {
    _title.dispose();
    _input.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final block = VisualBlock.fromInput(
        kind: kind,
        title: _title.text,
        input: _input.text,
        style: _style,
      );
      Navigator.pop(context, block);
    } on FormatException catch (e) {
      setState(() => _error = context.tr(e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final map = kind == VisualKind.mindmap;
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          autofocus: true,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: context.tr(map ? 'Central topic' : 'Chart title'),
          ),
        ),
        if (!map) ...[
          DropdownButtonFormField<ChartStyle>(
            initialValue: _style,
            dropdownColor: p.surface.withValues(alpha: 1),
            elevation: 4,
            borderRadius: BorderRadius.circular(Rad.lg),
            style: TextStyle(color: p.text, fontSize: Fs.body),
            decoration: InputDecoration(labelText: context.tr('Chart type')),
            items: [
              for (final style in ChartStyle.values)
                DropdownMenuItem(
                  value: style,
                  child: Text(
                    context.tr(switch (style) {
                      ChartStyle.bar => 'Bar chart',
                      ChartStyle.line => 'Line chart',
                      ChartStyle.donut => 'Donut chart',
                      ChartStyle.pie => 'Pie chart',
                      ChartStyle.horizontalBar => 'Horizontal bar chart',
                      ChartStyle.area => 'Area chart',
                    }),
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _style = value);
            },
          ),
          const SizedBox(height: 16),
        ],
        Text(
          context.tr(
            map
                ? 'One topic per line. Indent children with two spaces.'
                : 'One label; value pair per line. Up to 24 entries.',
          ),
          style: TextStyle(color: p.textMuted, fontSize: Fs.label, height: 1.5),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _input,
          minLines: 16,
          maxLines: null,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: Fs.body,
            height: 1.6,
          ),
          decoration: InputDecoration(
            labelText: context.tr(map ? 'Topics' : 'Data points'),
            alignLabelWithHint: true,
            hintText: context.tr(
              map
                  ? 'Research\n  Ideas\n  Sources\nPlanning\n  Tasks'
                  : 'January; 40\nFebruary; 65\nMarch; 90',
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: p.danger)),
          ),
      ],
    );
    final preview = AnimatedBuilder(
      animation: Listenable.merge([_title, _input]),
      builder: (context, _) {
        VisualBlock? block;
        String? message;
        if (_input.text.trim().isNotEmpty) {
          try {
            block = VisualBlock.fromInput(
              kind: kind,
              title: _title.text.trim().isEmpty
                  ? context.tr(map ? 'Mind map' : 'Chart')
                  : _title.text,
              input: _input.text,
              style: _style,
            );
          } on FormatException catch (e) {
            message = context.tr(e.message);
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('Preview'),
              style: TextStyle(
                color: p.text,
                fontSize: Fs.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            if (block != null)
              VisualBlockView(source: block.json)
            else
              Container(
                constraints: const BoxConstraints(minHeight: 280),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: p.codeBg,
                  borderRadius: BorderRadius.circular(Rad.lg),
                  border: Border.all(color: p.border),
                ),
                alignment: Alignment.center,
                child: Text(
                  message ??
                      context.tr(
                        map
                            ? 'Enter topics to see a live preview.'
                            : 'Enter chart data to see a live preview.',
                      ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.textMuted, height: 1.5),
                ),
              ),
          ],
        );
      },
    );
    return AppDialog(
      icon: map ? Icons.account_tree_outlined : Icons.bar_chart_rounded,
      title: context.tr(map ? 'Mind map' : 'Chart'),
      width: 1040,
      scrollable: false,
      content: SizedBox(
        width: 1000,
        height: math.min(640, MediaQuery.sizeOf(context).height * 0.68),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 760
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: SingleChildScrollView(child: form)),
                    const SizedBox(width: 28),
                    Expanded(child: SingleChildScrollView(child: preview)),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [form, const SizedBox(height: 24), preview],
                  ),
                ),
        ),
      ),
      actions: [
        const DialogCancelButton(),
        FilledButton(
          onPressed: _save,
          child: Text(context.tr(widget.initial == null ? 'Insert' : 'Save')),
        ),
      ],
    );
  }
}
