import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class GiftProvider extends ChangeNotifier {
  final ApiService api;
  final AuthProvider auth;
  GiftProvider(this.api, this.auth);

  Map<String, List<GiftItem>> byCategory = {};
  bool loading = false;
  bool sending = false;
  String? error;

  Future<void> loadGifts() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.get('${AppConfig.apiPrefix}/gifts/categories');
      final map = <String, List<GiftItem>>{};
      final cats = (data['categories'] ?? []) as List;
      for (final c in cats) {
        final name = (c['category'] ?? 'standard').toString();
        final items = ((c['gifts'] ?? []) as List).map((e) => GiftItem.fromJson(Map<String, dynamic>.from(e))).toList();
        map[name] = items;
      }
      byCategory = map;
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  List<GiftItem> get all => byCategory.values.expand((e) => e).toList();

  /// Send gift — coins deduct + XP. Returns server message.
  Future<Map<String, dynamic>> sendGift({required GiftItem gift, required String hostId, String? callId, String? message}) async {
    sending = true;
    notifyListeners();
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/gifts/send', {
        'gift_id': gift.id,
        'host_id': hostId,
        if (callId != null) 'call_id': callId,
        if (message != null && message.isNotEmpty) 'message': message,
      });
      if (data['new_balance'] != null) {
        auth.updateBalance((data['new_balance'] as num).toDouble());
      }
      await auth.refreshUser().catchError((_) {}); // XP/level sync
      return Map<String, dynamic>.from(data);
    } finally {
      sending = false;
      notifyListeners();
    }
  }
}
