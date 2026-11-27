import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

/// Inbox → host chat. AI bot talks as the admin-configured host persona
/// (or the default Priya persona when [hostId] is null).
/// Understands & replies in Hindi, English or Hinglish.
///
/// Threads are server-side (`GET /chat/bot/thread?host_id=`) so host messages
/// pushed by the backend (e.g. on the video call button) show up here too.
class ChatProvider extends ChangeNotifier {
  final ApiService api;
  final AuthProvider auth;
  ChatProvider(this.api, this.auth);

  /// Chat me kuch naya hua (message bheja / thread khula) → Inbox refresh.
  VoidCallback? onActivity;

  ChatPersona? persona;

  /// Currently open chat: host id (null = default Priya persona).
  String? selectedHostId;

  List<ChatMsg> messages = [];
  String? conversationId;
  bool loading = false;
  bool sending = false;
  String? error;
  int _loadToken = 0;

  String get botName => persona?.name ?? 'Priya';
  bool get aiPowered => persona?.aiPowered ?? false;

  /// Host behind the open chat — used for the video call button.
  Host? get callHost => persona?.host;

  /// Open the chat with a host (from Inbox / host profile).
  /// [fallback] = inbox data se turant header dikhane ke liye.
  Future<void> open({String? hostId, ChatPersona? fallback}) async {
    final token = ++_loadToken;
    selectedHostId = hostId;
    persona = fallback;
    messages = [];
    conversationId = null;
    error = null;
    loading = true;
    notifyListeners();
    await _fetchThread(token);
  }

  /// Silent reload (e.g. call se wapas aaye → host ka call message dikhao).
  Future<void> refresh() async {
    if (loading) return;
    await _fetchThread(++_loadToken, silent: true);
  }

  Future<void> _fetchThread(int token, {bool silent = false}) async {
    try {
      final data = await api.get(
        '${AppConfig.apiPrefix}/chat/bot/thread',
        query: selectedHostId == null ? null : {'host_id': selectedHostId!},
      );
      if (token != _loadToken) return; // beech me dusri chat khul gayi
      if (data['persona'] is Map) {
        persona = ChatPersona.fromJson(Map<String, dynamic>.from(data['persona']));
      }
      conversationId = data['conversation_id']?.toString();
      final msgs = ((data['messages'] ?? []) as List)
          .map((e) => ChatMsg.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      messages = msgs.isEmpty
          ? [ChatMsg(sender: 'bot', text: persona?.greeting.isNotEmpty == true ? persona!.greeting : 'Heyy! Main $botName hoon 😊', time: DateTime.now())]
          : msgs;
      error = null;
      onActivity?.call(); // unread clear hua
    } on ApiException catch (e) {
      if (token != _loadToken) return;
      if (!silent) error = e.status == 403 ? 'Is host ke saath chat abhi available nahi hai' : e.message;
    } catch (_) {
      if (token != _loadToken) return;
      if (!silent) error = 'Network issue — dobara try karo';
    } finally {
      if (token == _loadToken) {
        loading = false;
        notifyListeners();
      }
    }
  }

  /// Fresh conversation with the same persona ("New chat" menu).
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
      onActivity?.call();
    } catch (_) {
      messages = [
        ChatMsg(sender: 'bot', text: persona?.greeting.isNotEmpty == true ? persona!.greeting : 'Heyy! Main $botName hoon 😊', time: DateTime.now()),
      ];
    }
    notifyListeners();
  }

  Future<void> send(String text) async {
    if (text.trim().isEmpty || sending) return;
    sending = true;
    messages.add(ChatMsg(sender: 'user', text: text, time: DateTime.now()));
    notifyListeners();
    final token = _loadToken;
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/chat/bot/message', {
        'message': text,
        if (conversationId != null) 'conversation_id': conversationId,
        if (conversationId == null && selectedHostId != null) 'host_id': selectedHostId,
      });
      if (token != _loadToken) return; // chat badal gayi
      conversationId ??= data['conversation_id']?.toString();
      messages.add(ChatMsg(sender: 'bot', text: (data['bot_reply'] ?? '...').toString(), time: DateTime.now()));
      auth.refreshUser().catchError((_) {}); // XP sync (+1 per message)
      onActivity?.call();
    } on ApiException catch (e) {
      if (token == _loadToken) messages.add(ChatMsg(sender: 'bot', text: '⚠️ ${e.message}', time: DateTime.now()));
    } catch (e) {
      if (token == _loadToken) {
        messages.add(ChatMsg(sender: 'bot', text: 'Oops! Network issue ho gaya 😅 Phir try karo!', time: DateTime.now()));
      }
    } finally {
      sending = false;
      notifyListeners();
    }
  }
}
