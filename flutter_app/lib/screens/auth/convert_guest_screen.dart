import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/widgets.dart';

/// Guest → full account conversion (calls/gifts/wallet unlock).
class ConvertGuestScreen extends StatefulWidget {
  const ConvertGuestScreen({super.key});

  @override
  State<ConvertGuestScreen> createState() => _ConvertGuestScreenState();
}

class _ConvertGuestScreenState extends State<ConvertGuestScreen> {
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _convert() async {
    if (_name.text.trim().isEmpty || _mobile.text.trim().length != 10 || _password.text.length < 4) {
      showSnack(context, 'Name, 10-digit mobile, aur 4+ char password daalo', error: true);
      return;
    }
    try {
      await context.read<AuthProvider>().convertGuest(
            name: _name.text.trim(),
            mobile: _mobile.text.trim(),
            password: _password.text,
          );
      if (!mounted) return;
      showSnack(context, '🎉 Account upgraded! Sab features unlocked.');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'Conversion failed', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().busy;
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock Full Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('🚀', textAlign: TextAlign.center, style: TextStyle(fontSize: 56)),
            const SizedBox(height: 8),
            const Text('Guest mode me calls, gifts, wallet locked hain.\nRegister karke sab unlock karo!',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, height: 1.5)),
            const SizedBox(height: 28),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
            const SizedBox(height: 14),
            TextField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(labelText: 'Mobile Number', prefixText: '+91 ', counterText: ''),
            ),
            const SizedBox(height: 14),
            TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Set Password')),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: busy ? null : _convert,
              child: busy
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Upgrade my account'),
            ),
          ],
        ),
      ),
    );
  }
}
