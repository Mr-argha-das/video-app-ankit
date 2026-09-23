import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/host_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../home/host_detail_screen.dart';
import 'call_screen.dart';
import 'incoming_call_screen.dart';

class RandomMatchScreen extends StatefulWidget {
  const RandomMatchScreen({super.key});

  @override
  State<RandomMatchScreen> createState() => _RandomMatchScreenState();
}

class _RandomMatchScreenState extends State<RandomMatchScreen> {
  String? _interest;
  bool _searching = false;
  Host? _matched;
  String? _message;

  Future<void> _find() async {
    if (!await requireRegistered(context)) return;
    setState(() {
      _searching = true;
      _matched = null;
      _message = null;
    });
    try {
      final h = await context.read<HostProvider>().randomMatch(interest: _interest);
      setState(() {
        _matched = h;
        _message = h == null ? 'Abhi koi available nahi hai. Thodi der baad try karo! 😊' : 'Match mila! ${h.name} ke saath connect ho 🎉';
      });
    } catch (e) {
      setState(() => _message = 'Match failed — server check karo');
    } finally {
      setState(() => _searching = false);
    }
  }

  Future<void> _simulateIncoming() async {
    if (!await requireRegistered(context)) return;
    try {
      final h = await context.read<HostProvider>().randomIncoming();
      if (!mounted) return;
      if (h == null) {
        showSnack(context, 'Abhi koi host available nahi hai', error: true);
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => IncomingCallScreen(host: h), fullscreenDialog: true));
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hp = context.watch<HostProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('🎯 Random Match', style: TextStyle(fontWeight: FontWeight.w900))),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (hp.interests.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _interest == null,
                        onSelected: (_) => setState(() => _interest = null),
                        selectedColor: AppTheme.primary,
                        backgroundColor: AppTheme.cardAlt,
                        labelStyle: TextStyle(color: _interest == null ? Colors.white : AppTheme.textMuted, fontSize: 12),
                        side: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                    ...hp.interests.map((it) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(it),
                            selected: _interest == it,
                            onSelected: (_) => setState(() => _interest = _interest == it ? null : it),
                            selectedColor: AppTheme.primary,
                            backgroundColor: AppTheme.cardAlt,
                            labelStyle: TextStyle(color: _interest == it ? Colors.white : AppTheme.textMuted, fontSize: 12),
                            side: const BorderSide(color: AppTheme.border),
                          ),
                        )),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            Expanded(
              child: _searching
                  ? const _SearchingView()
                  : _matched != null
                      ? _MatchCard(host: _matched!)
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_message != null ? '😅' : '🎲', style: const TextStyle(fontSize: 72)),
                              const SizedBox(height: 16),
                              Text(
                                _message ?? 'Tap "Find Match" to meet a random host!',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 15, height: 1.5),
                              ),
                            ],
                          ),
                        ),
            ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _searching ? null : _find,
                icon: const Text('🔍'),
                label: Text(_searching ? 'Searching…' : 'Find Match'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _simulateIncoming,
                icon: const Text('📞'),
                label: const Text('Simulate incoming call'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchingView extends StatelessWidget {
  const _SearchingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 64, width: 64, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3)),
          SizedBox(height: 20),
          Text('Perfect match dhoondh rahe hain… 💫', style: TextStyle(color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final Host host;
  const _MatchCard({required this.host});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withOpacity(0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: AppTheme.cardAlt,
              backgroundImage: host.profilePic.isNotEmpty ? NetworkImage(host.profilePic) : null,
              child: host.profilePic.isEmpty ? const Text('👤', style: TextStyle(fontSize: 44)) : null,
            ),
            const SizedBox(height: 12),
            Text('${host.name}, ${host.age ?? '?'}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LevelBadge(level: host.level),
                const SizedBox(width: 8),
                CoinChip(host.pricePerMinute),
              ],
            ),
            if (host.interests.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(host.interests.take(3).join(' · '), style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: host.isOnline
                    ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(host: host)))
                    : null,
                icon: const Text('📹'),
                label: const Text('Start Video Call'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostDetailScreen(host: host))),
              child: const Text('View profile', style: TextStyle(color: AppTheme.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}
