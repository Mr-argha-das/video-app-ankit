import 'package:flutter/material.dart';

/// ❤️ Dating-app theme — hot pink/coral gradients, soft rounded cards.
class AppTheme {
  // Base — deep plum black
  static const Color bg = Color(0xFF170F1F);
  static const Color card = Color(0xFF241A2E);
  static const Color cardAlt = Color(0xFF30223C);
  static const Color border = Color(0xFF4A3658);

  // Brand — dating pink/coral
  static const Color primary = Color(0xFFFE3C72);
  static const Color secondary = Color(0xFFFF7854);
  static const Color purple = Color(0xFF9B5CF6);
  static const Color accent = Color(0xFF00CEC9);
  static const Color success = Color(0xFF2ED573);
  static const Color warning = Color(0xFFFFC952);
  static const Color danger = Color(0xFFFF4757);
  static const Color textMain = Color(0xF5FFFFFF);
  static const Color textMuted = Color(0xFFB9A8C4);

  /// Signature dating gradient (Tinder-style)
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFFD297B), Color(0xFFFF655B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Soft ambient background gradient
  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFF1E1226), Color(0xFF170F1F)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Photo bottom fade overlay (cards pe text readable rakhne ke liye)
  static const LinearGradient photoOverlay = LinearGradient(
    colors: [Colors.transparent, Color(0xE6000000)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: card,
        error: danger,
      ),
      cardColor: card,
      dividerColor: border,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textMain,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: textMain),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1F1526),
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 12,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardAlt,
        hintStyle: const TextStyle(color: textMuted, fontSize: 14),
        labelStyle: const TextStyle(color: textMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
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
          borderSide: const BorderSide(color: primary, width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          elevation: 4,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textMuted,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: cardAlt,
        contentTextStyle: TextStyle(color: textMain),
      ),
    );
  }
}
