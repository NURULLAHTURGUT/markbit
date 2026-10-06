import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';

/// The launch animation, shown over the app on every start: the logo tile
/// appears, three pages slide in, the code brackets draw themselves, the
/// star spins in, a light sweeps across, then the name and a loading line
/// rise below. It fades away to reveal the app; a click skips it.
/// Reduced-motion settings skip it entirely.
class SplashOverlay extends StatefulWidget {
  const SplashOverlay({super.key, required this.child});
  final Widget child;

  /// Animation (3.4 s) plus the fade to the app (0.35 s).
  static const duration = Duration(milliseconds: 3750);

  @override
  State<SplashOverlay> createState() => _SplashOverlayState();
}

/// Seconds on the animation timeline.
const double _total = 3.75;
const double _fadeStart = 3.4;

class _SplashOverlayState extends State<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SplashOverlay.duration,
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_done || _controller.isAnimating) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _done = true;
    } else {
      _controller.forward();
    }
  }

  /// Jumps to the fade-out.
  void _skip() {
    final fade = _fadeStart / _total;
    if (_controller.value < fade) _controller.forward(from: fade);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final dark = context.palette.isDark;
    final colors = _SplashColors(dark);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * _total;
            final fade = _progress(t, _fadeStart, _total - _fadeStart);
            return Opacity(
              opacity: 1 - Curves.easeIn.transform(fade),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skip,
                // A Material (not a plain colour) gives the text a proper
                // style: the splash sits above the app's own Material.
                child: Material(
                  color: colors.bg,
                  child: _SplashContent(t: t, colors: colors),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SplashColors {
  _SplashColors(bool dark)
    : bg = dark ? const Color(0xFF050506) : const Color(0xFFF2F2F4),
      fg = dark ? const Color(0xFFF4F4F6) : const Color(0xFF0C0C0E),
      muted = dark ? const Color(0xFF8A8A93) : const Color(0xFF77777F),
      tileEdge = dark ? const Color(0xFF26262B) : const Color(0xFF1D1D20),
      track = dark ? const Color(0xFF1E1E22) : const Color(0xFFDCDCE0);
  final Color bg, fg, muted, tileEdge, track;
}

// Easing curves of the original animation.
const _outExpo = Cubic(.22, 1, .36, 1);
const _spring = Cubic(.34, 1.4, .64, 1);
const _springStrong = Cubic(.34, 1.56, .64, 1);
const _inOut = Cubic(.65, 0, .35, 1);
const _sweep = Cubic(.45, 0, .2, 1);

/// Linear 0–1 progress of a step that starts at [start] and lasts [length].
double _progress(double t, double start, double length) =>
    ((t - start) / length).clamp(0.0, 1.0);

double _eased(double t, double start, double length, Curve curve) =>
    curve.transform(_progress(t, start, length));

class _SplashContent extends StatelessWidget {
  const _SplashContent({required this.t, required this.colors});
  final double t;
  final _SplashColors colors;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final icon = [size.width * .56, size.height * .46, 260.0].reduce(math.min);
    final nameFontSize = (size.width * .06).clamp(26.0, 34.0);
    Widget rise(double start, Widget child) {
      final v = _eased(t, start, .8, _outExpo);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - v)),
          child: child,
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: icon,
            child: CustomPaint(painter: _LogoPainter(t, colors)),
          ),
          const SizedBox(height: 28),
          rise(
            1.7,
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Mark'),
                  TextSpan(
                    text: 'bit',
                    style: TextStyle(
                      color: colors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              style: TextStyle(
                fontFamily: AppTheme.uiFont,
                color: colors.fg,
                fontSize: nameFontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -.02 * nameFontSize,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 14),
          rise(
            1.85,
            Container(
              width: 120,
              height: 3,
              decoration: BoxDecoration(
                color: colors.track,
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _eased(t, 2, 1.4, _inOut),
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.fg,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the Markbit logo (a 1000 × 1000 design) at time [t] seconds.
class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t, this.colors);
  final double t;
  final _SplashColors colors;

  static const _paper = Color(0xFFFFFFFF);
  static const _paper2 = Color(0xFFEFEFF1);
  static const _paper3 = Color(0xFFE3E3E6);
  static const _ink = Color(0xFF111113);

  static final _tile = RRect.fromRectAndRadius(
    const Rect.fromLTWH(20, 20, 960, 960),
    const Radius.circular(230),
  );

  static final _frontPaper = Path()
    ..moveTo(-250, -340)
    ..lineTo(250, -340)
    ..quadraticBezierTo(305, -340, 305, -285)
    ..lineTo(305, 200)
    ..lineTo(170, 335)
    ..lineTo(-250, 335)
    ..quadraticBezierTo(-305, 335, -305, 280)
    ..lineTo(-305, -285)
    ..quadraticBezierTo(-305, -340, -250, -340)
    ..close();

  static final _fold = Path()
    ..moveTo(305, 200)
    ..cubicTo(255, 194, 205, 206, 196, 252)
    ..cubicTo(189, 290, 183, 318, 170, 335)
    ..close();

  static final _star = Path()
    ..moveTo(0, -66)
    ..cubicTo(7, -18, 18, -7, 66, 0)
    ..cubicTo(18, 7, 7, 18, 0, 66)
    ..cubicTo(-7, 18, -18, 7, -66, 0)
    ..cubicTo(-18, -7, -7, -18, 0, -66)
    ..close();

  static final _bracketLeft = Path()
    ..moveTo(-55, -75)
    ..lineTo(-140, 15)
    ..lineTo(-55, 105);
  static final _bracketRight = Path()
    ..moveTo(40, -75)
    ..lineTo(125, 15)
    ..lineTo(40, 105);

  /// Runs [draw] with [opacity] applied to everything it paints.
  void _faded(Canvas canvas, double opacity, VoidCallback draw) {
    if (opacity <= 0) return;
    if (opacity >= 1) {
      draw();
      return;
    }
    canvas.saveLayer(
      null,
      Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    draw();
    canvas.restore();
  }

  /// A drop shadow like SVG feDropShadow, then the shape itself.
  void _shadowed(
    Canvas canvas,
    Path path,
    Paint paint, {
    Offset offset = const Offset(-6, 14),
    double blur = 16,
    double opacity = .45,
  }) {
    canvas.drawPath(
      path.shift(offset),
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..style = paint.style
        ..strokeWidth = paint.strokeWidth
        ..strokeCap = paint.strokeCap
        ..strokeJoin = paint.strokeJoin
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.drawPath(path, paint);
  }

  /// A page sliding up into place inside its own rotated frame.
  void _page(
    Canvas canvas, {
    required Offset at,
    required double angle,
    required double start,
    required Rect rect,
    required Color color,
  }) {
    final v = _eased(t, start, .9, _outExpo);
    _faded(canvas, v, () {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle * math.pi / 180);
      canvas.translate(0, 110 * (1 - v));
      final s = .9 + .1 * v;
      canvas.scale(s);
      _shadowed(
        canvas,
        Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(52))),
        Paint()..color = color,
      );
      canvas.restore();
    });
  }

  void _bracket(Canvas canvas, Path path, double start) {
    final v = _eased(t, start, .7, _inOut);
    if (v <= 0) return;
    final metric = path.computeMetrics().first;
    final drawn = metric.extractPath(0, metric.length * v);
    _shadowed(
      canvas,
      drawn,
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 50
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
      offset: const Offset(0, 6),
      blur: 6,
      opacity: .22,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1000);

    // Tile.
    final tileV = _eased(t, 0, .9, _outExpo);
    _faded(canvas, tileV, () {
      canvas.save();
      canvas.translate(500, 500);
      canvas.scale(.72 + .28 * tileV);
      canvas.translate(-500, -500);
      canvas.drawRRect(
        _tile,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF141416), Color(0xFF0B0B0C), Color(0xFF151517)],
            stops: [0, .55, 1],
          ).createShader(_tile.outerRect),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(21, 21, 958, 958),
          const Radius.circular(229),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = colors.tileEdge.withValues(alpha: .6),
      );
      canvas.restore();
    });

    // Everything else stays inside the tile.
    canvas.save();
    canvas.clipRRect(_tile);

    _page(
      canvas,
      at: const Offset(375, 610),
      angle: -7,
      start: .30,
      rect: const Rect.fromLTWH(-215, -295, 430, 590),
      color: _paper3,
    );
    _page(
      canvas,
      at: const Offset(455, 570),
      angle: -5,
      start: .42,
      rect: const Rect.fromLTWH(-235, -325, 470, 650),
      color: _paper2,
    );

    // Front page: slides up and straightens, then gets its details.
    final front = _eased(t, .54, 1, _outExpo);
    _faded(canvas, front, () {
      canvas.save();
      canvas.translate(590, 520);
      canvas.rotate(4 * math.pi / 180);
      canvas.translate(0, 130 * (1 - front));
      canvas.rotate(-9 * (1 - front) * math.pi / 180);
      canvas.scale(.9 + .1 * front);

      _shadowed(canvas, _frontPaper, Paint()..color = _paper);

      // Curled corner, springing out from the bottom-right.
      final fold = _eased(t, 1.05, .7, _spring);
      if (fold > 0) {
        canvas.save();
        canvas.translate(305, 335);
        canvas.scale(fold);
        canvas.translate(-305, -335);
        _shadowed(
          canvas,
          _fold,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFFFFF), Color(0xFFCFCFD3)],
            ).createShader(_fold.getBounds()),
          offset: const Offset(0, 6),
          blur: 6,
          opacity: .22,
        );
        canvas.restore();
      }

      _bracket(canvas, _bracketLeft, 1.05);
      _bracket(canvas, _bracketRight, 1.18);

      // Star spins in.
      final star = _eased(t, 1.45, .8, _springStrong);
      final starOpacity = _progress(t, 1.45, .8);
      _faded(canvas, starOpacity, () {
        canvas.save();
        canvas.translate(205, -205);
        canvas.rotate(-120 * (1 - star) * math.pi / 180);
        canvas.scale(math.max(0, star));
        _shadowed(
          canvas,
          _star,
          Paint()..color = _ink,
          offset: const Offset(0, 6),
          blur: 6,
          opacity: .22,
        );
        canvas.restore();
      });
      canvas.restore();
    });

    // Light sweep.
    final sweep = _eased(t, 1.7, 1.3, _sweep);
    if (sweep > 0 && sweep < 1) {
      canvas.save();
      canvas.translate(500, 500);
      canvas.rotate(20 * math.pi / 180);
      canvas.translate(-500, -500);
      final rect = Rect.fromLTWH(-200 + (-900 + 1800 * sweep), -200, 260, 1400);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0x38FFFFFF), Color(0x00FFFFFF)],
          ).createShader(rect),
      );
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.t != t || old.colors != colors;
}
