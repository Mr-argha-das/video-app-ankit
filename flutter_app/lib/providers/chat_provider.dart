import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Priya page chat — AI bot that talks as the admin-configured persona
/// (default Priya persona, or a specific host's persona).
/// Understands & replies in Hindi, English or Hinglish.
class ChatProvider extends ChangeNotifier {
  final ApiService api;
  final AuthProvider auth;
  ChatProvider(this.api, this.auth);

  /// Legacy key (default Priya) — purani chats preserve rehti hain.
  static const _legacyKey = 'priya_conversation_id';

  ChatPersona? persona;

  /// null = Priya page default persona; else chatting with this host's persona.
  String? selectedHostId;

  List<ChatMsg> messages = [];
  String? conversationId;
  bool loading = false;
  bool sending = false;
  bool _initialized = false;
  int _loadToken = 0;

  String get botName => persona?.name ?? 'Priya';
  bool get aiPowered => persona?.aiPowered ?? false;

  /// Host behind the current persona — used for the Priya page video call.
  Host? get callHost => persona?.host;

  String _key(String? hostId) => hostId == null ? _legacyKey : 'priya_conv_$hostId';

  Future<void> init({String? hostId, bool force = false}) async {
    if (!force && _initialized && hostId == selectedHostId && messages.isNotEmpty) return;
    final token = ++_loadToken;
    _initialized = true;
    selectedHostId = hostId;
    loading = true;
    messages = [];
    conversationId = null;
    notifyListeners();

    await _loadPersona(hostId);
    if (token != _loadToken) return; // user ne beech me persona switch kar diya

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key(selectedHostId));
    var restored = false;
    if (saved != null) {
      try {
        await loadHistory(saved);
        if (token != _loadToken) return;
        conversationId = saved;
        restored = true;
      } catch (_) {
        await prefs.remove(_key(selectedHostId));
      }
    }
    if (!restored) await newSession();
    if (token != _loadToken) return;
    loading = false;
    notifyListeners();
  }

  /// Switch the Priya page to another persona (null = default Priya).
  Future<void> selectPersona(String? hostId) => init(hostId: hostId);

  Future<void> _loadPersona(String? hostId) async {
    try {
      final data = await api.get(
        '${AppConfig.apiPrefix}/chat/bot/persona',
        query: hostId == null ? null : {'host_id': hostId},
      );
      persona = ChatPersona.fromJson(Map<String, dynamic>.from(data['persona'] ?? {}));
    } on ApiException catch (_) {
      if (hostId != null) {
        // Is host ke liye chat available nahi → default Priya
        selectedHostId = null;
        await _loadPersona(null);
      }
    } catch (_) {
      // offline — purana persona hi rehne do
    }
  }

  Future<void> newSession() async {
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/chat/bot/new-session', {
        if (selectedHostId != null) 'host_id': selectedHostId,
      });
      conversationId = data['conversation_id']?.toString();
      if (data['persona'] is Map) {
        persona = ChatPersona.fromJson(Map<String, dynamic>.from(data['persona']));
      }
      messages = [
        ChatMsg(sender: 'bot', text: (data['greeting'] ?? 'Heyy! 😊').toString(), time: DateTime.now()),
      ];
      final prefs = await SharedPreferences.getInstance();
      if (conversationId != null) await prefs.setString(_key(selectedHostId), conversationId!);
    } catch (_) {
      messages = [
        ChatMsg(sender: 'bot', text: persona?.greeting.isNotEmpty == true ? persona!.greeting : 'Heyy! Main $botName hoon 😊', time: DateTime.now()),
      ];
    }
    notifyListeners();
  }

  Future<void> loadHistory(String convId) async {
    final data = await api.get('${AppConfig.apiPrefix}/chat/bot/history/$convId');
    final conv = data['conversation'];
    final msgs = ((conv['messages'] ?? []) as List).map((e) => ChatMsg.fromJson(Map<String, dynamic>.from(e))).toList();
    messages = msgs.isEmpty ? [ChatMsg(sender: 'bot', text: 'Heyy! Main $botName hoon! 😊', time: DateTime.now())] : msgs;
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty || sending) return;
    sending = true;
    messages.add(ChatMsg(sender: 'user', text: text, time: DateTime.now()));
    notifyListeners();
    final hostAtSend = selectedHostId;
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/chat/bot/message', {
        'message': text,
        if (conversationId != null) 'conversation_id': conversationId,
        if (conversationId == null && selectedHostId != null) 'host_id': selectedHostId,
      });
      if (hostAtSend != selectedHostId) return; // persona switch ho gaya
      conversationId ??= data['conversation_id']?.toString();
      final prefs = await SharedPreferences.getInstance();
      if (conversationId != null) await prefs.setString(_key(selectedHostId), conversationId!);
      messages.add(ChatMsg(sender: 'bot', text: (data['bot_reply'] ?? '...').toString(), time: DateTime.now()));
      // XP sync (+1 per message)
      auth.refreshUser().catchError((_) {});
    } on ApiException catch (e) {
      messages.add(ChatMsg(sender: 'bot', text: '⚠️ ${e.message}', time: DateTime.now()));
    } catch (e) {
      messages.add(ChatMsg(sender: 'bot', text: 'Oops! Network issue ho gaya 😅 Phir try karo!', time: DateTime.now()));
    } finally {
      sending = false;
      notifyListeners();
    }
  }
}
