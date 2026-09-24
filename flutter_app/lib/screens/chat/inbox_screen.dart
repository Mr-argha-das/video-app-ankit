import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/inbox_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/recharge_prompt.dart';
import '../../widgets/widgets.dart';
import 'chat_screen.dart';

/// Inbox tab — list of hosts (recent chats first). Tap → chat page with that host.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<InboxProvider>().load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(InboxItem it) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(hostId: it.hostId, item: it)),
    );
    if (mounted) context.read<InboxProvider>().load();
  }

  static String _time(DateTime? t) {
    if (t == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    }
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1];
    return '${t.day}/${t.month}/${t.year % 100}';
  }

  @override
  Widget build(BuildContext context) {
    final inbox = context.watch<InboxProvider>();
    final balance = context.watch<AuthProvider>().balance;
    final items = _q.isEmpty
        ? inbox.items
        : inbox.items.where((i) => i.name.toLowerCase().contains(_q)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('📥 Inbox', style: TextStyle(fontWeight: FontWeight.w900)),
            if (inbox.totalUnread > 0) ...[
              const SizedBox(width: 8),
              _badge(inbox.totalUnread),
            ],
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: GestureDetector(onTap: () => openWallet(context), child: CoinChip(balance))),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search hosts…',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: AppTheme.textMuted),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                        },
                      ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: inbox.loading && inbox.items.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                : RefreshIndicator(
                    color: AppTheme.primary,
                    onRefresh: () => context.read<InboxProvider>().load(),
                    child: items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              const SizedBox(height: 80),
                              EmptyView(
                                emoji: inbox.error != null ? '📡' : '💬',
                                title: inbox.error != null ? 'Load nahi hua' : (_q.isEmpty ? 'Abhi koi host nahi' : 'Koi match nahi'),
                                subtitle: inbox.error,
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 82, color: AppTheme.border),
                            itemBuilder: (_, i) => _tile(items[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(InboxItem it) {
    final unread = it.unread > 0;
    final price = it.host != null ? '🪙${it.host!.priceLabel}/min' : '';
    final subtitle = it.hasChat
        ? '${it.lastSender == 'user' ? 'You: ' : ''}${it.lastMessage}'
        : [if (price.isNotEmpty) price, 'Say hi 👋'].join(' · ');
    return InkWell(
      onTap: () => _open(it),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 27,
                  backgroundColor: AppTheme.cardAlt,
                  backgroundImage: it.avatar.isNotEmpty ? CachedNetworkImageProvider(it.avatar) : null,
                  child: it.avatar.isEmpty ? const Text('👩', style: TextStyle(fontSize: 24)) : null,
                ),
                if (it.isOnline)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          it.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, fontWeight: unread ? FontWeight.w900 : FontWeight.w700),
                        ),
                      ),
                      if (it.hasChat)
                        Text(
                          _time(it.lastTime),
                          style: TextStyle(fontSize: 11, color: unread ? AppTheme.primary : AppTheme.textMuted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: unread ? AppTheme.textMain : AppTheme.textMuted,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (unread) ...[const SizedBox(width: 8), _badge(it.unread)],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _badge(int n) => Container(
        constraints: const BoxConstraints(minWidth: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(10)),
        child: Text(
          n > 99 ? '99+' : '$n',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
        ),
      );
}
