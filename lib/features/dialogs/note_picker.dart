import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_dialog.dart';

Future<List<String>?> pickNotes(
  BuildContext context, {
  List<String> selected = const [],
  String? exclude,
}) => showDialog<List<String>>(
  context: context,
  builder: (_) => NotePicker(selected: selected, exclude: exclude),
);

class NotePicker extends ConsumerStatefulWidget {
  const NotePicker({super.key, required this.selected, this.exclude});
  final List<String> selected;
  final String? exclude;
  @override
  ConsumerState<NotePicker> createState() => _NotePickerState();
}

class _NotePickerState extends ConsumerState<NotePicker> {
  late final Set<String> _selected = widget.selected.toSet();
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final notes =
        lib.notes.values
            .where(
              (n) =>
                  !n.trashed &&
                  n.id != widget.exclude &&
                  n.displayTitle.toLowerCase().contains(_query),
            )
            .toList()
          ..sort((a, b) => a.displayTitle.compareTo(b.displayTitle));
    final p = context.palette;
    return AppDialog(
      icon: Icons.library_books_outlined,
      title: context.tr('Choose source notes'),
      subtitle: context.tr('Up to 8 notes. Only selected sources are sent.'),
      width: 540,
      height: 560,
      scrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: p.textMuted,
              ),
              hintText: context.tr('Search your notes'),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Expanded(
            child: notes.isEmpty
                ? DialogEmptyState(
                    icon: Icons.search_off_rounded,
                    message: context.tr('No results'),
                  )
                : ListView.builder(
                    itemCount: notes.length,
                    itemBuilder: (ctx, i) {
                      final n = notes[i];
                      final checked = _selected.contains(n.id);
                      void toggle() => setState(() {
                        if (!checked) {
                          if (_selected.length < 8) _selected.add(n.id);
                        } else {
                          _selected.remove(n.id);
                        }
                      });
                      return DialogListItem(
                        selected: checked,
                        leading: SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: checked,
                            onChanged: (_) => toggle(),
                          ),
                        ),
                        title: Text(n.displayTitle),
                        subtitle: Text(lib.notebookPath(n.notebookId)),
                        trailing: const SizedBox.shrink(),
                        onTap: toggle,
                      );
                    },
                  ),
          ),
        ],
      ),
      footerLeading: Text(
        '${_selected.length}/8',
        style: TextStyle(color: p.textFaint, fontSize: Fs.small),
      ),
      actions: [
        const DialogCancelButton(),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected.toList()),
          child: Text(context.tr('Apply')),
        ),
      ],
    );
  }
}
