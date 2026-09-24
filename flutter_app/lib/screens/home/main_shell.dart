import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/chat_provider.dart';
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

  final _pages = const [
    DiscoverScreen(),
    RandomMatchScreen(),
    ChatScreen(),
    WalletScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // App open rahe toh har ~3 min pe simulated incoming call aayegi
      context.read<IncomingCallService>().start();
      // Bot ka admin-configured naam nav label ke liye pehle se hi la lo
      context.read<ChatProvider>().loadConfig();
    });
  }

  @override
  void dispose() {
    // shell band → incoming scheduler bhi band (context dispose ke baad
    // read() allowed nahi, isliye service ko pehle capture kar liya)
    final svc = _incomingSvc;
    if (svc != null) svc.stop();
    super.dispose();
  }

  // initState me context.read safe — reference rakh lo dispose ke liye
  IncomingCallService? _incomingSvc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _incomingSvc ??= context.read<IncomingCallService>();
  }

  @override
  Widget build(BuildContext context) {
    // Admin bot rename kare toh label/icon bhi update (default "Priya" 🤖)
    final chat = context.watch<ChatProvider>();
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          const BottomNavigationBarItem(icon: Text('🏠', style: TextStyle(fontSize: 22)), label: 'Discover'),
          const BottomNavigationBarItem(icon: Text('🎯', style: TextStyle(fontSize: 22)), label: 'Match'),
          BottomNavigationBarItem(icon: Text(chat.botEmoji, style: const TextStyle(fontSize: 22)), label: chat.botName),
          const BottomNavigationBarItem(icon: Text('💰', style: TextStyle(fontSize: 22)), label: 'Wallet'),
          const BottomNavigationBarItem(icon: Text('👤', style: TextStyle(fontSize: 22)), label: 'Profile'),
        ],
      ),
    );
  }
}
