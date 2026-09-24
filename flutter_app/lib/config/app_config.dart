/// Backend API configuration.
///
/// IMPORTANT: baseUrl apne hisaab se badlo — ya build ke waqt pass karo:
///   flutter run --dart-define=API_BASE_URL=https://your-domain.com
///
///  - Android emulator  → http://10.0.2.2:8000
///  - Real device (LAN) → http://<PC-ka-LAN-IP>:8000  (e.g. http://192.168.1.5:8000)
///  - Production        → https://your-domain.com   (https:// hi use karo)
///
/// Trailing slash mat lagao.
class AppConfig {
  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  /// Agar server ne redirect kiya (e.g. http → https) toh ApiService yahan
  /// sahi origin set karta hai; media URLs bhi isi se bante hain.
  static String? runtimeOrigin;

  static String get origin {
    final o = runtimeOrigin ?? baseUrl;
    return o.endsWith('/') ? o.substring(0, o.length - 1) : o;
  }

  static const String apiPrefix = "/api/v1";

  /// Billing sync interval fallback (server `billing_tick_seconds` override karta hai).
  static const int billingCheckSeconds = 60;
}
