import 'package:flutter/material.dart';

import 'app_theme_orange.dart' as orange;
import 'app_theme_dating.dart' as dating;
import '../config/app_flavor.dart';

/// Wrapper theme — flavor ke hisaab se sahi theme return karta hai.
class AppTheme {
  static ThemeData get dark {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.dark;
      case AppFlavor.dating:
        return dating.AppThemeDating.dark;
    }
  }

  static Color get primary {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.primary;
      case AppFlavor.dating:
        return dating.AppThemeDating.primary;
    }
  }

  static Color get primaryDark {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.primaryDark;
      case AppFlavor.dating:
        return dating.AppThemeDating.purple;
    }
  }

  static Color get accent {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.accent;
      case AppFlavor.dating:
        return dating.AppThemeDating.accent;
    }
  }

  static Color get success {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.success;
      case AppFlavor.dating:
        return dating.AppThemeDating.success;
    }
  }

  static Color get warning {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.warning;
      case AppFlavor.dating:
        return dating.AppThemeDating.warning;
    }
  }

  static Color get danger {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.danger;
      case AppFlavor.dating:
        return dating.AppThemeDating.danger;
    }
  }

  static Color get bg {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.bg;
      case AppFlavor.dating:
        return dating.AppThemeDating.bg;
    }
  }

  static Color get card {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.card;
      case AppFlavor.dating:
        return dating.AppThemeDating.card;
    }
  }

  static Color get cardAlt {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.cardAlt;
      case AppFlavor.dating:
        return dating.AppThemeDating.cardAlt;
    }
  }

  static Color get border {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.border;
      case AppFlavor.dating:
        return dating.AppThemeDating.border;
    }
  }

  static Color get textMain {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.textMain;
      case AppFlavor.dating:
        return dating.AppThemeDating.textMain;
    }
  }

  static Color get textMuted {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.textMuted;
      case AppFlavor.dating:
        return dating.AppThemeDating.textMuted;
    }
  }

  static LinearGradient get brandGradient {
    switch (AppFlavorConfig.current) {
      case AppFlavor.orange:
        return orange.AppTheme.brandGradient;
      case AppFlavor.dating:
        return dating.AppThemeDating.brandGradient;
    }
  }
}
