import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../home/host_detail_screen.dart';

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

  Future<void> _openRecharge(CoinPackage pack) async {
    if (!await requireRegistered(context)) return;
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
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(num.tryParse(ctrl.text.trim())), child: const Text('Next')),
        ],
      ),
    );
    if (amt == null || amt <= 0 || !mounted) return;
    if (!await requireRegistered(context)) return;
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RechargeSheet(
        pack: CoinPackage(id: 'custom', label: 'Custom Recharge', coins: amt.toInt(), price: amt, bonus: 0),
      ),
    );
    if (mounted) context.read<WalletProvider>().loadAll();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('💰 Wallet', style: TextStyle(fontWeight: FontWeight.w900)),
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
                    gradient: const LinearGradient(colors: [AppTheme.purple, AppTheme.primary]),
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
                      Text('~₹${auth.balance.toStringAsFixed(0)} value', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    ],
                  ),
                ),

                const SectionTitle('⚡ Coin Packages'),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.75,
                  ),
                  itemCount: wp.packages.length,
                  itemBuilder: (context, i) {
                    final p = wp.packages[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _openRecharge(p),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: p.bonus > 0 ? AppTheme.success.withOpacity(0.5) : AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('🪙 ${p.totalCoins}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                if (p.bonus > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                    child: Text('+${p.bonus}', style: const TextStyle(fontSize: 10, color: AppTheme.success, fontWeight: FontWeight.w800)),
                                  ),
                              ],
                            ),
                            Text(p.label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted), overflow: TextOverflow.ellipsis),
                            Text('₹${p.price}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.warning)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                TextButton.icon(
                  onPressed: _customRecharge,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Custom amount (₹1 = 1 coin)', style: TextStyle(fontSize: 13)),
                ),

                // My recharge requests
                if (wp.recharges.isNotEmpty) ...[
                  const SectionTitle('🕐 My Recharge Requests'),
                  ...wp.recharges.map((r) => _rechargeTile(r)),
                ],

                const SectionTitle('🧾 Transactions'),
                if (wp.transactions.isEmpty)
                  const EmptyView(emoji: '🧾', title: 'No transactions yet', subtitle: 'Recharge karke start karo')
                else
                  ...wp.transactions.map((t) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: t.isCredit ? AppTheme.success.withOpacity(0.15) : AppTheme.danger.withOpacity(0.15),
                          child: Text(t.isCredit ? '➕' : '➖', style: const TextStyle(fontSize: 16)),
                        ),
                        title: Text(t.description.isEmpty ? (t.isCredit ? 'Credit' : 'Debit') : t.description,
                            style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(formatDate(t.date), style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        trailing: Text(
                          '${t.isCredit ? '+' : '−'}🪙${t.amount % 1 == 0 ? t.amount.toInt() : t.amount}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: t.isCredit ? AppTheme.success : AppTheme.danger,
                          ),
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
                Text('₹${r.amountInr} → 🪙 ${r.coins}', style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  r.status == 'rejected' && r.rejectReason != null
                      ? r.rejectReason!
                      : (r.ref != null ? 'UTR: ${r.ref} · ${formatDate(r.date)}' : formatDate(r.date)),
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

/// Pay-to-UPID sheet — admin approve karne pe coins milte hain.
class _RechargeSheet extends StatefulWidget {
  final CoinPackage pack;
  const _RechargeSheet({required this.pack});

  @override
  State<_RechargeSheet> createState() => _RechargeSheetState();
}

class _RechargeSheetState extends State<_RechargeSheet> {
  final _utr = TextEditingController();
  int _step = 0; // 0 = pay instructions, 1 = done

  @override
  void dispose() {
    _utr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    try {
      await context.read<WalletProvider>().createRecharge(
            amount: widget.pack.price,
            transactionRef: _utr.text.trim().isEmpty ? null : _utr.text.trim(),
          );
      if (mounted) setState(() => _step = 1);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (_) {
      if (mounted) showSnack(context, 'Request failed', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wp = context.watch<WalletProvider>();
    final upid = wp.payToUpid;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: _step == 1
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('✅', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 10),
                  const Text('Request submitted!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  const Text(
                    'Payment verify hote hi admin coins credit kar dega.\nStatus: "My Recharge Requests" me dekho.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('⚡ ${widget.pack.label}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text('₹${widget.pack.price} → 🪙 ${widget.pack.totalCoins}${widget.pack.bonus > 0 ? ' (+${widget.pack.bonus} bonus)' : ''}',
                        style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.cardAlt,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.success.withOpacity(upid.isNotEmpty ? 0.6 : 0.0)),
                      ),
                      child: Column(
                        children: [
                          const Text('STEP 1 — Pay via any UPI app', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.accent)),
                          const SizedBox(height: 10),
                          if (upid.isNotEmpty)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: SelectableText(upid,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.warning, letterSpacing: 1)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18, color: AppTheme.textMuted),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: upid));
                                    showSnack(context, 'UPID copied!');
                                  },
                                ),
                              ],
                            )
                          else
                            const Text('UPID abhi set nahi hai — support se contact karo',
                                style: TextStyle(color: AppTheme.danger, fontSize: 13)),
                          Text('Amount: ₹${widget.pack.price}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('STEP 2 — Payment ke baad UTR / Ref No. daalo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.accent)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _utr,
                      decoration: const InputDecoration(labelText: 'UPI Transaction Ref (UTR) — optional but recommended'),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: wp.submitting || upid.isEmpty ? null : _submit,
                      child: wp.submitting
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text('I paid ₹${widget.pack.price} — Submit'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
