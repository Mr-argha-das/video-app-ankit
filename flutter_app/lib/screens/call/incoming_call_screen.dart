import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'call_screen.dart';

/// "Host is calling you" screen — Accept / Reject.
///
/// Accept → same flow as an outgoing call:
///   Connecting (10s) → host video → wallet deduction → auto-end on low balance.
/// Reject / no answer within [ringTimeoutSeconds] → logged as rejected / missed.
class IncomingCallScreen extends StatefulWidget {
  final Host host;
  final int ringTimeoutSeconds;
  const IncomingCallScreen({super.key, required this.host, this.ringTimeoutSeconds = 30});

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  Timer? _timeout;
  Timer? _buzz;
  bool _done = false;

  Host get h => widget.host;

  @override
  void initState() {
    super.initState();
    _timeout = Timer(Duration(seconds: widget.ringTimeoutSeconds), () => _finish('missed'));
    _vibrate();
    _buzz = Timer.periodic(const Duration(milliseconds: 1800), (_) => _vibrate());
  }

  void _vibrate() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
  }

  void _stopRinging() {
    _timeout?.cancel();
    _buzz?.cancel();
  }

  Future<void> _finish(String action) async {
    if (_done) return;
    _done = true;
    _stopRinging();
    // Admin call logs ke liye rejected/missed record (best effort)
    try {
      context.read<ApiService>().postJson('${AppConfig.apiPrefix}/calls/incoming/respond', {
        'host_id': h.id,
        'action': action,
      });
    } catch (_) {}
    if (mounted) Navigator.of(context).maybePop();
  }

  void _accept() {
    if (_done) return;
    _done = true;
    _stopRinging();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => CallScreen(host: h, incoming: true)),
    );
  }

  @override
  void dispose() {
    _stopRinging();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balance = context.watch<AuthProvider>().balance;
    final meta = [if (h.age != null) '${h.age}', if (h.city.isNotEmpty) h.city].join(' · ');
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        if (!_done) {
          await _finish('rejected');
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (h.profilePic.isNotEmpty)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: CachedNetworkImage(imageUrl: h.profilePic, fit: BoxFit.cover),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF1F1B3A).withOpacity(0.85), AppTheme.bg.withOpacity(0.97)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  const Text('📲 Incoming video call',
                      style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                  const Spacer(),
                  ScaleTransition(
                    scale: Tween(begin: 0.94, end: 1.06).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primary, width: 3),
                        boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.5), blurRadius: 30, spreadRadius: 4)],
                        color: AppTheme.cardAlt,
                        image: h.profilePic.isNotEmpty
                            ? DecorationImage(image: CachedNetworkImageProvider(h.profilePic), fit: BoxFit.cover)
                            : null,
                      ),
                      child: h.profilePic.isEmpty ? const Center(child: Text('👤', style: TextStyle(fontSize: 64))) : null,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(h.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    meta.isEmpty ? 'is calling you…' : '$meta  ·  is calling you…',
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '🪙 ${h.priceLabel}/min  ·  Balance 🪙${balance % 1 == 0 ? balance.toInt() : balance.toStringAsFixed(1)}',
                      style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 56),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _action(icon: Icons.call_end, label: 'Reject', bg: AppTheme.danger, onTap: () => _finish('rejected')),
                        ScaleTransition(
                          scale: Tween(begin: 1.0, end: 1.12).animate(_pulse),
                          child: _action(icon: Icons.videocam, label: 'Accept', bg: AppTheme.success, onTap: _accept),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _action({required IconData icon, required String label, required Color bg, required VoidCallback onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bg,
              boxShadow: [BoxShadow(color: bg.withOpacity(0.45), blurRadius: 18)],
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
