import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_icon_button.dart';

/// The single card used by every modal in the app: a header with an accent
/// icon tile, title, optional subtitle and close button; a padded body; and
/// a footer with compact, consistently styled actions.
///
/// Keeping all dialogs on this one widget is what makes them look like part
/// of the same product instead of a mix of Material defaults.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.content,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.actions = const [],
    this.footerLeading,
    this.headerActions = const [],
    this.width = 440,
    this.height,
    this.maxHeight,
    this.scrollable = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xl),
    this.showClose = true,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? content;

  /// Footer buttons, right aligned. The last one is the primary action.
  final List<Widget> actions;

  /// Optional widget shown on the left of the footer (e.g. a destructive
  /// "Remove" action or a status text).
  final Widget? footerLeading;

  /// Extra icon buttons shown in the header before the close button.
  final List<Widget> headerActions;

  /// Preferred width; shrinks on narrow windows.
  final double width;

  /// Fixed body+chrome height (for list / split layouts). When null the
  /// dialog hugs its content up to [maxHeight].
  final double? height;
  final double? maxHeight;

  /// Wraps [content] in a scroll view. Disable for content that manages its
  /// own scrolling (lists with `Expanded`, split panes).
  final bool scrollable;
  final EdgeInsets bodyPadding;
  final bool showClose;
  final VoidCallback? onClose;

  /// Compact button styling shared by dialog footers.
  static ThemeData footerTheme(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    const text = TextStyle(
      fontFamily: AppTheme.uiFont,
      fontSize: Fs.small,
      fontWeight: FontWeight.w600,
    );
    const pad = EdgeInsets.symmetric(horizontal: 14);
    const size = Size(64, 36);
    ButtonStyle merge(ButtonStyle compact, ButtonStyle? base) =>
        base == null ? compact : compact.merge(base);
    return theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: merge(
          FilledButton.styleFrom(
            minimumSize: size,
            padding: pad,
            textStyle: text,
            iconSize: 16,
          ),
          theme.filledButtonTheme.style,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: merge(
          OutlinedButton.styleFrom(
            minimumSize: size,
            padding: pad,
            textStyle: text,
            iconSize: 16,
          ),
          theme.outlinedButtonTheme.style,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: merge(
          TextButton.styleFrom(
            foregroundColor: p.textMuted,
            minimumSize: size,
            padding: pad,
            textStyle: text,
            iconSize: 16,
          ),
          theme.textButtonTheme.style,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final media = MediaQuery.of(context);
    final available =
        media.size.height - media.viewInsets.bottom - media.padding.vertical;
    final double ceiling = (available - 48).clamp(160.0, double.infinity);
    final double limit = (maxHeight ?? 760.0).clamp(160.0, ceiling);
    final tint = iconColor ?? p.accent;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.md, Sp.lg),
      child: Row(
        crossAxisAlignment: subtitle == null
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: p.isDark ? .16 : .10),
                borderRadius: BorderRadius.circular(Rad.md),
              ),
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: Sp.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.text,
                    fontSize: Fs.dialogTitle,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: p.textMuted,
                      fontSize: Fs.small,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...headerActions,
          if (showClose)
            AppIconButton(
              icon: Icons.close_rounded,
              tooltip: context.tr('Close'),
              onPressed: onClose ?? () => Navigator.maybePop(context),
            ),
        ],
      ),
    );

    Widget? body;
    if (content != null) {
      body = scrollable
          ? SingleChildScrollView(padding: bodyPadding, child: content)
          : Padding(padding: bodyPadding, child: content);
      body = height != null ? Expanded(child: body) : Flexible(child: body);
    }

    final hasFooter = actions.isNotEmpty || footerLeading != null;
    final footer = hasFooter
        ? Theme(
            data: footerTheme(context),
            child: Container(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  p.isDark
                      ? Colors.black.withValues(alpha: .10)
                      : Colors.black.withValues(alpha: .018),
                  p.surface,
                ),
                border: Border(top: BorderSide(color: p.border)),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: Sp.lg,
                vertical: Sp.md,
              ),
              child: Row(
                children: [
                  if (footerLeading != null) ...[
                    Flexible(child: footerLeading!),
                    const SizedBox(width: Sp.sm),
                  ],
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Sp.sm,
                      runSpacing: Sp.sm,
                      children: actions,
                    ),
                  ),
                ],
              ),
            ),
          )
        : null;

    final dialog = Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: Sp.lg,
        vertical: Sp.xl,
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height?.clamp(160.0, limit),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: limit),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Divider(height: 1, color: p.border),
              ?body,
              ?footer,
            ],
          ),
        ),
      ),
    );
    // Plays once when the dialog opens; the route itself fades it in.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .96, end: 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.normal,
      curve: Motion.curve,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: dialog,
    );
  }
}

/// Muted secondary "Cancel"-style footer button.
class DialogCancelButton extends StatelessWidget {
  const DialogCancelButton({super.key, this.label = 'Cancel', this.result});
  final String label;
  final Object? result;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => Navigator.pop(context, result),
    child: Text(context.tr(label)),
  );
}

/// Small uppercase label used to title a group of fields in a dialog.
class DialogLabel extends StatelessWidget {
  const DialogLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: p.text,
                fontSize: Fs.small,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Selectable row used by list-style pickers inside dialogs.
class DialogListItem extends StatelessWidget {
  const DialogListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.titleStyle,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? p.selection : Colors.transparent,
        borderRadius: BorderRadius.circular(Rad.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Rad.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sp.md,
              vertical: Sp.sm + 1,
            ),
            child: Row(
              children: [
                if (leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(
                      size: 18,
                      color: selected ? p.accent : p.textMuted,
                    ),
                    child: leading!,
                  ),
                  const SizedBox(width: Sp.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DefaultTextStyle.merge(
                        style: TextStyle(
                          color: p.text,
                          fontSize: Fs.body,
                          fontWeight: FontWeight.w500,
                        ).merge(titleStyle),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        child: title,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        DefaultTextStyle.merge(
                          style: TextStyle(
                            color: p.textFaint,
                            fontSize: Fs.small,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          child: subtitle!,
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: Sp.sm),
                  trailing!,
                ] else if (selected)
                  Icon(Icons.check_rounded, size: 18, color: p.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered empty / loading / error message for dialog bodies.
class DialogEmptyState extends StatelessWidget {
  const DialogEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.loading = false,
  });
  final String message;
  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            else
              Icon(icon, size: 28, color: p.textFaint),
            const SizedBox(height: Sp.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: p.textMuted,
                fontSize: Fs.small,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
