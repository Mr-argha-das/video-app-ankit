/// Backend API configuration.
///
/// IMPORTANT: baseUrl apne hisaab se badlo:
///  - Android emulator  → http://10.0.2.2:8000
///  - Real device       → http://<PC-ka-LAN-IP>:8000  (e.g. http://192.168.1.5:8000)
///  - Production        → https://your-domain.com
class AppConfig {
  static const String baseUrl = "http://10.0.2.2:8000";

  static const String apiPrefix = "/api/v1";

  /// Billing check interval — backend bhi server-side time based hai,
  /// app sirf har 60 sec pe sync karta hai.
  static const int billingCheckSeconds = 60;
}
