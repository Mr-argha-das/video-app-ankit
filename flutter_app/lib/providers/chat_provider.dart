import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService api;
  final AuthProvider auth;
  ChatProvider(this.api, this.auth);

  static const _convKey = 'priya_conversation_id';

  List<ChatMsg> messages = [];
  String? conversationId;
  bool loading = false;
  bool sending = false;
  String botName = 'Priya';
  String botEmoji = '🤖';
  String botTagline = 'Hinglish AI dost';

  /// Admin panel se configured bot branding (naam/emoji/tagline) lao.
  /// MainShell bhi isse call karta hai taaki nav label update ho jaye.
  Future<void> loadConfig() async {
    try {
      final data = await api.get('${AppConfig.apiPrefix}/chat/bot/config');
      if (data is Map && data['success'] == true) {
        final name = data['bot_name']?.toString();
        if (name != null && name.trim().isNotEmpty) botName = name.trim();
        final emoji = data['bot_emoji']?.toString();
        if (emoji != null && emoji.trim().isNotEmpty) botEmoji = emoji.trim();
        final tag = data['tagline']?.toString();
        if (tag != null && tag.trim().isNotEmpty) botTagline = tag.trim();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> init() async {
    loading = true;
    notifyListeners();
    loadConfig(); // fire & forget — header/nav kabhi bhi refresh ho jayenge
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_convKey);
    if (saved != null) {
      try {
        await loadHistory(saved);
        conversationId = saved;
        loading = false;
        notifyListeners();
        return;
      } catch (_) {
        await prefs.remove(_convKey);
      }
    }
    await newSession();
    loading = false;
    notifyListeners();
  }

  Future<void> newSession() async {
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/chat/bot/new-session', {});
      conversationId = data['conversation_id']?.toString();
      messages = [
        ChatMsg(sender: 'bot', text: (data['greeting'] ?? 'Heyy! 😊').toString(), time: DateTime.now()),
      ];
      final prefs = await SharedPreferences.getInstance();
      if (conversationId != null) await prefs.setString(_convKey, conversationId!);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadHistory(String convId) async {
    final data = await api.get('${AppConfig.apiPrefix}/chat/bot/history/$convId');
    final conv = data['conversation'];
    final msgs = ((conv['messages'] ?? []) as List).map((e) => ChatMsg.fromJson(Map<String, dynamic>.from(e))).toList();
    if (msgs.isEmpty) {
      messages = [ChatMsg(sender: 'bot', text: 'Heyy! Main $botName hoon! 😊', time: DateTime.now())];
    } else {
      messages = msgs;
    }
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty || sending) return;
    sending = true;
    messages.add(ChatMsg(sender: 'user', text: text, time: DateTime.now()));
    notifyListeners();
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/chat/bot/message', {
        'message': text,
        if (conversationId != null) 'conversation_id': conversationId,
      });
      conversationId ??= data['conversation_id']?.toString();
      final prefs = await SharedPreferences.getInstance();
      if (conversationId != null) await prefs.setString(_convKey, conversationId!);
      messages.add(ChatMsg(sender: 'bot', text: (data['bot_reply'] ?? '...').toString(), time: DateTime.now()));
      // XP sync (+1 per message)
      auth.refreshUser().catchError((_) {});
    } catch (e) {
      messages.add(ChatMsg(sender: 'bot', text: 'Oops! Network issue ho gaya 😅 Phir try karo!', time: DateTime.now()));
    } finally {
      sending = false;
      notifyListeners();
    }
  }
}
