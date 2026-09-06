import 'package:flutter/material.dart';

/// Centralized border radius scale for Expense Tracker.
class AppRadius {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double pillDouble = 999.0;

  // Component Radii
  static const Radius cardRadius = Radius.circular(lg);
  static const Radius buttonRadius = Radius.circular(md);
  static const Radius inputRadius = Radius.circular(md);
  static const Radius modalRadius = Radius.circular(xl);
  static const Radius chipRadius = Radius.circular(sm);
  static const Radius badgeRadius = Radius.circular(xs);

  // BorderRadius helpers
  static const BorderRadius card = BorderRadius.all(cardRadius);
  static const BorderRadius button = BorderRadius.all(buttonRadius);
  static const BorderRadius input = BorderRadius.all(inputRadius);
  static const BorderRadius chip = BorderRadius.all(chipRadius);
  static const BorderRadius pill = BorderRadius.all(
    Radius.circular(pillDouble),
  );
  static const BorderRadius pillBorderRadius = pill;
  static const BorderRadius modalTop = BorderRadius.only(
    topLeft: Radius.circular(xl),
    topRight: Radius.circular(xl),
  );
}
