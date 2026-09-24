import 'package:flutter/material.dart';

/// Dark theme — dating-app colour palette (Tinder-style pink/orange)
/// applied on the ORIGINAL layout. Same constant names as before,
/// only the colour values changed.
class AppTheme {
  // Warm plum-dark surfaces (dating vibe)
  static const Color bg = Color(0xFF170F1F);
  static const Color card = Color(0xFF241A30);
  static const Color cardAlt = Color(0xFF2F2340);
  static const Color border = Color(0xFF4A3558);

  // Brand colours — pink → orange (Tinder feel), soft purple secondary
  static const Color primary = Color(0xFFFE3C72);
  static const Color purple = Color(0xFF9B5CF6);
  static const Color accent = Color(0xFFFF7854);

  static const Color success = Color(0xFF00B894);
  static const Color warning = Color(0xFFFDCB6E);
  static const Color danger = Color(0xFFE17055);
  static const Color textMain = Color(0xDDFFFFFF);
  static const Color textMuted = Color(0xFFB4A3C7);

  // Dating brand gradient (pink → orange) — usable anywhere a
  // highlight gradient is needed.
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFFD297B), Color(0xFFFF655B)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: purple,
        surface: card,
        error: danger,
      ),
      cardColor: card,
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF201526),
        foregroundColor: textMain,
        elevation: 0,
        centerTitle: false,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF201526),
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
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textMuted,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
