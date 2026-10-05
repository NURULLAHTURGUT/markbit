import '../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_icon_button.dart';
import '../../data/models/note.dart';
import '../../domain/markdown_utils.dart';

/// Table of contents + backlinks for the open note.
class OutlinePanel extends ConsumerWidget {
  const OutlinePanel({
    super.key,
    required this.note,
    required this.body,
    required this.onJump,
    required this.onOpenNote,
    required this.onClose,
  });

  final Note note;
  final String body;
  final void Function(int line) onJump;
  final void Function(String id) onOpenNote;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final headings = extractHeadings(body);
    final backlinks = ref.watch(libraryProvider).backlinksTo(note);
    final minLevel = headings.isEmpty
        ? 1
        : headings.map((h) => h.level).reduce((a, b) => a < b ? a : b);

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: p.listBg,
        border: Border(left: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Sp.lg, right: Sp.xs),
            child: Row(
              children: [
                Text(
                  context.tr('Outline'),
                  style: TextStyle(
                    color: p.text,
                    fontWeight: FontWeight.w700,
                    fontSize: Fs.body,
                  ),
                ),
                const Spacer(),
                AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: context.tr('Close outline'),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: Sp.lg),
              children: [
                if (headings.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(Sp.lg),
                    child: Text(
                      context.tr('Add headings with # to build an outline.'),
                      style: TextStyle(color: p.textFaint, fontSize: Fs.small),
                    ),
                  ),
                for (final h in headings)
                  InkWell(
                    borderRadius: BorderRadius.circular(Rad.md),
                    onTap: () => onJump(h.line),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        Sp.lg + (h.level - minLevel) * 12,
                        7,
                        Sp.md,
                        7,
                      ),
                      child: Text(
                        h.text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: h.level == minLevel ? p.text : p.textMuted,
                          fontSize: Fs.small,
                          fontWeight: h.level == minLevel
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                if (backlinks.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Sp.lg,
                      Sp.xl,
                      Sp.lg,
                      Sp.xs,
                    ),
                    child: Text(
                      context.tr('LINKED FROM'),
                      style: TextStyle(
                        color: p.sectionLabel,
                        fontSize: Fs.caption,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  for (final n in backlinks)
                    InkWell(
                      borderRadius: BorderRadius.circular(Rad.md),
                      onTap: () => onOpenNote(n.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Sp.lg,
                          vertical: 7,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.north_west_rounded,
                              size: 13,
                              color: p.textFaint,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                n.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: p.accent,
                                  fontSize: Fs.small,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
