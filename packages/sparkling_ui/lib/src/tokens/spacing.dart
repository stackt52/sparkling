import 'package:flutter/widgets.dart';

/// 4px grid spacing tokens (UX-001 "Spacing").
abstract final class SparklingSpacing {
  static const double unit = 4;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Phone screen gutter.
  static const double gutter = 20;

  /// Admin content gutter.
  static const double adminGutter = 26;

  /// Card padding range 14–20.
  static const double cardPaddingTight = 14;
  static const double cardPadding = 16;
  static const double cardPaddingLoose = 20;

  /// Gap between sibling cards 9–14.
  static const double cardGapTight = 9;
  static const double cardGap = 12;
  static const double cardGapLoose = 14;

  /// Minimum touch target (UX-006). Staff primary actions use [touchTargetStaff].
  static const double touchTarget = 44;
  static const double touchTargetStaff = 48;

  static const EdgeInsets screen = EdgeInsets.symmetric(horizontal: gutter);
  static const EdgeInsets screenAll = EdgeInsets.all(gutter);
  static const EdgeInsets card = EdgeInsets.all(cardPadding);
  static const EdgeInsets cardLoose = EdgeInsets.all(cardPaddingLoose);
  static const EdgeInsets cardTight = EdgeInsets.all(cardPaddingTight);
  static const EdgeInsets chip = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 6,
  );
}
