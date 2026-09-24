import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/inbox_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/recharge_prompt.dart';
import '../../widgets/widgets.dart';
import '../call/call_screen.dart';
import '../home/host_detail_screen.dart';

/// Chat page with one host (opened from the Inbox tab or a host profile).
///
/// AI bot talks as the admin-configured host persona in Hindi / English /
/// Hinglish. Header has the video call button + wallet chip. Host messages
/// pushed by the backend (video call button) appear in this thread.
class ChatScreen extends StatefulWidget {
  /// null = default Priya persona.
  final String? hostId;

  /// Inbox row — used to render the header instantly while the thread loads.
  final InboxItem? item;

  const ChatScreen({super.key, this.hostId, this.item});

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
      final it = widget.item;
      context.read<InboxProvider>().markRead(widget.hostId);
      context
          .read<ChatProvider>()
          .open(
            hostId: widget.hostId,
            fallback: it == null
                ? null
                : ChatPersona(name: it.name, hostId: it.hostId, isDefault: it.hostId == null, avatar: it.avatar, host: it.host),
          )
          .then((_) => _scrollDown(jump: true));
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollDown({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent + 80;
      if (jump) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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

  /// Video call — har click backend tak jaata hai (host ka message Inbox me aata hai).
  /// Balance kam ho toh CallScreen khud recharge prompt dikhata hai.
  Future<void> _startCall(Host host) async {
    if (!await requireRegistered(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(host: host)));
    if (!mounted) return;
    await context.read<ChatProvider>().refresh(); // host ka call message dikhao
    _scrollDown();
  }

  void _openProfile(Host host) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostDetailScreen(host: host)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cp = context.watch<ChatProvider>();
    // Provider kisi aur chat pe ho (race) toh purana data mat dikhao
    final mine = cp.selectedHostId == widget.hostId;
    final persona = mine ? cp.persona : null;
    final host = mine ? cp.callHost : widget.item?.host;
    final name = persona?.name ?? widget.item?.name ?? 'Chat';
    final messages = mine ? cp.messages : const <ChatMsg>[];
    final loading = !mine || (cp.loading && messages.isEmpty);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: GestureDetector(
          onTap: host == null ? null : () => _openProfile(host),
          child: Row(
            children: [
              _avatar(persona?.avatar ?? widget.item?.avatar ?? '', 20, online: host?.isOnline ?? true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text(
                      mine && cp.sending
                          ? 'typing…'
                          : (host?.isOnline ?? true)
                              ? 'Online • Hindi · English · Hinglish'
                              : 'Offline • chat available',
                      style: TextStyle(
                        fontSize: 11,
                        color: (host?.isOnline ?? true) ? AppTheme.success.withOpacity(0.9) : AppTheme.textMuted,
                      ),
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
              icon: Icon(Icons.videocam_rounded, color: host.isOnline ? AppTheme.primary : AppTheme.textMuted, size: 28),
              onPressed: host.isOnline ? () => _startCall(host) : () => showSnack(context, '${host.name} abhi offline hai'),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.textMuted),
            color: AppTheme.card,
            onSelected: (v) {
              if (v == 'new') context.read<ChatProvider>().newSession();
              if (v == 'wallet') openWallet(context);
              if (v == 'profile' && host != null) _openProfile(host);
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
          if (host != null) _callBanner(host, auth.balance),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : mine && cp.error != null && messages.isEmpty
                    ? EmptyView(emoji: '💬', title: 'Chat load nahi hui', subtitle: cp.error)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(14),
                        itemCount: messages.length + (mine && cp.sending ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == messages.length) return _bubble(const _TypingDots(), isUser: false);
                          final m = messages[i];
                          if (m.isCallMessage) return _callMessage(m);
                          return _bubble(
                            Text(m.text, style: const TextStyle(fontSize: 14.5, height: 1.35)),
                            isUser: m.isUser,
                          );
                        },
                      ),
          ),
          if (!loading && messages.length <= 2) _quickReplyRow(),
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
                        hintText: '$name se Hindi / English me baat karo…',
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
                      onPressed: cp.sending || loading ? null : () => _send(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String url, double radius, {bool online = true}) {
    return Stack(
      children: [
        CircleAvatar(
          radius: radius,
          backgroundColor: AppTheme.purple,
          backgroundImage: url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
          child: url.isEmpty ? Text('👩', style: TextStyle(fontSize: radius * 0.9)) : null,
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

  Widget _callBanner(Host host, double balance) {
    final enough = balance >= host.pricePerMinute;
    final minutes = host.pricePerMinute > 0 ? (balance / host.pricePerMinute).floor() : 0;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.primary.withOpacity(0.22), AppTheme.accent.withOpacity(0.12)]),
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
                  enough ? '🪙${host.priceLabel}/min · ~$minutes min talk time' : '🪙${host.priceLabel}/min · balance kam hai',
                  style: TextStyle(fontSize: 11.5, color: enough ? AppTheme.textMuted : AppTheme.danger),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              backgroundColor: AppTheme.success,
            ),
            onPressed: host.isOnline ? () => _startCall(host) : null,
            child: Text(host.isOnline ? 'Call' : 'Offline'),
          ),
        ],
      ),
    );
  }

  /// Host ka auto message (video call button dabane pe backend se).
  Widget _callMessage(ChatMsg m) {
    final low = m.kind == 'low_balance';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: AppTheme.cardAlt,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: (low ? AppTheme.warning : AppTheme.primary).withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(low ? '💰 Video call request' : '📹 Video call',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: low ? AppTheme.warning : AppTheme.primary)),
            const SizedBox(height: 4),
            Text(m.text, style: const TextStyle(fontSize: 14.5, height: 1.35)),
            if (low) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  onPressed: () => openWallet(context),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  child: const Text('Recharge', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
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
