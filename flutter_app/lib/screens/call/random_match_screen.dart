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

  Future<void> _find() async {
    if (!await requireRegistered(context)) return;
    setState(() => _searching = true);
    try {
      final h = await context.read<HostProvider>().randomMatch(interest: _interest);
      if (!mounted) return;
      setState(() => _searching = false);
      if (h == null) {
        showSnack(context, 'Abhi koi available nahi hai — thodi der baad try karo! 😊');
      } else {
        // 💘 Dating-app moment
        await _showMatchOverlay(h);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _searching = false);
        showSnack(context, 'Match failed — server check karo', error: true);
      }
    }
  }

  Future<void> _showMatchOverlay(Host h) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) => _MatchOverlay(host: h),
    );
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
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => AppTheme.brandGradient.createShader(b),
                      child: const Text('Find your vibe 💞', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 16),
                if (hp.interests.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _chip('All', _interest == null, () => setState(() => _interest = null)),
                        ...hp.interests.map((it) => _chip(it, _interest == it, () {
                              setState(() => _interest = _interest == it ? null : it);
                            })),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Expanded(
                  child: _searching
                      ? const _SearchingView()
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: AppTheme.brandGradient,
                                  boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.5), blurRadius: 40, spreadRadius: 4)],
                                ),
                                child: const Center(child: Text('💘', style: TextStyle(fontSize: 72))),
                              ),
                              const SizedBox(height: 26),
                              const Text('Ready to meet someone?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                              const SizedBox(height: 8),
                              const Text('Tap the button — ek random online host\nse instantly match ho jaoge!',
                                  textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, height: 1.5)),
                            ],
                          ),
                        ),
                ),
                GradientButton(
                  emoji: '💞',
                  label: _searching ? 'Finding your match…' : 'Find Match',
                  onPressed: _searching ? null : _find,
                ),
                const SizedBox(height: 12),
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
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: active ? AppTheme.brandGradient : null,
            color: active ? null : AppTheme.cardAlt,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? Colors.transparent : AppTheme.border),
          ),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
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
          SizedBox(height: 70, width: 70, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3)),
          SizedBox(height: 22),
          Text('Tumhare liye koi khaas dhoondh rahe hain… 💫', style: TextStyle(color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

/// 💘 Full-screen "It's a Match!" overlay — signature dating moment.
class _MatchOverlay extends StatelessWidget {
  final Host host;
  const _MatchOverlay({required this.host});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              ShaderMask(
                shaderCallback: (b) => AppTheme.brandGradient.createShader(b),
                child: const Text("IT'S A MATCH!",
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: Colors.white, letterSpacing: 1.5)),
              ),
              const SizedBox(height: 8),
              const Text('Dono ne ek dusre ko vibe kiya 💘', style: TextStyle(color: AppTheme.textMuted, fontSize: 15)),
              const SizedBox(height: 44),
              // Two hearts overlapping
              SizedBox(
                width: 240,
                height: 150,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primary, width: 4),
                        ),
                        child: AvatarPhoto(url: auth.avatarUrl, size: 140, letter: '😊'),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.secondary, width: 4),
                        ),
                        child: AvatarPhoto(url: host.profilePic, size: 140, letter: '💃'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('${host.name}, ${host.age ?? '?'}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('⭐ ${host.rating}', style: const TextStyle(color: AppTheme.textMuted)),
                  const SizedBox(width: 12),
                  Text('🪙 ${host.pricePerMinute % 1 == 0 ? host.pricePerMinute.toInt() : host.pricePerMinute}/min',
                      style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700)),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 40),
                child: Column(
                  children: [
                    GradientButton(
                      emoji: '📹',
                      label: 'Start Video Call',
                      onPressed: host.isOnline
                          ? () {
                              Navigator.of(context).pop();
                              Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(host: host)));
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Baad me baat karta hoon', style: TextStyle(color: AppTheme.textMuted)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
