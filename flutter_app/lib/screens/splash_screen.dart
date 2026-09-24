import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'auth/login_screen.dart';
import 'home/main_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final auth = context.read<AuthProvider>();
    await auth.init();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => auth.loggedIn ? const MainShell() : const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.bg, Color(0xFF1F1B3A)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🎥', style: TextStyle(fontSize: 72)),
            SizedBox(height: 16),
            Text('VideoCall App', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.primary)),
            SizedBox(height: 8),
            Text('Connect. Talk. Earn levels. 🚀', style: TextStyle(color: AppTheme.textMuted)),
            SizedBox(height: 32),
            CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
          ],
        ),
      ),
    );
  }
}
