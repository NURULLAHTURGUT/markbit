import 'package:flutter/animation.dart';

/// Spacing scale (4pt rhythm).
abstract final class Sp {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii.
abstract final class Rad {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 16;
  static const double pill = 999;
}

/// Motion tokens. Keep every micro-interaction in the 120-260ms range.
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 260);
  static const Curve curve = Curves.easeOutCubic;
}

/// Type scale.
abstract final class Fs {
  static const double micro = 10.5;
  static const double caption = 11.5;
  static const double small = 12.5;
  static const double label = 13.5;
  static const double body = 14;
  static const double title = 16;
  static const double dialogTitle = 17;
  static const double heading = 18;
  static const double headline = 24;
}

/// Responsive breakpoints (logical pixels).
abstract final class Breakpoints {
  static const double compact = 720; // below: single pane (phone)
  static const double medium = 1040; // below: list + editor, sidebar in drawer
}
