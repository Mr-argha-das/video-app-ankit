import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/inbox_provider.dart';
import '../../services/incoming_call_service.dart';
import '../../theme/app_theme.dart';

import '../call/random_match_screen.dart';
import '../chat/inbox_screen.dart';
import '../profile/profile_screen.dart';
import '../wallet/wallet_screen.dart';
import 'discover_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final IncomingCallService _incoming;

  @override
  void initState() {
    super.initState();
    // App open + user active → host incoming call har 5 min (admin setting)
    _incoming = context.read<IncomingCallService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _incoming.start();
      context.read<InboxProvider>().load(); // unread badge
    });
  }

  @override
  void dispose() {
    _incoming.stop();
    super.dispose();
  }

  final _pages = const [
    DiscoverScreen(),
    RandomMatchScreen(),
    InboxScreen(),
    WalletScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final unread = context.select<InboxProvider, int>((p) => p.totalUnread);
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) {
          if (i == 2) context.read<InboxProvider>().load();
          setState(() => _index = i);
        },
        items: [
          const BottomNavigationBarItem(icon: Text('🏠', style: TextStyle(fontSize: 22)), label: 'Discover'),
          const BottomNavigationBarItem(icon: Text('🎯', style: TextStyle(fontSize: 22)), label: 'Match'),
          BottomNavigationBarItem(icon: _InboxIcon(unread: unread, active: _index == 2), label: 'Inbox'),
          const BottomNavigationBarItem(icon: Text('💰', style: TextStyle(fontSize: 22)), label: 'Wallet'),
          const BottomNavigationBarItem(icon: Text('👤', style: TextStyle(fontSize: 22)), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Inbox tab icon + unread count badge.
class _InboxIcon extends StatelessWidget {
  final int unread;
  final bool active;
  const _InboxIcon({required this.unread, required this.active});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(active ? Icons.inbox_rounded : Icons.inbox_outlined, size: 26, color: active ? AppTheme.primary : AppTheme.textMuted),
        if (unread > 0)
          Positioned(
            right: -8,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 18),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.danger,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppTheme.card, width: 1.5),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );
  }
}
