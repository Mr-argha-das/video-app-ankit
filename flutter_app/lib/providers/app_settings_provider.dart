import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Admin-configured runtime settings: connecting-screen duration, billing sync
/// interval, incoming-call interval, Priya linked host…
class AppSettingsProvider extends ChangeNotifier {
  final ApiService api;
  AppSettingsProvider(this.api);

  AppSettings settings = const AppSettings();
  DateTime? _loadedAt;

  Future<AppSettings> load({bool force = false}) async {
    // 5 min cache — admin changes jaldi pick ho jaate hain, bina har screen pe request ke
    if (!force && _loadedAt != null && DateTime.now().difference(_loadedAt!) < const Duration(minutes: 5)) {
      return settings;
    }
    try {
      final data = await api.get('${AppConfig.apiPrefix}/settings/app');
      settings = AppSettings.fromJson(Map<String, dynamic>.from(data['settings'] ?? {}));
      _loadedAt = DateTime.now();
      notifyListeners();
    } catch (_) {
      // defaults se kaam chala lo
    }
    return settings;
  }
}
