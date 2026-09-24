import 'package:flutter/material.dart';

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
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Text('🔥', style: TextStyle(fontSize: 24)), label: 'Vibes'),
          BottomNavigationBarItem(icon: Text('💞', style: TextStyle(fontSize: 24)), label: 'Match'),
          BottomNavigationBarItem(icon: Text('🤖', style: TextStyle(fontSize: 24)), label: 'Priya'),
          BottomNavigationBarItem(icon: Text('💎', style: TextStyle(fontSize: 24)), label: 'Wallet'),
          BottomNavigationBarItem(icon: Text('👤', style: TextStyle(fontSize: 24)), label: 'Me'),
        ],
      ),
    );
  }
}
