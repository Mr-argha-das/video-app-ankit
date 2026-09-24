import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/models.dart';
import '../../providers/call_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../gifts/gift_sheet.dart';
import '../wallet/wallet_screen.dart';

/// Video call screen.
/// Flow: "Calling…" ringing (~10 sec, free) → host ka admin-uploaded video play
/// → per-minute wallet deduction → balance khatam → auto-end + recharge prompt.
class CallScreen extends StatefulWidget {
  final Host host;
  const CallScreen({super.key, required this.host});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  VideoPlayerController? _vp;
  bool _started = false;
  bool _videoStarting = false;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    final call = context.read<CallProvider>();
    try {
      await call.startCall(widget.host);
    } on ApiException catch (e) {
      if (mounted) {
        showSnack(context, e.message, error: true);
        Navigator.of(context).pop();
      }
      return;
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Call connect nahi ho payi', error: true);
        Navigator.of(context).pop();
      }
      return;
    }
    _maybeStartVideo(call);
  }

  /// Call active hone pe admin-uploaded video chalao (simulated live feed).
  void _maybeStartVideo(CallProvider call) {
    if (_videoStarting || call.state != CallState.active || !mounted) return;
    _videoStarting = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.host.previewVideo.isNotEmpty) {
        _vp = VideoPlayerController.networkUrl(Uri.parse(widget.host.previewVideo));
        try {
          await _vp!.initialize();
        } catch (_) {
          // video load fail → photo fallback dikhta rahega, call chalti rahegi
        }
        if (mounted && _vp != null && _vp!.value.isInitialized) {
          await _vp!.setLooping(true);
          await _vp!.setVolume(0.6);
          await _vp!.play();
        }
        setState(() {});
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _vp?.dispose();
    _pulse.dispose();
    // Agar call abhi bhi active/ringing (user ne back dabaya) → silently end
    final call = context.read<CallProvider>();
    if (call.state == CallState.active || call.state == CallState.connecting) {
      call.forceEndIfActive();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _cancelRinging() async {
    final call = context.read<CallProvider>();
    await call.cancelConnecting();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _endCall() async {
    final call = context.read<CallProvider>();
    final rating = await _askRating();
    if (!mounted) return;
    await call.endCall(rating: rating);
    if (!mounted) return;
    await _showSummary();
    if (mounted) Navigator.of(context).pop();
  }

  Future<int?> _askRating() async {
    int stars = 5;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Call rating ⭐'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              5,
              (i) => IconButton(
                icon: Icon(i < stars ? Icons.star : Icons.star_border, color: AppTheme.warning, size: 34),
                onPressed: () => setD(() => stars = i + 1),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Skip')),
            ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Submit')),
          ],
        ),
      ),
    );
    return ok == true ? stars : null;
  }

  Future<void> _showSummary() async {
    final call = context.read<CallProvider>();
    final s = call.summary ?? {};
    final secs = (s['duration_seconds'] as num?)?.toInt() ?? call.elapsedSeconds;
    final cost = (s['total_cost'] as num?)?.toDouble() ?? call.totalCost;
    final xp = (s['xp_gained'] as num?)?.toInt() ?? 10;
    final auto = s['auto_end'] == true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(auto ? '📵 Call ended' : '📞 Call completed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (auto)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  s['reason'] == 'insufficient_balance' ? 'Balance khatam — call auto-end hui' : 'Call auto-end hui',
                  style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                ),
              ),
            _row('⏱ Duration', '${secs ~/ 60}m ${secs % 60}s'),
            _row('🪙 Coins spent', '$cost'),
            if (!auto) _row('✨ XP earned', '+$xp'),
          ],
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  /// Balance khatam hone pe top-up prompt — "Recharge Now" wallet khol deta hai.
  Future<void> _offerRecharge() async {
    final goRecharge = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('💰 Balance khatam!'),
        content: const Text(
          'Aapke coins khatam ho gaye, isliye call end ho gayi.\n\nRecharge karke phir se call karo! 🚀',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Baad mein')),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Text('🪙'),
            label: const Text('Recharge Now'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (goRecharge == true) {
      // Call screen ki jagah seedha Wallet — back dabane pe pichla screen wapas
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const WalletScreen()));
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: AppTheme.textMuted)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );

  // Auto-end by server → summary + (balance case me) recharge prompt
  void _maybeHandleAutoEnd(CallProvider call) {
    if (call.state == CallState.ended && call.summary != null && call.summary?['auto_end'] == true && mounted) {
      final reason = call.summary?['reason']?.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _showSummary();
        // Mark handled so it doesn't re-show
        call.summary?['auto_end'] = false;
        if (!mounted) return;
        if (reason == 'insufficient_balance') {
          await _offerRecharge();
        } else {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, call, _) {
        _maybeHandleAutoEnd(call);
        _maybeStartVideo(call); // active hote hi video start (10-sec ringing ke baad)
        final h = widget.host;
        final connecting = call.state == CallState.connecting;
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ---- Main visual: video (active) ya ringing UI (connecting) ----
                if (connecting)
                  _ringingView(h)
                else if (_vp != null && _vp!.value.isInitialized)
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _vp!.value.size.width,
                      height: _vp!.value.size.height,
                      child: VideoPlayer(_vp!),
                    ),
                  )
                else
                  Container(
                    color: AppTheme.cardAlt,
                    child: Center(
                      child: h.profilePic.isNotEmpty
                          ? CachedNetworkImage(imageUrl: h.profilePic, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                          : const Text('👤', style: TextStyle(fontSize: 100)),
                    ),
                  ),
                // Gradient top
                const IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black87, Colors.transparent, Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                // Top bar
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          call.state == CallState.active ? '🔴 ${call.timerText}' : '⏳ Calling…',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
                        child: Text('🪙 ${call.balance % 1 == 0 ? call.balance.toInt() : call.balance}',
                            style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
                // Low balance warning
                if (call.warning != null)
                  Positioned(
                    top: 60,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.danger.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('⚠️ ${call.warning}', textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                // Bottom controls
                Positioned(
                  bottom: 24,
                  left: 16,
                  right: 16,
                  child: Column(
                    children: [
                      Text('${h.name}  ·  🪙${call.pricePerMinute % 1 == 0 ? call.pricePerMinute.toInt() : call.pricePerMinute}/min',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
                      if (connecting)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('Ringing ke dauraan koi charge nahi lagega ✨',
                              style: TextStyle(fontSize: 11, color: Colors.white70, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
                        ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _roundBtn(
                            emoji: '🎁',
                            label: 'Gift',
                            bg: AppTheme.purple,
                            onTap: connecting
                                ? null
                                : () async {
                                    await showGiftSheet(context, hostId: h.id, callId: call.callId);
                                  },
                          ),
                          _roundBtn(
                            emoji: '📵',
                            label: connecting ? 'Cancel' : 'End',
                            bg: AppTheme.danger,
                            size: 72,
                            onTap: connecting ? _cancelRinging : (call.state == CallState.active ? _endCall : null),
                          ),
                          _roundBtn(
                            emoji: _vp != null && _vp!.value.volume > 0 ? '🔊' : '🔇',
                            label: 'Audio',
                            bg: AppTheme.cardAlt,
                            onTap: (connecting || _vp == null)
                                ? null
                                : () async {
                                    final v = _vp!.value.volume > 0 ? 0.0 : 0.6;
                                    await _vp!.setVolume(v);
                                    setState(() {});
                                  },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// "Calling… / Ringing…" view — host photo + pulsing rings (≈10 sec tak).
  Widget _ringingView(Host h) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F1B3A), AppTheme.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 210,
                  height: 210,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // expanding pulse rings
                      for (var i = 0; i < 2; i++)
                        Transform.scale(
                          scale: 0.75 + (((_pulse.value + i * 0.5) % 1.0) * 0.45),
                          child: Opacity(
                            opacity: 1.0 - ((_pulse.value + i * 0.5) % 1.0),
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primary, width: 2.5),
                              ),
                            ),
                          ),
                        ),
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.primary, width: 3),
                          color: AppTheme.cardAlt,
                          image: h.profilePic.isNotEmpty
                              ? DecorationImage(image: CachedNetworkImageProvider(h.profilePic), fit: BoxFit.cover)
                              : null,
                        ),
                        child: h.profilePic.isEmpty ? const Center(child: Text('👤', style: TextStyle(fontSize: 52))) : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(h.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                const _CallingDots(),
              ],
            ),
          },
        ),
      ),
    );
  }

  Widget _roundBtn({required String emoji, required String label, required Color bg, VoidCallback? onTap, double size = 60}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg.withOpacity(onTap == null ? 0.4 : 0.95)),
            child: Center(child: Text(emoji, style: TextStyle(fontSize: size * 0.42))),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ],
    );
  }
}

/// "Calling..." text ke aage animated dots.
class _CallingDots extends StatefulWidget {
  const _CallingDots();

  @override
  State<_CallingDots> createState() => _CallingDotsState();
}

class _CallingDotsState extends State<_CallingDots> {
  int _dots = 1;
  late final Stream<int> _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Stream.periodic(const Duration(milliseconds: 500), (i) => i);
    _ticker.listen((_) {
      if (mounted) setState(() => _dots = (_dots % 3) + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      'Calling${'.' * _dots} 📹',
      style: const TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 1),
    );
  }
}
