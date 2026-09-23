import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cp = context.read<ChatProvider>();
      if (cp.messages.isEmpty) cp.init();
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await context.read<ChatProvider>().send(text);
    _scrollDown();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(backgroundColor: AppTheme.purple, child: Text('🤖')),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Priya', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text('Online • Hinglish bot', style: TextStyle(fontSize: 11, color: AppTheme.success.withOpacity(0.9))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            icon: const Icon(Icons.refresh, color: AppTheme.textMuted),
            onPressed: () => context.read<ChatProvider>().newSession(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, cp, _) {
                if (cp.loading && cp.messages.isEmpty) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(14),
                  itemCount: cp.messages.length + (cp.sending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i == cp.messages.length) {
                      return _bubble(const _TypingDots(), isUser: false);
                    }
                    final m = cp.messages[i];
                    return _bubble(
                      Text(m.text, style: const TextStyle(fontSize: 14.5, height: 1.35)),
                      isUser: m.isUser,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: AppTheme.card,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Priya se kuch bhi poocho…',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Consumer<ChatProvider>(
                    builder: (context, cp, _) => CircleAvatar(
                      backgroundColor: AppTheme.primary,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 20),
                        onPressed: cp.sending ? null : _send,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!auth.isGuest)
            Container(
              width: double.infinity,
              color: AppTheme.purple.withOpacity(0.12),
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: const Text('Har message pe +1 XP milta hai ✨',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            ),
        ],
      ),
    );
  }

  Widget _bubble(Widget child, {required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.primary : AppTheme.cardAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        return Text(
          t < 0.33 ? '•' : t < 0.66 ? '• •' : '• • •',
          style: const TextStyle(fontSize: 18, color: AppTheme.textMuted, letterSpacing: 2),
        );
      },
    );
  }
}
