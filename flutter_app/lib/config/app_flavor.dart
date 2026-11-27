/// App flavor — decides kaunsa theme aur kaunsa backend URL use hoga.
enum AppFlavor { orange, dating }

class AppFlavorConfig {
  static AppFlavor current = AppFlavor.orange;

  /// Backend URL flavor ke hisaab se
  static String get apiBaseUrl {
    switch (current) {
      case AppFlavor.orange:
        return String.fromEnvironment('API_BASE_URL', defaultValue: 'https://videcall1.duckdns.org');
      case AppFlavor.dating:
        return String.fromEnvironment('DATING_API_BASE_URL', defaultValue: 'https://videcall2.duckdns.org');
    }
  }
}
