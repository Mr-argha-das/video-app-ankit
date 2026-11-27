import 'package:flutter/material.dart';

import 'app_theme_orange.dart' as orange;
import 'app_theme_dating.dart' as dating;
import '../config/app_flavor.dart';

/// Wrapper theme — flavor ke hisaab se sahi theme return karta hai.
///
/// Static const fields are orange theme values (usable in const contexts).
/// The [dark] getter switches flavors at runtime for ThemeData.
class AppTheme {
  // Orange theme const values (usable in const contexts)
  static const Color primary = Color(0xFFFF7C4D);
  static const Color primaryDark = Color(0xFFE86B3A);
  static const Color accent = Color(0xFFFF9B6E);
  static const Color success = Color(0xFF00B894);
  static const Color warning = Color(0xFFFDCB6E);
  static const Color danger = Color(0xFFE17055);
  static const Color textMain = Color(0xDDFFFFFF);
  static const Color textMuted = Color(0xFFB4A3C7);
  static const Color bg = Color(0xFF121212);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardAlt = Color(0xFFF5F5F5);
  static const Color border = Color(0xFFE0E0E0);
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFFF7C4D), Color(0xFFFF9B6E)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  /// Dating-specific colors (not const, used at runtime)
  static const Color purple = Color(0xFF9B5CF6);

  /// ThemeData — flavor ke hisaab se sahi theme return karta hai (runtime).
  static ThemeData get dark {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.dark;
      case AppFlavor.dating:
        return dating.AppThemeDating.dark;
    }
  }
}
