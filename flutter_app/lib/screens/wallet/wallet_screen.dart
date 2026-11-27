import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().loadAll();
    });
  }

  bool _requireReg() {
    final auth = context.read<AuthProvider>();
    if (auth.isGuest) {
      showSnack(context, 'Recharge/call ke liye pehle register/login karo', error: true);
      return false;
    }
    return true;
  }

  Future<void> _openRecharge(CoinPackage pack) async {
    if (!_requireReg()) return;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RechargeSheet(pack: pack),
    );
    if (mounted) context.read<WalletProvider>().loadAll();
  }

  Future<void> _customRecharge() async {
    final ctrl = TextEditingController();
    final amt = await showDialog<num>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom amount'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Amount (₹) — ₹1 = 1 coin, no bonus'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(num.tryParse(ctrl.text.trim())),
            child: const Text('Next'),
          ),
        ],
      ),
    );
    if (amt == null || amt <= 0 || !mounted || !_requireReg()) return;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RechargeSheet(
        pack: CoinPackage(id: 'custom', payAmount: amt, getAmount: amt.toInt()),
      ),
    );
    if (mounted) context.read<WalletProvider>().loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('💰 Talktime Wallet', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: CoinChip(auth.balance))),
        ],
      ),
      body: Consumer<WalletProvider>(
        builder: (context, wp, _) {
          if (wp.loading && wp.packages.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          return RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: wp.loadAll,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Balance card
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark]),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOTAL BALANCE', style: TextStyle(fontSize: 11, color: Colors.white70, letterSpacing: 1)),
                      const SizedBox(height: 6),
                      Text('🪙 ${auth.balance % 1 == 0 ? auth.balance.toInt() : auth.balance.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('~₹${auth.balance.toStringAsFixed(0)} Talktime', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),

                const SectionTitle('⚡ Recharge Packs'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Pay ₹ → Get coins (1 coin = ₹1). Bonus coins free.',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                ),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: wp.packages.length,
                  itemBuilder: (context, i) {
                    final p = wp.packages[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openRecharge(p),
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: p.isBest ? AppTheme.primary : AppTheme.border, width: p.isBest ? 2 : 1),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (p.isBest)
                                  const Align(
                                    alignment: Alignment.topRight,
                                    child: Text('BEST', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppTheme.warning)),
                                  ),
                                Text('🪙 ${p.getAmount}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                                const SizedBox(height: 4),
                                Text('Pay ₹${p.payAmount}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.primary)),
                                if (p.bonus > 0)
                                  Text('+${p.bonus} bonus', style: const TextStyle(fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.w700)),
                                Text('${p.id.replaceAll('pack_', '')}', style: const TextStyle(fontSize: 9, color: AppTheme.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                TextButton.icon(
                  onPressed: _customRecharge,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Custom amount (₹1 = 1 coin)', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
                ),
                const SizedBox(height: 6),

                // My recharge requests
                if (wp.recharges.isNotEmpty) ...[
                  const SectionTitle('🕐 My Recharge Requests'),
                  ...wp.recharges.map((r) => _rechargeTile(r)),
                ],

                const SectionTitle('🧾 Transactions (last 90 days)'),
                if (wp.transactions.isEmpty)
                  const EmptyView(emoji: '🧾', title: 'No transactions yet', subtitle: 'Recharge karke start karo.\n90 din purane transactions dikhai nahi de sakte.')
                else
                  ...wp.transactions.map((t) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: t.isCredit ? AppTheme.success.withOpacity(0.15) : AppTheme.danger.withOpacity(0.15),
                          child: Text(t.isCredit ? '➕' : '➖', style: const TextStyle(fontSize: 16)),
                        ),
                        title: Text(t.description.isEmpty ? (t.isCredit ? 'Credit' : 'Debit') : t.description,
                            style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_fmtDate(t.date), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        trailing: Text(
                          '${t.isCredit ? '+' : '−'}🪙${t.amount % 1 == 0 ? t.amount.toInt() : t.amount}',
                          style: TextStyle(fontWeight: FontWeight.w800,
                              color: t.isCredit ? AppTheme.success : AppTheme.danger),
                        ),
                      )),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmtDate(DateTime? d) => d == null ? '-' : '${d.day}/${d.month}/${d.year}';

  Widget _rechargeTile(RechargeItem r) {
    final color = r.status == 'approved' ? AppTheme.success : r.status == 'rejected' ? AppTheme.danger : AppTheme.warning;
    final label = r.status == 'approved' ? 'Approved ✅' : r.status == 'rejected' ? 'Rejected ❌' : 'Pending ⏳';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pay ₹${r.amountInr} → 🪙 ${r.coins}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  r.status == 'rejected' && r.rejectReason != null
                      ? r.rejectReason!
                      : (r.ref != null ? 'Ref: ${r.ref} · ${_fmtDate(r.date)}' : _fmtDate(r.date)),
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
            child: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

/// Recharge sheet — Razorpay OR QR deposit (screenshot + UTR, admin approve).
class _RechargeSheet extends StatefulWidget {
  final CoinPackage pack;
  const _RechargeSheet({required this.pack});

  @override
  State<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends State<_RechargeSheet> {
  int _mode = 0; // 0 = razorpay, 1 = qr deposit
  String _orderId = '';
  String _paymentId = '';
  String _signature = '';
  bool _gotOrder = false;

  // QR deposit fields
  String _qrImageUrl = '';
  String _upiId = '';
  File? _screenshot;
  final _utrCtrl = TextEditingController();
  bool _loadingQr = true;

  @override
  void initState() {
    super.initState();
    _loadQrConfig();
  }

  @override
  void dispose() {
    _utrCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadQrConfig() async {
    try {
      final data = await ApiService().get('/api/v1/wallet/qr-config');
      if (!mounted) return;
      setState(() {
        _qrImageUrl = data['qr_image_url']?.toString() ?? '';
        _upiId = data['upi_id']?.toString() ?? '';
        _loadingQr = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingQr = false);
    }
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null && mounted) {
      setState(() => _screenshot = File(picked.path));
    }
  }

  Future<void> _createOrder() async {
    final wp = context.read<WalletProvider>();
    try {
      final data = await wp.createRazorpayOrder(payAmount: widget.pack.payAmount, packId: widget.pack.id);
      if (!mounted) return;
      setState(() {
        _orderId = (data['order_id'] ?? '').toString();
        _gotOrder = true;
      });
      showSnack(context, 'Razorpay order bana liya hai');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Order failed: $e', error: true);
    }
  }

  Future<void> _verify() async {
    final wp = context.read<WalletProvider>();
    if (_paymentId.isEmpty || _signature.isEmpty) {
      showSnack(context, 'Payment ID aur signature daalo', error: true);
      return;
    }
    final ok = await wp.verifyRazorpayPayment(orderId: _orderId, paymentId: _paymentId, signature: _signature);
    if (!mounted) return;
    if (ok) {
      showSnack(context, 'Coins credit ho gaye!');
      Navigator.of(context).pop();
    } else {
      showSnack(context, wp.error ?? 'Verify failed', error: true);
    }
  }

  Future<void> _submitDeposit() async {
    if (_screenshot == null) {
      showSnack(context, 'Payment ka screenshot upload karo', error: true);
      return;
    }
    if (_utrCtrl.text.trim().isEmpty) {
      showSnack(context, 'UTR / Transaction ID daalo', error: true);
      return;
    }
    final wp = context.read<WalletProvider>();
    try {
      final bytes = await _screenshot!.readAsBytes();
      final data = await context.read<ApiService>().multipart('POST', '${AppConfig.apiPrefix}/wallet/deposit',
          fields: {'amount': widget.pack.payAmount.toString(), 'transaction_ref': _utrCtrl.text.trim()},
          files: [ApiFile('screenshot', bytes, 'screenshot_${DateTime.now().millisecondsSinceEpoch}.jpg')]);
      if (!mounted) return;
      showSnack(context, data['message'] ?? 'Deposit request submit ho gaya');
      Navigator.of(context).pop();
      await wp.loadAll();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Deposit failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WalletProvider>();
    final auth = context.watch<AuthProvider>();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('⚡ ${widget.pack.id.replaceAll('pack_', '')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Pay ₹${widget.pack.payAmount} → Get 🪙${widget.pack.getAmount} coins',
                style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: wp.submitting ? null : () => setState(() => _mode = 0),
                    icon: const Icon(Icons.payment, size: 18),
                    label: const Text('Razorpay'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _mode == 0 ? AppTheme.primary : AppTheme.textMuted,
                      side: BorderSide(color: _mode == 0 ? AppTheme.primary : AppTheme.border),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: wp.submitting ? null : () => setState(() => _mode = 1),
                    icon: const Icon(Icons.qr_code, size: 18),
                    label: const Text('QR Deposit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _mode == 1 ? AppTheme.primary : AppTheme.textMuted,
                      side: BorderSide(color: _mode == 1 ? AppTheme.primary : AppTheme.border),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_mode == 0) ...[
              if (!_gotOrder)
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: wp.submitting ? null : _createOrder,
                    child: const Text('Create Razorpay Order', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              if (_gotOrder) ...[
                const Text('Checkout pe payment karne ke baad yahan details daalo:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(labelText: 'Razorpay Order ID'),
                  onChanged: (v) => setState(() => _orderId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(labelText: 'Payment ID'),
                  onChanged: (v) => setState(() => _paymentId = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(labelText: 'Signature'),
                  onChanged: (v) => setState(() => _signature = v),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: wp.submitting ? null : _verify,
                    child: wp.submitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Verify & Credit Coins', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ] else ...[
              // QR Deposit mode
              if (_loadingQr)
                const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              else ...[
                const Text('STEP 1 — UPI se payment karo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.accent)),
                const SizedBox(height: 8),
                if (_qrImageUrl.isNotEmpty) ...[
                  GestureDetector(
                    onTap: _qrImageUrl.isNotEmpty
                        ? () => showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                child: Image.network(_qrImageUrl!, fit: BoxFit.contain),
                              ),
                            )
                        : null,
                    child: Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: AppTheme.cardAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(_qrImageUrl!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                      ),
                    ),
                  ),
                ] else
                  Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(color: AppTheme.cardAlt, borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Text('QR image available nahi hai', style: TextStyle(color: AppTheme.textMuted))),
                  ),
                const SizedBox(height: 10),
                if (_upiId.isNotEmpty)
                  Row(
                    children: [
                      const Text('UPI: ', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      Flexible(
                        child: SelectableText(_upiId,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.warning)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18, color: AppTheme.textMuted),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _upiId));
                          showSnack(context, 'UPI ID copied!');
                        },
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                const Text('STEP 2 — Screenshot upload karo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.accent)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: _pickScreenshot,
                  child: Container(
                    width: double.infinity,
                    height: 140,
                    decoration: BoxDecoration(
                      color: AppTheme.cardAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _screenshot != null ? AppTheme.primary : AppTheme.border),
                    ),
                    child: _screenshot != null
                        ? Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(_screenshot!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                              ),
                              Positioned(
                                right: 8,
                                top: 8,
                                child: GestureDetector(
                                  onTap: () => setState(() => _screenshot = null),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.camera_alt, color: AppTheme.textMuted, size: 32),
                              const SizedBox(height: 8),
                              Text('Screenshot upload karo (payment proof)',
                                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('STEP 3 — UTR / Transaction ID daalo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.accent)),
                const SizedBox(height: 8),
                TextField(
                  controller: _utrCtrl,
                  decoration: const InputDecoration(labelText: 'UPI Transaction Ref / UTR'),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: wp.submitting || _screenshot == null ? null : _submitDeposit,
                    child: wp.submitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Submit Deposit Request', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ]),
        ),
      ),
    );
  }
}
