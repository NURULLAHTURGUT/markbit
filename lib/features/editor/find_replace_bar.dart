import 'package:flutter/material.dart';
import '../../core/l10n/app_strings.dart';
import 'syntax_controller.dart';

List<TextRange> findTextMatches(
  String text,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return [];
  return RegExp(
    RegExp.escape(query),
    caseSensitive: caseSensitive,
  ).allMatches(text).map((m) => TextRange(start: m.start, end: m.end)).toList();
}

class FindReplaceBar extends StatefulWidget {
  const FindReplaceBar({
    super.key,
    required this.controller,
    required this.replace,
    required this.readOnly,
    required this.onNavigate,
    required this.onChanged,
    required this.onClose,
  });
  final SyntaxController controller;
  final bool replace;
  final bool readOnly;
  final ValueChanged<TextRange> onNavigate;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  @override
  State<FindReplaceBar> createState() => _FindReplaceBarState();
}

class _FindReplaceBarState extends State<FindReplaceBar> {
  final _query = TextEditingController();
  final _replacement = TextEditingController();
  final _focus = FocusNode();
  List<TextRange> _matches = [];
  String _lastText = '';
  int _index = 0;
  bool _case = false;
  @override
  void initState() {
    super.initState();
    _lastText = widget.controller.text;
    widget.controller.addListener(_edited);
  }

  void _edited() {
    if (_lastText != widget.controller.text) {
      _lastText = widget.controller.text;
      _search();
    }
  }

  void _search() {
    _matches = findTextMatches(
      widget.controller.text,
      _query.text,
      caseSensitive: _case,
    );
    _index = _matches.isEmpty ? 0 : _index.clamp(0, _matches.length - 1);
    widget.controller.searchQuery = _query.text;
    widget.controller.searchCaseSensitive = _case;
    if (mounted) setState(() {});
  }

  void _navigate(int step) {
    if (_matches.isEmpty) return;
    setState(() => _index = (_index + step) % _matches.length);
    final range = _matches[_index];
    widget.controller.selection = TextSelection(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    widget.onNavigate(range);
    _focus.requestFocus();
  }

  void _replace(bool all) {
    if (_matches.isEmpty || widget.readOnly) return;
    final text = widget.controller.text;
    var next = text;
    final ranges = all ? _matches.reversed : [_matches[_index]];
    for (final range in ranges) {
      next = next.replaceRange(range.start, range.end, _replacement.text);
    }
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: (_matches[_index].start + _replacement.text.length).clamp(
          0,
          next.length,
        ),
      ),
    );
    widget.onChanged();
    _search();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_edited);
    widget.controller.searchQuery = '';
    _query.dispose();
    _replacement.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                autofocus: true,
                focusNode: _focus,
                controller: _query,
                onChanged: (_) {
                  _index = 0;
                  _search();
                  if (_matches.isNotEmpty) _navigate(0);
                },
                onSubmitted: (_) => _navigate(1),
                decoration: InputDecoration(
                  hintText: context.tr('Find in note'),
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              tooltip: context.tr('Match case'),
              isSelected: _case,
              onPressed: () {
                _case = !_case;
                _search();
              },
              icon: const Text('Aa'),
            ),
            Text('${_matches.isEmpty ? 0 : _index + 1}/${_matches.length}'),
            IconButton(
              tooltip: context.tr('Previous match'),
              onPressed: _matches.isEmpty ? null : () => _navigate(-1),
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: context.tr('Next match'),
              onPressed: _matches.isEmpty ? null : () => _navigate(1),
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            IconButton(
              tooltip: context.tr('Close'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        if (widget.replace && !widget.readOnly) ...[
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (_, constraints) => Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth > 450
                      ? constraints.maxWidth - 225
                      : constraints.maxWidth,
                  child: TextField(
                    controller: _replacement,
                    onSubmitted: (_) => _replace(false),
                    decoration: InputDecoration(
                      hintText: context.tr('Replace with'),
                      isDense: true,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _matches.isEmpty ? null : () => _replace(false),
                  child: Text(context.tr('Replace')),
                ),
                TextButton(
                  onPressed: _matches.isEmpty ? null : () => _replace(true),
                  child: Text(context.tr('Replace all')),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}
