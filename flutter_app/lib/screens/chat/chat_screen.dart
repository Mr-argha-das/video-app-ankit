import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/host_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/recharge_prompt.dart';
import '../../widgets/widgets.dart';
import '../call/call_screen.dart';
import '../home/host_detail_screen.dart';

/// Priya page — AI chat (Hindi / English / Hinglish) + video call + wallet,
/// all driven by the admin-configured persona/host.
///
/// Used as the "Priya" bottom-nav tab, and can also be pushed with a
/// [hostId] to chat with a specific host's persona (from the host profile).
class ChatScreen extends StatefulWidget {
  final String? hostId;
  final bool pushed;
  const ChatScreen({super.key, this.hostId, this.pushed = false});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  static const _quickReplies = [
    'Hi! 👋',
    'Kaise ho? 😊',
    'Tell me about yourself',
    'आप कहाँ से हो?',
    'Kya kar rahi ho?',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final cp = context.read<ChatProvider>();
      if (widget.pushed) {
        cp.init(hostId: widget.hostId).then((_) => _scrollDown());
      } else if (cp.messages.isEmpty) {
        cp.init().then((_) => _scrollDown());
      }
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

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;
    _input.clear();
    final cp = context.read<ChatProvider>();
    final f = cp.send(text);
    _scrollDown();
    await f;
    _scrollDown();
  }

  Future<void> _startCall(Host host) async {
    if (!await requireRegistered(context)) return;
    if (!mounted) return;
    final balance = context.read<AuthProvider>().balance;
    if (balance < host.pricePerMinute) {
      await showRechargePrompt(
        context,
        requiredCoins: host.pricePerMinute,
        message: '${host.name} ko call karne ke liye kam se kam 🪙${host.priceLabel} (1 minute) chahiye. Wallet recharge karein.',
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(host: host)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cp = context.watch<ChatProvider>();
    final persona = cp.persona;
    final host = cp.callHost;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: widget.pushed ? 0 : 12,
        title: GestureDetector(
          onTap: host == null
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostDetailScreen(host: host))),
          child: Row(
            children: [
              _avatar(persona, 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cp.botName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text(
                      cp.sending ? 'typing…' : 'Online • Hindi · English · Hinglish',
                      style: TextStyle(fontSize: 11, color: AppTheme.success.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(onTap: () => openWallet(context), child: CoinChip(auth.balance)),
          ),
          if (host != null)
            IconButton(
              tooltip: 'Video call',
              icon: const Icon(Icons.videocam_rounded, color: AppTheme.primary, size: 28),
              onPressed: host.isOnline ? () => _startCall(host) : null,
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
            color: AppTheme.card,
            onSelected: (v) {
              if (v == 'new') context.read<ChatProvider>().newSession();
              if (v == 'wallet') openWallet(context);
              if (v == 'profile' && host != null) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostDetailScreen(host: host)));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('🔄  New chat')),
              const PopupMenuItem(value: 'wallet', child: Text('💰  Wallet / Recharge')),
              if (host != null) const PopupMenuItem(value: 'profile', child: Text('👤  View profile')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.pushed) _personaStrip(cp),
          if (host != null) _callBanner(host, auth.balance),
          Expanded(
            child: cp.loading && cp.messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : ListView.builder(
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
                  ),
          ),
          if (!cp.loading && cp.messages.length <= 2) _quickReplyRow(),
          SafeArea(
            top: false,
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
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '${cp.botName} se Hindi / English me baat karo…',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppTheme.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: cp.sending ? null : () => _send(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!auth.isGuest && !widget.pushed)
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

  Widget _avatar(ChatPersona? p, double radius, {bool online = true}) {
    final url = p?.avatar ?? '';
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: AppTheme.purple,
          backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
          child: url.isEmpty ? Text('🤖', style: TextStyle(fontSize: radius * 0.9)) : null,
        ),
        if (online)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: radius * 0.55,
              height: radius * 0.55,
              decoration: BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.bg, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  /// Switch who you're chatting with: default Priya + hosts with chat enabled.
  Widget _personaStrip(ChatProvider cp) {
    final hosts = context.watch<HostProvider>().hosts;
    final defaultHostId = cp.selectedHostId == null ? cp.persona?.hostId : null;
    final others = hosts.where((h) => h.hasBot && h.id != defaultHostId).take(20).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    Widget item({required String label, required String avatar, required bool selected, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected ? AppTheme.brandGradient : null,
                  color: selected ? null : AppTheme.border,
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.cardAlt,
                  backgroundImage: avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
                  child: avatar.isEmpty ? const Text('🤖', style: TextStyle(fontSize: 18)) : null,
                ),
              ),
              const SizedBox(height: 3),
              SizedBox(
                width: 56,
                child: Text(label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                      color: selected ? AppTheme.textMain : AppTheme.textMuted,
                    )),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 82,
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: [
          item(
            label: cp.selectedHostId == null ? cp.botName : context.watch<AppSettingsProvider>().settings.priyaName,
            avatar: cp.selectedHostId == null ? (cp.persona?.avatar ?? '') : '',
            selected: cp.selectedHostId == null,
            onTap: () {
              if (cp.selectedHostId != null) cp.selectPersona(null).then((_) => _scrollDown());
            },
          ),
          ...others.map((h) => item(
                label: h.name,
                avatar: h.profilePic,
                selected: cp.selectedHostId == h.id,
                onTap: () {
                  if (cp.selectedHostId != h.id) cp.selectPersona(h.id).then((_) => _scrollDown());
                },
              )),
        ],
      ),
    );
  }

  Widget _callBanner(Host host, double balance) {
    final enough = balance >= host.pricePerMinute;
    final minutes = host.pricePerMinute > 0 ? (balance / host.pricePerMinute).floor() : 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary.withOpacity(0.22), AppTheme.accent.withOpacity(0.12)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          const Text('📹', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Video call ${host.name}',
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  enough
                      ? '🪙${host.priceLabel}/min · ~$minutes min talk time'
                      : '🪙${host.priceLabel}/min · balance kam hai',
                  style: TextStyle(fontSize: 11.5, color: enough ? AppTheme.textMuted : AppTheme.danger),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          enough
              ? ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    backgroundColor: AppTheme.success,
                  ),
                  onPressed: host.isOnline ? () => _startCall(host) : null,
                  child: Text(host.isOnline ? 'Call' : 'Offline'),
                )
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                  onPressed: () => openWallet(context),
                  child: const Text('Recharge'),
                ),
        ],
      ),
    );
  }

  Widget _quickReplyRow() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: _quickReplies
            .map((q) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(q, style: const TextStyle(fontSize: 12)),
                    backgroundColor: AppTheme.cardAlt,
                    side: const BorderSide(color: AppTheme.border),
                    onPressed: () => _send(q),
                  ),
                ))
            .toList(),
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
