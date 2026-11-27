import 'package:flutter/material.dart';

/// OnlineDost.app theme.
/// Orange (#FF7C4D) primary, white/light cards, rounded 16px corners.
class AppTheme {
  // Surfaces — light cards on a soft dark background
  static const Color bg = Color(0xFF121212);
  static const Color card = Color(0xFFFFFFFF);      // white cards
  static const Color cardAlt = Color(0xFFF5F5F5);
  static const Color border = Color(0xFFE0E0E0);

  // Brand colours
  static const Color primary = Color(0xFFFF7C4D);   // orange
  static const Color primaryDark = Color(0xFFE86B3A);
  static const Color accent = Color(0xFFFF9B6E);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFFF7C4D), Color(0xFFFF9B6E)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const Color success = Color(0xFF00B894);
  static const Color warning = Color(0xFFFDCB6E);
  static const Color danger = Color(0xFFE17055);
  static const Color textMain = Color(0xDDFFFFFF);
  static const Color textMuted = Color(0xFFB4A3C7);

  // Dating brand gradient (pink → orange) — usable anywhere a
  // highlight gradient is needed.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFFF7C4D), Color(0xFFFF9B6E)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primaryDark,
        surface: card,
        error: danger,
      ),
      cardColor: card,
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textMain,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bg,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardAlt,
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cardAlt,
        contentTextStyle: TextStyle(color: textMain),
      ),
    );
  }
}
