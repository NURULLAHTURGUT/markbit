import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Small rounded label tinted with the tag colour.
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.label,
    required this.color,
    this.onTap,
    this.onRemove,
    this.dense = true,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Lighten on dark backgrounds, darken on light ones, to keep 4.5:1 text.
    final fg = isDark
        ? Color.lerp(color, Colors.white, 0.35)!
        : Color.lerp(color, Colors.black, 0.25)!;

    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 1.5 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(Rad.pill),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: dense ? Fs.caption : Fs.small,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(Rad.md),
              child: Icon(Icons.close_rounded, size: 13, color: fg),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return chip;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: chip),
    );
  }
}
