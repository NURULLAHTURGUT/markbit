import 'package:flutter/material.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../data/note_images.dart';

Future<ImageOptions?> showImageSizeDialog(
  BuildContext context, {
  ImageOptions initial = const ImageOptions(),
  bool editing = false,
}) => showDialog<ImageOptions>(
  context: context,
  builder: (_) => _ImageSizeDialog(initial, editing),
);

class _ImageSizeDialog extends StatefulWidget {
  const _ImageSizeDialog(this.initial, this.editing);
  final ImageOptions initial;
  final bool editing;
  @override
  State<_ImageSizeDialog> createState() => _ImageSizeDialogState();
}

class _ImageSizeDialogState extends State<_ImageSizeDialog> {
  late double width = widget.initial.width.toDouble();
  late String align = widget.initial.align;
  late bool rounded = widget.initial.rounded;
  late final caption = TextEditingController(text: widget.initial.caption);
  @override
  void dispose() {
    caption.dispose();
    super.dispose();
  }

  Widget _choices(
    List<({String label, IconData? icon, bool selected, VoidCallback choose})>
    choices,
  ) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: p.codeBg,
        borderRadius: BorderRadius.circular(Rad.lg),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < choices.length; i++) ...[
            if (i != 0) const SizedBox(width: 4),
            Expanded(
              child: Semantics(
                selected: choices[i].selected,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    foregroundColor: choices[i].selected
                        ? p.accent
                        : p.textMuted,
                    backgroundColor: choices[i].selected
                        ? p.accent.withValues(alpha: p.isDark ? .18 : .09)
                        : Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Rad.md),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppTheme.uiFont,
                      fontSize: Fs.small,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: choices[i].choose,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (choices[i].icon != null) ...[
                        Icon(choices[i].icon, size: 16),
                        const SizedBox(width: 6),
                      ],
                      Flexible(child: Text(choices[i].label, maxLines: 1)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _apply() => Navigator.pop(
    context,
    ImageOptions(
      width: width.round(),
      align: align,
      caption: caption.text.trim(),
      rounded: rounded,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final label = TextStyle(
      color: p.text,
      fontSize: Fs.small,
      fontWeight: FontWeight.w600,
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(64, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(
              fontFamily: AppTheme.uiFont,
              fontSize: Fs.small,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        const SizedBox(width: Sp.sm),
        FilledButton(
          style: FilledButton.styleFrom(
            minimumSize: const Size(76, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(
              fontFamily: AppTheme.uiFont,
              fontSize: Fs.small,
              fontWeight: FontWeight.w600,
            ),
          ),
          onPressed: _apply,
          child: Text(context.tr('Apply')),
        ),
      ],
    );
    final remove = TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: p.danger,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(
          fontFamily: AppTheme.uiFont,
          fontSize: Fs.small,
        ),
      ),
      onPressed: () => Navigator.pop(context, const ImageOptions(remove: true)),
      icon: const Icon(Icons.delete_outline_rounded, size: 16),
      label: Text(context.tr('Remove image')),
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Sp.lg,
        vertical: Sp.xl,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                      MediaQuery.viewInsetsOf(context).bottom -
                      48)
                  .clamp(120, 720),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(Rad.md),
                    ),
                    child: Icon(Icons.tune_rounded, size: 18, color: p.accent),
                  ),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Text(
                      context.tr('Image options'),
                      style: TextStyle(
                        color: p.text,
                        fontSize: Fs.dialogTitle,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.close_rounded,
                    tooltip: context.tr('Close'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: p.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr('Width relative to the note'),
                            style: label,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: p.accent.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(Rad.md),
                          ),
                          child: Text(
                            '${width.round()}%',
                            style: label.copyWith(color: p.accent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                        showValueIndicator: ShowValueIndicator.never,
                      ),
                      child: Slider(
                        value: width,
                        min: 10,
                        max: 100,
                        label: '${width.round()}%',
                        onChanged: (v) => setState(() => width = v),
                      ),
                    ),
                    _choices([
                      for (final value in [25, 50, 75, 100])
                        (
                          label: '$value%',
                          icon: null,
                          selected: width.round() == value,
                          choose: () =>
                              setState(() => width = value.toDouble()),
                        ),
                    ]),
                    const SizedBox(height: Sp.xl),
                    Text(context.tr('Image alignment'), style: label),
                    const SizedBox(height: Sp.sm),
                    _choices([
                      for (final entry in [
                        ('left', 'Left', Icons.format_align_left_rounded),
                        ('center', 'Center', Icons.format_align_center_rounded),
                        ('right', 'Right', Icons.format_align_right_rounded),
                      ])
                        (
                          label: context.tr(entry.$2),
                          icon: entry.$3,
                          selected: align == entry.$1,
                          choose: () => setState(() => align = entry.$1),
                        ),
                    ]),
                    const SizedBox(height: Sp.xl),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr('Image caption'),
                            style: label,
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: caption,
                          builder: (_, value, _) => Text(
                            '${value.text.characters.length}/160',
                            style: TextStyle(
                              color: p.textFaint,
                              fontSize: Fs.caption,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Sp.sm),
                    TextField(
                      key: const ValueKey('image-caption'),
                      controller: caption,
                      maxLength: 160,
                      minLines: 2,
                      maxLines: 3,
                      style: TextStyle(color: p.text, fontSize: Fs.body),
                      decoration: InputDecoration(
                        hintText: context.tr('Optional caption'),
                        counterText: '',
                        contentPadding: const EdgeInsets.all(Sp.md),
                      ),
                    ),
                    const SizedBox(height: Sp.lg),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Sp.md,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: p.codeBg,
                        borderRadius: BorderRadius.circular(Rad.lg),
                        border: Border.all(color: p.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.rounded_corner_rounded,
                            color: p.textMuted,
                            size: 18,
                          ),
                          const SizedBox(width: Sp.md),
                          Expanded(
                            child: Text(
                              context.tr('Rounded corners'),
                              style: TextStyle(
                                color: p.text,
                                fontSize: Fs.small,
                              ),
                            ),
                          ),
                          Switch(
                            value: rounded,
                            onChanged: (v) => setState(() => rounded = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Sp.md),
                    Text(
                      context.tr('The image keeps its proportions.'),
                      style: TextStyle(
                        color: p.textMuted,
                        fontSize: Fs.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: p.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (_, constraints) {
                  if (constraints.maxWidth < 345 && widget.editing) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(alignment: Alignment.centerLeft, child: remove),
                        const SizedBox(height: 4),
                        Align(alignment: Alignment.centerRight, child: actions),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      if (widget.editing) remove,
                      const Spacer(),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
