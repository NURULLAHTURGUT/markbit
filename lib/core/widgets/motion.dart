import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Fades (and optionally slides) its child in once, when it is first built.
///
/// Give it a key that changes with the content (a note id, a view mode) to
/// replay the entrance. Unlike an [AnimatedSwitcher] the old child is
/// removed at once, so subtrees with global keys or heavy state are never
/// built twice.
class FadeIn extends StatefulWidget {
  const FadeIn({
    super.key,
    required this.child,
    this.from = 0,
    this.offset = Offset.zero,
    this.duration = Motion.normal,
  });

  final Widget child;

  /// Starting opacity; above zero for a subtle refresh of mostly the same
  /// content.
  final double from;

  /// Starting offset as a fraction of the child's size.
  final Offset offset;
  final Duration duration;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.curve,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = FadeTransition(
      opacity: _curve.drive(Tween(begin: widget.from, end: 1.0)),
      child: widget.child,
    );
    if (widget.offset != Offset.zero) {
      child = SlideTransition(
        position: _curve.drive(Tween(begin: widget.offset, end: Offset.zero)),
        child: child,
      );
    }
    return child;
  }
}

/// Smoothly expands or collapses [child] vertically. While collapsed (and
/// after the animation) the child is not built.
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.normal,
    value: widget.visible ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Motion.curve,
  );

  @override
  void didUpdateWidget(Reveal old) {
    super.didUpdateWidget(old);
    if (old.visible == widget.visible) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isDismissed) return const SizedBox(width: double.infinity);
    return SizeTransition(
      sizeFactor: _curve,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _curve, child: widget.child),
    );
  }
}
