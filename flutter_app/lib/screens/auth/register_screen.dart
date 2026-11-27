import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../home/main_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  String _gender = 'other';
  XFile? _photo;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
    if (img != null) setState(() => _photo = img);
  }

  Future<void> _register() async {
    final name = _name.text.trim();
    var mobile = _mobile.text.replaceAll(RegExp(r'\D'), '');
    if (mobile.length == 12 && mobile.startsWith('91')) mobile = mobile.substring(2);
    if (mobile.length == 11 && mobile.startsWith('0')) mobile = mobile.substring(1);
    final password = _password.text;
    if (name.isEmpty) {
      showSnack(context, 'Apna naam daalo', error: true);
      return;
    }
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(mobile)) {
      showSnack(context, 'Valid 10-digit mobile number daalo (6/7/8/9 se shuru)', error: true);
      return;
    }
    if (password.length < 4) {
      showSnack(context, 'Password kam se kam 4 characters ka hona chahiye', error: true);
      return;
    }
    try {
      final bytes = _photo != null ? await _photo!.readAsBytes() : null;
      await context.read<AuthProvider>().register(
            name: name,
            mobile: mobile,
            password: password,
            gender: _gender,
            photoBytes: bytes,
            photoName: _photo?.name ?? 'photo.jpg',
          );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (r) => false,
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Registration failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: AppTheme.cardAlt,
                  child: _photo == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, color: AppTheme.textMuted),
                            SizedBox(height: 4),
                            Text('Photo', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                          ],
                        )
                      : null,
                  backgroundImage: null,
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 14),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              maxLength: 14,
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
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _gender,
              decoration: const InputDecoration(labelText: 'Gender'),
              dropdownColor: AppTheme.cardAlt,
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Male ♂')),
                DropdownMenuItem(value: 'female', child: Text('Female ♀')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => setState(() => _gender = v ?? 'other'),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: auth.busy ? null : _register,
              child: auth.busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Register for free'),
            ),
            const SizedBox(height: 10),
            const Text('Registering unlocks calls, gifts & wallet 🎁',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}
