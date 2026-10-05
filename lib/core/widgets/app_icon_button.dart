import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/tokens.dart';

/// Compact icon button with a proper hit target (44dp on touch platforms,
/// 34dp with pointer input), hover/press feedback and a tooltip that doubles
/// as the accessibility label.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 18,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final platform = Theme.of(context).platform;
    final touch =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final box = touch ? 44.0 : 34.0;
    final enabled = onPressed != null;
    final fg =
        color ??
        (active
            ? p.accent
            : (enabled ? p.textMuted : p.textFaint.withValues(alpha: 0.5)));

    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active ? p.accent.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(Rad.md),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(Rad.md),
            child: AnimatedContainer(
              duration: Motion.fast,
              width: box,
              height: box,
              alignment: Alignment.center,
              child: Icon(icon, size: size, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}
