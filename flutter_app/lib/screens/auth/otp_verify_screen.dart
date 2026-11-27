import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../home/main_shell.dart';

/// 4-box OTP entry (spec: OTP entry screen).
class OtpVerifyScreen extends StatefulWidget {
  final String mobile;
  const OtpVerifyScreen({super.key, required this.mobile});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final List<TextEditingController> _boxes = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(4, (_) => FocusNode());
  String _otp = '';

  @override
  void dispose() {
    for (final c in _boxes) c.dispose();
    for (final f in _nodes) f.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_otp.length != 4) {
      showSnack(context, '4-digit OTP daalo', error: true);
      return;
    }
    try {
      await context.read<AuthProvider>().verifyOtp(widget.mobile, _otp);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Verify failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Verify OTP')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text('🔐', textAlign: TextAlign.center, style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('${widget.mobile} par code bheja gaya hai',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textMain)),
            const SizedBox(height: 6),
            const Text('4-digit code enter kijiye', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.cardAlt,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _nodes[i].hasFocus ? AppTheme.primary : AppTheme.border, width: 2),
                  ),
                  child: TextField(
                    controller: _boxes[i],
                    focusNode: _nodes[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppTheme.textMain),
                    decoration: const InputDecoration(counterText: '', border: InputBorder.none, contentPadding: EdgeInsets.zero),
                    onChanged: (v) {
                      setState(() {
                        _otp = _boxes.map((c) => c.text).join();
                      });
                      if (v.isNotEmpty && i < 3) _nodes[i + 1].requestFocus();
                      if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
                    },
                  ),
                );
              }),
            ),
            const SizedBox(height: 30),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: auth.busy ? null : _verify,
                child: auth.busy
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Verify & Continue', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Code nahi mila? ', style: TextStyle(color: AppTheme.textMuted)),
                GestureDetector(
                  onTap: auth.busy ? null : () {
                    context.read<AuthProvider>().sendOtp(widget.mobile);
                    showSnack(context, 'Naya OTP bhej diya gaya');
                  },
                  child: const Text('Resend OTP', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Password se login? ', style: TextStyle(color: AppTheme.textMuted)),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Text('Yahan click karo', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
