import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class LevelProvider extends ChangeNotifier {
  final ApiService api;
  LevelProvider(this.api);

  Map<String, dynamic>? myLevel;
  List<dynamic> xpActions = [];
  List<LeaderboardUser> leaderboard = [];
  List<dynamic> allLevels = [];
  bool loading = false;

  Future<void> loadMyLevel() async {
    loading = true;
    notifyListeners();
    try {
      final data = await api.get('${AppConfig.apiPrefix}/levels/my-level');
      myLevel = {
        'level': data['level'],
        'badge': data['badge'],
        'perks': data['perks'],
      };
      xpActions = (data['xp_actions'] ?? []) as List;
    } catch (_) {} finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadLeaderboard() async {
    loading = true;
    notifyListeners();
    try {
      final data = await api.get('${AppConfig.apiPrefix}/levels/leaderboard');
      leaderboard = ((data['leaderboard'] ?? []) as List).map((e) => LeaderboardUser.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {} finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllLevels() async {
    try {
      final data = await api.get('${AppConfig.apiPrefix}/levels/all-levels');
      allLevels = (data['levels'] ?? []) as List;
      notifyListeners();
    } catch (_) {}
  }

  Map<String, dynamic>? get levelData {
    final l = myLevel?['level'];
    return l is Map<String, dynamic> ? l : null;
  }
}
