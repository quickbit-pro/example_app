import 'package:flutter/widgets.dart';

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;

  static const EdgeInsets screenPadding = EdgeInsets.fromLTRB(md, sm, md, lg);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
}

/// Neo-banking radii: large, soft. Cards = lg (20), pills = pill (999).
/// `sm` and `md` kept as legacy aliases so existing screens don't break.
abstract final class AppRadii {
  static const double xs = 8;
  static const double sm = 14; // inputs
  static const double md = 18; // buttons
  static const double lg = 22; // cards
  static const double xl = 28; // hero cards
  static const double pill = 999;
}
