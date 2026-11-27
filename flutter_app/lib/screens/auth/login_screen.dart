import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../home/main_shell.dart';
import 'otp_verify_screen.dart';
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
  bool _usePassword = false; // true → mobile+password; false → OTP

  @override
  void dispose() {
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  String _cleanMobile(String raw) {
    var m = raw.replaceAll(RegExp(r'\D'), '');
    if (m.length == 12 && m.startsWith('91')) m = m.substring(2);
    if (m.length == 11 && m.startsWith('0')) m = m.substring(1);
    return m;
  }

  Future<void> _sendOtp() async {
    final mobile = _cleanMobile(_mobile.text);
    if (mobile.length != 10) {
      showSnack(context, 'Valid 10-digit mobile number daalo', error: true);
      return;
    }
    try {
      await context.read<AuthProvider>().sendOtp(mobile);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OtpVerifyScreen(mobile: mobile),
      ));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'OTP nahi bhej sakte: $e', error: true);
    }
  }

  Future<void> _loginPassword() async {
    final mobile = _cleanMobile(_mobile.text);
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
      if (mounted) showSnack(context, 'Login failed: $e', error: true);
    }
  }

  Future<void> _googleLogin() async {
    // Google Sign-In returns an idToken; here we open a placeholder flow.
    // Real integration: google_sign_in package → pass idToken to auth.googleLogin.
    if (!mounted) return;
    showSnack(context, 'Google Sign-In configure karne ke baad kaam karega (id_token)', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Text('💛', textAlign: TextAlign.center, style: TextStyle(fontSize: 56)),
              const SizedBox(height: 12),
              const Text('OnlineDost.app',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
              const SizedBox(height: 6),
              const Text('Welcome! Naye doston se miliye aur baat kijiye.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
              const SizedBox(height: 40),
              if (!_usePassword) ...[
                TextField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  maxLength: 14,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixText: '+91 ',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: auth.busy ? null : _sendOtp,
                    child: auth.busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('OTP bhejo (Continue)', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: auth.busy ? null : _googleLogin,
                    icon: const Icon(Icons.g_mobiledata, color: AppTheme.primary, size: 22),
                    label: const Text('Login with Google', style: TextStyle(fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textMain,
                      side: const BorderSide(color: AppTheme.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Password se login? ', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    GestureDetector(
                      onTap: () => setState(() => _usePassword = true),
                      child: const Text('Yahan click karo', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
              ] else ...[
                TextField(
                  controller: _mobile,
                  keyboardType: TextInputType.phone,
                  maxLength: 14,
                  decoration: const InputDecoration(
                    labelText: 'Mobile Number',
                    prefixText: '+91 ',
                    counterText: '',
                  ),
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
                  onSubmitted: (_) => _loginPassword(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: auth.busy ? null : _loginPassword,
                    child: auth.busy
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Login', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('OTP se login? ', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                    GestureDetector(
                      onTap: () => setState(() => _usePassword = false),
                      child: const Text('Yahan click karo', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('New here? ', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: const Text('Create account', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _openPage('terms'),
                    child: const Text('Terms', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ),
                  const Text('  •  ', style: TextStyle(color: AppTheme.textMuted)),
                  GestureDetector(
                    onTap: () => _openPage('privacy-policy'),
                    child: const Text('Privacy', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPage(String slug) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StaticPageScreen(slug: slug),
    ));
  }
}

/// Reads a static page (privacy/terms) from /api/v1/pages/{slug}.
class StaticPageScreen extends StatefulWidget {
  final String slug;
  const StaticPageScreen({super.key, required this.slug});

  @override
  State<StaticPageScreen> createState() => _StaticPageScreenState();
}

class _StaticPageScreenState extends State<StaticPageScreen> {
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService().get('/api/v1/pages/${widget.slug}');
      if (mounted) setState(() {
        _content = (data['page']?['content'] ?? '') as String;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.slug == 'terms' ? 'Terms & Conditions' : 'Privacy Policy')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: _content.isEmpty
                  ? const Center(child: Text('Content available nahi hai'))
                  : SingleChildScrollView(
                      child: Text(_content.replaceAll(RegExp(r'<[^>]*>'), ' '),
                          style: const TextStyle(fontSize: 15, height: 1.6, color: AppTheme.textMain)),
                    ),
            ),
    );
  }
}
