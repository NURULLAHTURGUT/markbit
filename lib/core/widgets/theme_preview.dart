import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/tokens.dart';

/// A miniature of the app (sidebar, note list, editor) drawn in [palette],
/// so theme cards show how the theme will actually look.
class ThemePreview extends StatelessWidget {
  const ThemePreview(this.palette, {super.key});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final pal = palette;
    Widget line(Color color, double width, {double height = 4}) => Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Rad.pill),
      ),
    );
    final backdrop = pal.isGlass
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: pal.isDark
                ? const [Color(0xFF29333D), Color(0xFF17232E)]
                : const [Color(0xFFDCECF5), Color(0xFFC2D4E8)],
          )
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: backdrop,
        color: backdrop == null ? pal.editorBg : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 30,
            color: pal.sidebarBg,
            padding: const EdgeInsets.fromLTRB(5, 8, 5, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line(pal.accent, 16),
                line(pal.textFaint.withValues(alpha: .6), 18),
                line(pal.textFaint.withValues(alpha: .6), 14),
                line(pal.textFaint.withValues(alpha: .6), 17),
              ],
            ),
          ),
          Container(
            width: 42,
            color: pal.listBg,
            padding: const EdgeInsets.fromLTRB(5, 8, 5, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 18,
                  margin: const EdgeInsets.only(bottom: 5),
                  decoration: BoxDecoration(
                    color: pal.selection,
                    borderRadius: BorderRadius.circular(Rad.xs),
                  ),
                ),
                line(pal.text.withValues(alpha: .55), 26),
                line(pal.textFaint.withValues(alpha: .5), 30),
                line(pal.text.withValues(alpha: .55), 22),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: pal.isGlass ? null : pal.editorBg,
              padding: const EdgeInsets.fromLTRB(7, 9, 6, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(pal.text, 34, height: 6),
                  line(pal.textMuted.withValues(alpha: .6), 48),
                  line(pal.textMuted.withValues(alpha: .6), 40),
                  Row(
                    children: [
                      line(pal.synKeyword, 12),
                      const SizedBox(width: 3),
                      line(pal.synString, 18),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 20,
                      height: 9,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: pal.accent,
                        borderRadius: BorderRadius.circular(Rad.xs),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .62, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width * .38, size.height)
    ..close();

  @override
  bool shouldReclip(DiagonalClipper oldClipper) => false;
}
