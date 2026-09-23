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

class CallScreen extends StatefulWidget {
  final Host host;
  const CallScreen({super.key, required this.host});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  VideoPlayerController? _vp;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    // Preview video loop as simulated video feed
    if (widget.host.previewVideo.isNotEmpty && mounted) {
      _vp = VideoPlayerController.networkUrl(Uri.parse(widget.host.previewVideo));
      await _vp!.initialize();
      if (mounted) {
        await _vp!.setLooping(true);
        await _vp!.setVolume(0.6);
        await _vp!.play();
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _vp?.dispose();
    // Agar call abhi bhi active (user ne back dabaya) → silently end (server settle kar lega)
    final call = context.read<CallProvider>();
    if (call.state == CallState.active) {
      call.forceEndIfActive();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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

  // Auto-end by server → pop after showing summary once
  void _maybeHandleAutoEnd(CallProvider call) {
    if (call.state == CallState.ended && call.summary != null && call.summary?['auto_end'] == true && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _showSummary();
        // Mark handled so it doesn't re-show
        call.summary?['auto_end'] = false;
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CallProvider>(
      builder: (context, call, _) {
        _maybeHandleAutoEnd(call);
        final h = widget.host;
        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Video feed (simulated)
                if (_vp != null && _vp!.value.isInitialized)
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
                          call.state == CallState.active ? '🔴 ${call.timerText}' : '⏳ Connecting…',
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
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _roundBtn(
                            emoji: '🎁',
                            label: 'Gift',
                            bg: AppTheme.purple,
                            onTap: () async {
                              await showGiftSheet(context, hostId: h.id, callId: call.callId);
                            },
                          ),
                          _roundBtn(
                            emoji: '📵',
                            label: 'End',
                            bg: AppTheme.danger,
                            size: 72,
                            onTap: call.state == CallState.active ? _endCall : null,
                          ),
                          _roundBtn(
                            emoji: _vp != null && _vp!.value.volume > 0 ? '🔊' : '🔇',
                            label: 'Audio',
                            bg: AppTheme.cardAlt,
                            onTap: _vp == null
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
