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
    // App open & in use → automatic incoming call suggestion har 5 min
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

  final List<Widget> _pages = [
    const DiscoverScreen(),      // Home — For You / All / New / Follow
    const ComingSoonScreen(),    // Live — coming soon
    const InboxScreen(),         // Chats
    const ProfileScreen(),       // Profile (wallet, settings, delete account)
  ];

  String _title(int i) => const ['Home', 'Live', 'Chats', 'Profile'][i];

  IconData _iconData(int i, bool active) {
    return [
      Icons.home,
      Icons.live_tv,
      Icons.chat_bubble_outline,
      Icons.person,
    ][i];
  }

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
          BottomNavigationBarItem(
            icon: Icon(_iconData(0, _index == 0), size: 26),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(_iconData(1, _index == 1), size: 26),
            label: 'Live',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(_iconData(2, _index == 2), size: 26),
                if (unread > 0)
                  Positioned(
                    right: -6,
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
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Chats',
          ),
          BottomNavigationBarItem(
            icon: Icon(_iconData(3, _index == 3), size: 26),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Live tab — coming soon (spec item n).
class ComingSoonScreen extends StatelessWidget {
  const ComingSoonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.live_tv, size: 80, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          Text('Live streaming',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textMain)),
          const SizedBox(height: 8),
          Text('Coming soon',
              style: TextStyle(fontSize: 14, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}
