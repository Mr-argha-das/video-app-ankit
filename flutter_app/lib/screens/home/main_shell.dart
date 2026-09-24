import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/incoming_call_service.dart';

import '../call/random_match_screen.dart';
import '../chat/chat_screen.dart';
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
    // App open + user active → host incoming call har ~3 min (admin setting)
    _incoming = context.read<IncomingCallService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _incoming.start());
  }

  @override
  void dispose() {
    _incoming.stop();
    super.dispose();
  }

  final _pages = const [
    DiscoverScreen(),
    RandomMatchScreen(),
    ChatScreen(),
    WalletScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Text('🏠', style: TextStyle(fontSize: 22)), label: 'Discover'),
          BottomNavigationBarItem(icon: Text('🎯', style: TextStyle(fontSize: 22)), label: 'Match'),
          BottomNavigationBarItem(icon: Text('🤖', style: TextStyle(fontSize: 22)), label: 'Priya'),
          BottomNavigationBarItem(icon: Text('💰', style: TextStyle(fontSize: 22)), label: 'Wallet'),
          BottomNavigationBarItem(icon: Text('👤', style: TextStyle(fontSize: 22)), label: 'Profile'),
        ],
      ),
    );
  }
}
