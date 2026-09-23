import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/gift_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

/// Gift panel — call screen ya host profile dono se open hota hai.
Future<void> showGiftSheet(BuildContext context, {required String hostId, String? callId}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GiftSheet(hostId: hostId, callId: callId),
  );
}

class _GiftSheet extends StatefulWidget {
  final String hostId;
  final String? callId;
  const _GiftSheet({required this.hostId, this.callId});

  @override
  State<_GiftSheet> createState() => _GiftSheetState();
}

class _GiftSheetState extends State<_GiftSheet> {
  String? _selectedCategory;
  bool _sentOverlay = false;

  @override
  void initState() {
    super.initState();
    final gp = context.read<GiftProvider>();
    if (gp.byCategory.isEmpty) gp.loadGifts();
  }

  Future<void> _send(GiftItem gift) async {
    final auth = context.read<AuthProvider>();
    if (auth.balance < gift.coins) {
      showSnack(context, 'Balance kam hai — wallet me recharge karo! 🪙', error: true);
      return;
    }
    try {
      final data = await context.read<GiftProvider>().sendGift(
            gift: gift,
            hostId: widget.hostId,
            callId: widget.callId,
          );
      if (!mounted) return;
      setState(() => _sentOverlay = true);
      showSnack(context, (data['message'] ?? '🎁 Gift sent!').toString());
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Consumer<GiftProvider>(
      builder: (context, gp, _) {
        final categories = gp.byCategory.keys.toList();
        if (_selectedCategory == null && categories.isNotEmpty) _selectedCategory = categories.first;
        final gifts = gp.byCategory[_selectedCategory] ?? [];

        return Container(
          height: MediaQuery.of(context).size.height * 0.62,
          decoration: const BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 10),
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('🎁 Send a Gift', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        CoinChip(auth.balance),
                      ],
                    ),
                  ),
                  if (gp.loading)
                    const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.primary)))
                  else if (categories.isEmpty)
                    const Expanded(child: EmptyView(emoji: '🎁', title: 'No gifts available'))
                  else ...[
                    SizedBox(
                      height: 40,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final cat = categories[i];
                          final selected = cat == _selectedCategory;
                          return ChoiceChip(
                            label: Text(cat[0].toUpperCase() + cat.substring(1)),
                            selected: selected,
                            onSelected: (_) => setState(() => _selectedCategory = cat),
                            selectedColor: AppTheme.purple,
                            backgroundColor: AppTheme.cardAlt,
                            labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.textMuted, fontSize: 12),
                            side: const BorderSide(color: AppTheme.border),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.85,
                        ),
                        itemCount: gifts.length,
                        itemBuilder: (context, i) {
                          final g = gifts[i];
                          final affordable = auth.balance >= g.coins;
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: gp.sending ? null : () => _send(g),
                            child: Opacity(
                              opacity: affordable ? 1 : 0.45,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppTheme.cardAlt,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppTheme.border),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(g.emoji, style: const TextStyle(fontSize: 30)),
                                    const SizedBox(height: 4),
                                    Text(g.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                    Text('🪙 ${g.coins}', style: const TextStyle(fontSize: 11, color: AppTheme.warning)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
              if (_sentOverlay)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: const Center(child: Text('🎁💫', style: TextStyle(fontSize: 72))),
                ),
            ],
          ),
        );
      },
    );
  }
}
