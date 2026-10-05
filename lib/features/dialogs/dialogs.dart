import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_notification.dart';
import '../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';

/// Shows a compact notification at the top of the window.
void showToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  AppNotifications.show(
    context,
    message,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// Single-line text prompt. Returns `null` when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirmLabel = 'Save',
  IconData icon = Icons.edit_outlined,
}) {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = controller.text.trim();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return AppDialog(
        icon: icon,
        title: title,
        width: 420,
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          const DialogCancelButton(),
          FilledButton(onPressed: submit, child: Text(ctx.tr(confirmLabel))),
        ],
      );
    },
  );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final p = ctx.palette;
      return AppDialog(
        icon: destructive
            ? Icons.warning_amber_rounded
            : Icons.help_outline_rounded,
        iconColor: destructive ? p.danger : p.accent,
        title: title,
        width: 420,
        content: Text(
          message,
          style: TextStyle(color: p.textMuted, fontSize: Fs.body, height: 1.5),
        ),
        actions: [
          const DialogCancelButton(result: false),
          FilledButton(
            autofocus: true,
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: p.danger,
                    foregroundColor: Colors.white,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr(confirmLabel)),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Section title used inside dialogs/panels.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Sp.lg, bottom: Sp.sm),
    child: Text(
      context.tr(text).toUpperCase(),
      style: TextStyle(
        color: context.palette.sectionLabel,
        fontSize: Fs.caption,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    ),
  );
}
