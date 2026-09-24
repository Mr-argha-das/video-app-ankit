import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/wallet/wallet_screen.dart';
import '../theme/app_theme.dart';

/// Opens the wallet as a full screen (used from call / incoming / Priya flows).
Future<void> openWallet(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WalletScreen()));
}

/// Low / exhausted balance notification with a "Recharge now" action.
///
/// [exhausted] = call was auto-ended because the wallet ran out.
Future<void> showRechargePrompt(
  BuildContext context, {
  String? message,
  bool exhausted = false,
  double? requiredCoins,
}) async {
  final balance = context.read<AuthProvider>().balance;
  final go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppTheme.card,
    isDismissible: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.danger.withOpacity(0.15)),
              child: Center(child: Text(exhausted ? '🪫' : '💸', style: const TextStyle(fontSize: 38))),
            ),
            const SizedBox(height: 14),
            Text(
              exhausted ? 'Balance khatam ho gaya!' : 'Low balance',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message ??
                  (exhausted
                      ? 'Aapka wallet balance khatam ho gaya, isliye call end ho gayi. Baat continue karne ke liye wallet recharge karein.'
                      : 'Call karne ke liye wallet me balance kam hai. Please recharge karein.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, height: 1.45),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Wallet balance: ', style: TextStyle(color: AppTheme.textMuted)),
                  Text('🪙 ${balance % 1 == 0 ? balance.toInt() : balance.toStringAsFixed(2)}',
                      style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w900)),
                  if (requiredCoins != null) ...[
                    const Text('  ·  Need: ', style: TextStyle(color: AppTheme.textMuted)),
                    Text('🪙 ${requiredCoins % 1 == 0 ? requiredCoins.toInt() : requiredCoins}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Text('💰'),
                label: const Text('Recharge Now'),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Baad mein', style: TextStyle(color: AppTheme.textMuted)),
            ),
          ],
        ),
      ),
    ),
  );
  if (go == true && context.mounted) {
    await openWallet(context);
  }
}
