import '../../domain/colored_text.dart';
import '../../domain/visual_block.dart';
import '../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../core/widgets/color_picker_panel.dart';
import 'markdown_commands.dart';
import 'table_commands.dart';

/// Markdown actions in a single fixed row above the editor content.
/// Actions that do not fit move into a trailing "More" menu.
class FormatToolbar extends StatelessWidget {
  const FormatToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    this.onInsertImage,
    this.onInsertGallery,
    this.onAttachFile,
    this.onInsertVisual,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback? onInsertImage;
  final VoidCallback? onInsertGallery;
  final VoidCallback? onAttachFile;
  final ValueChanged<VisualKind>? onInsertVisual;

  void _run(void Function(TextEditingController c) action) {
    action(controller);
    onChanged(controller.text);
    focusNode.requestFocus();
  }

  Future<void> _pickTextColor(BuildContext context) async {
    final savedSelection = controller.selection;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => _TextColorDialog(),
    );
    if (chosen == null || focusNode.context?.mounted != true) return;
    controller.selection = savedSelection;
    _run((c) => MarkdownCommands.textColor(c, chosen.isEmpty ? null : chosen));
  }

  Future<void> _pickTypography(BuildContext context, bool family) async {
    final savedSelection = controller.selection;
    final original = controller.text;
    String? initial;
    for (final match in styledTextPattern.allMatches(original)) {
      if (savedSelection.start >= match.start &&
          savedSelection.end <= match.end) {
        initial = parseTextStyle(
          match[1]!,
        )?[family ? 'font-family' : 'font-size'];
        break;
      }
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _TypographyDialog(family: family, initial: initial),
    );
    if (chosen == null ||
        focusNode.context?.mounted != true ||
        controller.text != original) {
      return;
    }
    controller.selection = savedSelection;
    _run((c) {
      if (family) {
        MarkdownCommands.fontFamily(c, chosen.isEmpty ? null : chosen);
      } else {
        MarkdownCommands.fontSize(
          c,
          chosen.isEmpty ? null : double.parse(chosen),
        );
      }
    });
  }

  /// Insert a table, or edit the one at the caret (rows, columns, alignment).
  Future<void> _tableMenu(BuildContext context, BuildContext anchor) async {
    final saved = controller.selection;
    final inTable =
        saved.isValid &&
        MarkdownTable.at(controller.text, saved.baseOffset) != null;
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(
      Offset(0, box.size.height),
      ancestor: overlay,
    );
    final p = context.palette;
    PopupMenuItem<Object> item(Object value, IconData icon, String label) =>
        PopupMenuItem<Object>(
          value: value,
          height: 36,
          child: Row(
            children: [
              Icon(icon, size: 17, color: p.textMuted),
              const SizedBox(width: Sp.md),
              Text(label),
            ],
          ),
        );
    final choice = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(
        origin & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        item(
          'insert',
          Icons.add_box_outlined,
          context.tr('Insert table\u2026'),
        ),
        if (inTable) ...[
          const PopupMenuDivider(),
          item(
            TableOp.rowAbove,
            Icons.vertical_align_top_rounded,
            context.tr('Add row above'),
          ),
          item(
            TableOp.rowBelow,
            Icons.vertical_align_bottom_rounded,
            context.tr('Add row below'),
          ),
          item(
            TableOp.columnLeft,
            Icons.first_page_rounded,
            context.tr('Add column left'),
          ),
          item(
            TableOp.columnRight,
            Icons.last_page_rounded,
            context.tr('Add column right'),
          ),
          item(
            TableOp.deleteRow,
            Icons.remove_circle_outline_rounded,
            context.tr('Delete row'),
          ),
          item(
            TableOp.deleteColumn,
            Icons.remove_circle_outline_rounded,
            context.tr('Delete column'),
          ),
          const PopupMenuDivider(),
          item(
            TableOp.alignLeft,
            Icons.format_align_left_rounded,
            context.tr('Align column left'),
          ),
          item(
            TableOp.alignCenter,
            Icons.format_align_center_rounded,
            context.tr('Align column center'),
          ),
          item(
            TableOp.alignRight,
            Icons.format_align_right_rounded,
            context.tr('Align column right'),
          ),
          item(
            TableOp.format,
            Icons.auto_fix_high_outlined,
            context.tr('Tidy table'),
          ),
        ],
      ],
    );
    if (choice == null || focusNode.context?.mounted != true) return;
    if (choice == 'insert') {
      if (!context.mounted) return;
      final size = await showDialog<(int, int)>(
        context: context,
        builder: (_) => const _TableSizeDialog(),
      );
      if (size == null || focusNode.context?.mounted != true) return;
      controller.selection = saved;
      _run(
        (c) => MarkdownCommands.insert(
          c,
          '\n${TableCommands.create(size.$1, size.$2, header: trs('Column'))}\n',
        ),
      );
      return;
    }
    controller.selection = saved;
    _run((c) => TableCommands.apply(c, choice as TableOp));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    // Ordered by how often they are used; each inner list is a visual group.
    // Whatever does not fit on one row moves into the "More" menu, so the
    // toolbar never grows to several rows and pushes the note down.
    final groups = <List<_ToolAction>>[
      [
        _ToolAction(
          Icons.tag_rounded,
          context.tr('Heading (cycle H1–H3)'),
          () => _run(MarkdownCommands.cycleHeading),
        ),
        _ToolAction(
          Icons.format_bold_rounded,
          context.tr('Bold'),
          () => _run(MarkdownCommands.bold),
        ),
        _ToolAction(
          Icons.format_italic_rounded,
          context.tr('Italic'),
          () => _run(MarkdownCommands.italic),
        ),
        _ToolAction(
          Icons.strikethrough_s_rounded,
          context.tr('Strikethrough'),
          () => _run(MarkdownCommands.strike),
        ),
        _ToolAction(
          Icons.border_color_outlined,
          context.tr('Highlight'),
          () => _run(MarkdownCommands.highlight),
        ),
      ],
      [
        _ToolAction(
          Icons.format_list_bulleted_rounded,
          context.tr('Bulleted list'),
          () => _run(MarkdownCommands.bulletList),
        ),
        _ToolAction(
          Icons.format_list_numbered_rounded,
          context.tr('Numbered list'),
          () => _run(MarkdownCommands.orderedList),
        ),
        _ToolAction(
          Icons.check_box_outlined,
          context.tr('Task list (toggle)'),
          () => _run(MarkdownCommands.toggleTask),
        ),
        _ToolAction(
          Icons.format_quote_rounded,
          context.tr('Quote'),
          () => _run(MarkdownCommands.quote),
        ),
      ],
      [
        _ToolAction(
          Icons.link_rounded,
          context.tr('Link'),
          () => _run(MarkdownCommands.link),
        ),
        _ToolAction(
          Icons.code_rounded,
          context.tr('Inline code'),
          () => _run(MarkdownCommands.inlineCode),
        ),
        _ToolAction(
          Icons.data_object_rounded,
          context.tr('Code block'),
          () => _run((c) => MarkdownCommands.codeBlock(c)),
        ),
        _ToolAction(
          Icons.table_chart_outlined,
          context.tr('Table'),
          () => _tableMenu(context, context),
          anchored: (anchor) => _tableMenu(context, anchor),
        ),
      ],
      [
        if (onInsertImage != null)
          _ToolAction(
            Icons.add_photo_alternate_outlined,
            context.tr('Insert image'),
            onInsertImage!,
          ),
        if (onInsertGallery != null)
          _ToolAction(
            Icons.photo_library_outlined,
            context.tr('Add images side by side'),
            onInsertGallery!,
          ),
        if (onAttachFile != null)
          _ToolAction(
            Icons.attach_file_rounded,
            context.tr('Attach file'),
            onAttachFile!,
          ),
        if (onInsertVisual != null) ...[
          _ToolAction(
            Icons.bar_chart_rounded,
            context.tr('Chart'),
            () => onInsertVisual!(VisualKind.chart),
          ),
          _ToolAction(
            Icons.account_tree_outlined,
            context.tr('Mind map'),
            () => onInsertVisual!(VisualKind.mindmap),
          ),
        ],
      ],
      [
        _ToolAction(
          Icons.format_size_rounded,
          context.tr('Font size'),
          () => _pickTypography(context, false),
        ),
        _ToolAction(
          Icons.font_download_outlined,
          context.tr('Font family'),
          () => _pickTypography(context, true),
        ),
        _ToolAction(
          Icons.format_color_text_rounded,
          context.tr('Text color'),
          () => _pickTextColor(context),
        ),
      ],
    ].where((g) => g.isNotEmpty).toList();

    final platform = Theme.of(context).platform;
    final touch =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final button = touch ? 44.0 : 34.0;
    const gap = 2.0;
    const separator = Sp.sm * 2 + 1;

    return Container(
      decoration: BoxDecoration(
        color: p.isGlass ? p.hover : p.surface,
        border: Border(
          top: BorderSide(color: p.border),
          bottom: BorderSide(color: p.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
      child: LayoutBuilder(
        builder: (context, cons) {
          final total = groups.fold<int>(0, (n, g) => n + g.length);
          double needed(int count) {
            var width = 0.0;
            var placed = 0;
            for (var gi = 0; gi < groups.length && placed < count; gi++) {
              if (gi > 0) width += separator;
              for (var i = 0; i < groups[gi].length && placed < count; i++) {
                width += button + gap;
                placed++;
              }
            }
            return width;
          }

          var visible = total;
          if (needed(total) > cons.maxWidth) {
            final room = cons.maxWidth - button - separator;
            while (visible > 0 && needed(visible) > room) {
              visible--;
            }
          }

          final row = <Widget>[];
          // _ToolAction entries; an int marks the start of a new group.
          final overflow = <Object>[];
          var placed = 0;
          for (var gi = 0; gi < groups.length; gi++) {
            final group = groups[gi];
            for (var i = 0; i < group.length; i++) {
              final action = group[i];
              if (placed < visible) {
                if (i == 0 && gi > 0) row.add(const _GroupDivider());
                row.add(
                  Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: Builder(
                      builder: (anchor) => AppIconButton(
                        icon: action.icon,
                        tooltip: action.label,
                        onPressed: action.anchored == null
                            ? action.onPressed
                            : () => action.anchored!(anchor),
                      ),
                    ),
                  ),
                );
              } else {
                if (i == 0 && overflow.isNotEmpty) overflow.add(gi);
                overflow.add(action);
              }
              placed++;
            }
          }
          if (overflow.isNotEmpty) {
            row.add(const _GroupDivider());
            row.add(
              PopupMenuButton<_ToolAction>(
                tooltip: context.tr('More formatting'),
                position: PopupMenuPosition.under,
                constraints: const BoxConstraints(minWidth: 200, maxWidth: 340),
                onSelected: (a) =>
                    a.anchored == null ? a.onPressed() : a.anchored!(context),
                itemBuilder: (_) => [
                  for (final entry in overflow)
                    if (entry is _ToolAction)
                      PopupMenuItem(
                        value: entry,
                        height: 38,
                        child: Row(
                          children: [
                            Icon(entry.icon, size: 18, color: p.textMuted),
                            const SizedBox(width: Sp.md),
                            Flexible(
                              child: Text(
                                entry.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const PopupMenuDivider(height: Sp.sm + 1),
                ],
                child: SizedBox(
                  width: button,
                  height: button,
                  child: Icon(
                    Icons.more_horiz_rounded,
                    size: 18,
                    color: p.textMuted,
                  ),
                ),
              ),
            );
          }
          return Row(children: row);
        },
      ),
    );
  }
}

class _ToolAction {
  const _ToolAction(this.icon, this.label, this.onPressed, {this.anchored});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  /// For actions that open a menu next to their button.
  final void Function(BuildContext anchor)? anchored;
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 18,
    margin: const EdgeInsets.symmetric(horizontal: Sp.sm),
    color: context.palette.border,
  );
}

class _TextColorDialog extends StatefulWidget {
  @override
  State<_TextColorDialog> createState() => _TextColorDialogState();
}

class _TextColorDialogState extends State<_TextColorDialog> {
  Color _color = const Color(0xFF2563EB);
  bool _validColor = true;
  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.format_color_text_rounded,
      title: context.tr('Text color'),
      subtitle: context.tr(
        'Apply to selected text, or choose a color and start typing.',
      ),
      width: 420,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ColorPickerPanel(
              color: _color,
              onChanged: (color) => _color = color,
              onValidityChanged: (valid) => setState(() => _validColor = valid),
            ),
          ],
        ),
      ),
      footerLeading: TextButton.icon(
        onPressed: () => Navigator.pop(context, ''),
        icon: const Icon(Icons.format_color_reset_outlined),
        label: Text(context.tr('Default text color')),
      ),
      actions: [
        const DialogCancelButton(),
        FilledButton(
          onPressed: !_validColor
              ? null
              : () {
                  RecentColors.remember(_color).catchError((Object _) {});
                  Navigator.pop(
                    context,
                    _color
                        .toARGB32()
                        .toRadixString(16)
                        .substring(2)
                        .toUpperCase(),
                  );
                },
          child: Text(context.tr('Apply')),
        ),
      ],
    );
  }
}

class _TypographyDialog extends StatefulWidget {
  const _TypographyDialog({required this.family, this.initial});
  final bool family;
  final String? initial;
  @override
  State<_TypographyDialog> createState() => _TypographyDialogState();
}

class _TypographyDialogState extends State<_TypographyDialog> {
  late String _family = textFontFamilies.contains(widget.initial)
      ? widget.initial!
      : 'Inter';
  late double _size =
      (double.tryParse(widget.initial?.replaceAll('pt', '') ?? '') ?? 14).clamp(
        8,
        48,
      );
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppDialog(
      icon: widget.family
          ? Icons.font_download_outlined
          : Icons.format_size_rounded,
      title: context.tr(widget.family ? 'Font family' : 'Font size'),
      subtitle: context.tr(
        'Apply to selected text, or choose a style and start typing.',
      ),
      width: 420,
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 84,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                color: p.codeBg,
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(Rad.lg),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  context.tr('Sample text'),
                  style: TextStyle(
                    color: p.text,
                    fontFamily: _family,
                    fontSize: _size * 4 / 3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Sp.lg),
            if (widget.family)
              // Chips keep all families visible without scrolling, even in
              // short windows; each label is drawn in its own font.
              Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final family in textFontFamilies)
                    ChoiceChip(
                      label: Text(
                        family,
                        style: TextStyle(
                          color: family == _family ? p.accent : p.text,
                          fontFamily: family,
                          fontSize: Fs.body,
                        ),
                      ),
                      selected: family == _family,
                      onSelected: (_) => setState(() => _family = family),
                    ),
                ],
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('Size in points'),
                    style: TextStyle(color: p.textMuted),
                  ),
                  Text(
                    '${_size.round()} pt',
                    style: TextStyle(
                      color: p.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Slider(
                value: _size,
                min: 8,
                max: 48,
                divisions: 40,
                label: '${_size.round()} pt',
                onChanged: (size) => setState(() => _size = size),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final size in [10, 12, 14, 16, 18, 20, 24, 28, 32, 36])
                    ChoiceChip(
                      label: Text('$size'),
                      selected: _size.round() == size,
                      onSelected: (_) =>
                          setState(() => _size = size.toDouble()),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      footerLeading: TextButton.icon(
        onPressed: () => Navigator.pop(context, ''),
        icon: const Icon(Icons.format_clear_rounded),
        label: Text(context.tr('Default style')),
      ),
      actions: [
        const DialogCancelButton(),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            widget.family ? _family : '${_size.round()}',
          ),
          child: Text(context.tr('Apply')),
        ),
      ],
    );
  }
}

/// Rows and columns for a new table.
class _TableSizeDialog extends StatefulWidget {
  const _TableSizeDialog();

  @override
  State<_TableSizeDialog> createState() => _TableSizeDialogState();
}

class _TableSizeDialogState extends State<_TableSizeDialog> {
  int _rows = 3;
  int _columns = 3;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget stepper(
      String label,
      int value,
      int max,
      ValueChanged<int> set,
    ) => Row(
      children: [
        Expanded(child: Text(label)),
        AppIconButton(
          icon: Icons.remove_rounded,
          tooltip: context.tr('Fewer'),
          onPressed: value > 1 ? () => setState(() => set(value - 1)) : null,
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        AppIconButton(
          icon: Icons.add_rounded,
          tooltip: context.tr('More'),
          onPressed: value < max ? () => setState(() => set(value + 1)) : null,
        ),
      ],
    );
    return AppDialog(
      icon: Icons.table_chart_outlined,
      title: context.tr('Insert table'),
      width: 360,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          stepper(context.tr('Rows'), _rows, 30, (v) => _rows = v),
          stepper(context.tr('Columns'), _columns, 12, (v) => _columns = v),
          const SizedBox(height: Sp.sm),
          Text(
            context.tr(
              'Tip: Tab moves to the next cell and adds a row at the end.',
            ),
            style: TextStyle(color: p.textFaint, fontSize: Fs.small),
          ),
        ],
      ),
      actions: [
        const DialogCancelButton(),
        FilledButton(
          onPressed: () => Navigator.pop(context, (_rows, _columns)),
          child: Text(context.tr('Insert')),
        ),
      ],
    );
  }
}
