import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../home/main_shell.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final mobile = _mobile.text.trim();
    final password = _password.text;
    if (mobile.length != 10 || password.isEmpty) {
      showSnack(context, 'Valid 10-digit mobile aur password daalo', error: true);
      return;
    }
    try {
      await context.read<AuthProvider>().login(mobile, password);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Server se connect nahi ho pa raha', error: true);
    }
  }

  Future<void> _guest() async {
    try {
      await context.read<AuthProvider>().guestLogin();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
      showSnack(context, 'Guest mode ON — calls/gifts ke liye register karo');
    } catch (_) {
      if (mounted) showSnack(context, 'Server se connect nahi ho pa raha', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Text('🎥', textAlign: TextAlign.center, style: TextStyle(fontSize: 64)),
              const SizedBox(height: 12),
              const Text('VideoCall App',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
              const SizedBox(height: 6),
              const Text('Login to continue', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
              const SizedBox(height: 36),
              TextField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: const InputDecoration(labelText: 'Mobile Number', prefixText: '+91 ', counterText: ''),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: AppTheme.textMuted, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: auth.busy ? null : _submit,
                child: auth.busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Login'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: auth.busy ? null : _guest,
                icon: const Text('👤'),
                label: const Text('Continue as Guest'),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('New here? ', style: TextStyle(color: AppTheme.textMuted)),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: const Text('Create account', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
