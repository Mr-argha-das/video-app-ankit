import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';

/// Inbox tab — saare chat-enabled hosts + last message + unread badge.
class InboxProvider extends ChangeNotifier {
  final ApiService api;
  InboxProvider(this.api);

  List<InboxItem> items = [];
  int totalUnread = 0;
  bool loading = false;
  String? error;
  bool _inFlight = false;
  bool _again = false;

  Future<void> load({bool showLoader = false}) async {
    if (_inFlight) {
      _again = true; // chal rahi request ke baad ek aur (latest data)
      return;
    }
    _inFlight = true;
    if (showLoader || items.isEmpty) {
      loading = true;
      notifyListeners();
    }
    try {
      final data = await api.get('${AppConfig.apiPrefix}/chat/inbox');
      items = ((data['items'] ?? []) as List)
          .map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      totalUnread = (data['total_unread'] as num?)?.toInt() ?? items.fold<int>(0, (a, i) => a + i.unread);
      error = null;
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Network issue — pull karke refresh karo';
    } finally {
      loading = false;
      _inFlight = false;
      notifyListeners();
    }
    if (_again) {
      _again = false;
      await load();
    }
  }

  /// Chat kholte hi badge turant hatao (server bhi thread open pe read mark karta hai).
  void markRead(String? hostId) {
    final i = items.indexWhere((e) => e.hostId == hostId);
    if (i < 0 || items[i].unread == 0) return;
    final it = items[i];
    totalUnread = (totalUnread - it.unread).clamp(0, 1 << 30).toInt();
    items[i] = InboxItem(
      hostId: it.hostId,
      name: it.name,
      avatar: it.avatar,
      isOnline: it.isOnline,
      host: it.host,
      conversationId: it.conversationId,
      lastMessage: it.lastMessage,
      lastSender: it.lastSender,
      lastTime: it.lastTime,
      unread: 0,
    );
    notifyListeners();
  }

  void clear() {
    items = [];
    totalUnread = 0;
    notifyListeners();
  }
}
