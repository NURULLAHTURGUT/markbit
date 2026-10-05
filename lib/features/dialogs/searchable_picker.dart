import 'package:flutter/material.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';

class PickerOption<T> {
  const PickerOption(this.value, this.label, {this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

Future<T?> showSearchablePicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  PickerOption<T>? action,
}) => showDialog<T>(
  context: context,
  builder: (_) => _Picker<T>(
    title: title,
    options: options,
    selected: selected,
    action: action,
  ),
);

class _Picker<T> extends StatefulWidget {
  const _Picker({
    required this.title,
    required this.options,
    this.selected,
    this.action,
  });
  final String title;
  final List<PickerOption<T>> options;
  final T? selected;
  final PickerOption<T>? action;
  @override
  State<_Picker<T>> createState() => _PickerState<T>();
}

class _PickerState<T> extends State<_Picker<T>> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final matches = widget.options
        .where(
          (option) =>
              option.label.toLowerCase().contains(_query.trim().toLowerCase()),
        )
        .toList();
    return AppDialog(
      icon: Icons.manage_search_rounded,
      title: widget.title,
      width: 440,
      height: (widget.options.length * 42.0 + 230).clamp(300.0, 540.0),
      scrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: context.tr('Search'),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: p.textMuted,
              ),
            ),
            onChanged: (value) => setState(() => _query = value),
            onSubmitted: (_) {
              if (matches.length == 1) {
                Navigator.pop(context, matches.first.value);
              }
            },
          ),
          const SizedBox(height: Sp.sm),
          Expanded(
            child: matches.isEmpty
                ? DialogEmptyState(
                    icon: Icons.search_off_rounded,
                    message: context.tr('No results'),
                  )
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final option = matches[index];
                      return DialogListItem(
                        selected: option.value == widget.selected,
                        leading: option.icon == null ? null : Icon(option.icon),
                        title: Text(option.label),
                        onTap: () => Navigator.pop(context, option.value),
                      );
                    },
                  ),
          ),
        ],
      ),
      footerLeading: widget.action == null
          ? null
          : TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: p.accent),
              onPressed: () => Navigator.pop(context, widget.action!.value),
              icon: Icon(widget.action!.icon ?? Icons.add_rounded, size: 16),
              label: Text(widget.action!.label),
            ),
      actions: const [DialogCancelButton()],
    );
  }
}
