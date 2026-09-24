import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/app_settings_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/call_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/gift_provider.dart';
import 'providers/host_provider.dart';
import 'providers/inbox_provider.dart';
import 'providers/level_provider.dart';
import 'providers/wallet_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/incoming_call_service.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const VideoCallApp());
}

class VideoCallApp extends StatefulWidget {
  const VideoCallApp({super.key});

  @override
  State<VideoCallApp> createState() => _VideoCallAppState();
}

class _VideoCallAppState extends State<VideoCallApp> {
  final ApiService api = ApiService();

  late final AuthProvider authP = AuthProvider(api);
  late final HostProvider hostP = HostProvider(api);
  late final WalletProvider walletP = WalletProvider(api, authP);
  late final AppSettingsProvider settingsP = AppSettingsProvider(api);
  // Video call button → host ka message Inbox me (backend) → badge refresh
  late final CallProvider callP = CallProvider(api, authP, settingsP)..onHostMessage = () => inboxP.load();
  late final IncomingCallService incomingS = IncomingCallService(
    api: api,
    auth: authP,
    callP: callP,
    settingsP: settingsP,
    navigatorKey: navigatorKey,
  );
  late final GiftProvider giftP = GiftProvider(api, authP);
  late final InboxProvider inboxP = InboxProvider(api);
  late final ChatProvider chatP = ChatProvider(api, authP)..onActivity = () => inboxP.load();
  late final LevelProvider levelP = LevelProvider(api);

  @override
  void initState() {
    super.initState();
    // Token expire/invalid hone pe seedha login screen pe bhejo.
    api.onUnauthorized = () {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        Navigator.of(ctx, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Session expired — please login again')),
        );
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider.value(value: authP),
        ChangeNotifierProvider.value(value: hostP),
        ChangeNotifierProvider.value(value: walletP),
        ChangeNotifierProvider.value(value: settingsP),
        ChangeNotifierProvider.value(value: callP),
        ChangeNotifierProvider.value(value: incomingS),
        ChangeNotifierProvider.value(value: giftP),
        ChangeNotifierProvider.value(value: inboxP),
        ChangeNotifierProvider.value(value: chatP),
        ChangeNotifierProvider.value(value: levelP),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'VideoCall App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: const SplashScreen(),
      ),
    );
  }
}
