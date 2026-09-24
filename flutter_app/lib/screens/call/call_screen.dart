import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/models.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/call_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/recharge_prompt.dart';
import '../../widgets/widgets.dart';
import '../gifts/gift_sheet.dart';

/// Full call experience (outgoing or accepted incoming):
///
///  1. "Calling… / Connecting…" screen for ~10s (admin configurable, not billed)
///  2. Host's admin-uploaded video starts playing = the video call
///  3. Wallet deducted continuously at the host's rate (live balance on screen)
///  4. Balance exhausted → call auto-ends → recharge prompt
class CallScreen extends StatefulWidget {
  final Host host;
  final bool incoming;
  const CallScreen({super.key, required this.host, this.incoming = false});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late final CallProvider _call;
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  VideoPlayerController? _vp;
  bool _videoFailed = false;
  bool _started = false;
  bool _handledEnd = false;
  bool _closing = false;

  Host get h => widget.host;

  @override
  void initState() {
    super.initState();
    _call = context.read<CallProvider>();
    _call.addListener(_onCallChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    await context.read<AppSettingsProvider>().load();
    if (!mounted) return;
    try {
      await _call.startCall(h, incoming: widget.incoming);
    } on InsufficientBalanceException catch (e) {
      if (!mounted) return;
      await showRechargePrompt(context, message: e.message, requiredCoins: h.pricePerMinute);
      _close();
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      showSnack(context, e.message, error: true);
      _close();
      return;
    } catch (_) {
      if (!mounted) return;
      showSnack(context, 'Call connect nahi ho payi', error: true);
      _close();
      return;
    }
    // Connecting screen ke dauraan hi video preload karo — 10s pe turant start ho
    _prepareVideo();
  }

  Future<void> _prepareVideo() async {
    final url = _call.callVideoUrl.isNotEmpty ? _call.callVideoUrl : h.playableCallVideo;
    if (url.isEmpty) {
      setState(() => _videoFailed = true);
      return;
    }
    final vp = VideoPlayerController.networkUrl(Uri.parse(url));
    _vp = vp;
    try {
      await vp.initialize();
      await vp.setLooping(true);
      await vp.setVolume(1.0);
      if (!mounted || _vp != vp) return;
      if (_call.state == CallState.active) await vp.play();
      setState(() {});
    } catch (_) {
      if (mounted) setState(() => _videoFailed = true);
    }
  }

  void _onCallChanged() {
    if (!mounted) return;
    final vp = _vp;
    if (_call.state == CallState.active && vp != null && vp.value.isInitialized && !vp.value.isPlaying) {
      vp.play();
    }
    if (_call.state == CallState.ended && !_handledEnd) {
      final reason = _call.endReason;
      if (reason == CallEndReason.insufficientBalance ||
          reason == CallEndReason.connectionLost ||
          reason == CallEndReason.error) {
        _handledEnd = true;
        vp?.pause();
        WidgetsBinding.instance.addPostFrameCallback((_) => _handleAutoEnd(reason!));
      }
    }
  }

  Future<void> _handleAutoEnd(String reason) async {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    if (reason == CallEndReason.error && (_call.summary?['duration_seconds'] ?? 0) == 0) {
      showSnack(context, _call.endMessage ?? 'Call end ho gayi', error: true);
      _close();
      return;
    }
    await _showSummary();
    if (!mounted) return;
    if (reason == CallEndReason.insufficientBalance) {
      await showRechargePrompt(context, exhausted: true, message: _call.endMessage);
    }
    _close();
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _call.removeListener(_onCallChanged);
    _pulse.dispose();
    _vp?.dispose();
    // Call kabhi background me chalti na rahe (back button etc.).
    // Microtask: widget tree unlock hone ke baad listeners notify hon.
    final call = _call;
    Future.microtask(call.leaveScreen);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _cancel() async {
    await _call.cancelCall();
    _close();
  }

  Future<void> _endCall() async {
    _handledEnd = true;
    _vp?.pause();
    final rating = await _askRating();
    if (!mounted) return;
    await _call.endCall(rating: rating);
    if (!mounted) return;
    await _showSummary();
    if (!mounted) return;
    if (_call.endReason == CallEndReason.insufficientBalance) {
      await showRechargePrompt(context, exhausted: true);
    }
    _close();
  }

  Future<bool> _onWillPop() async {
    if (_call.state == CallState.connecting) {
      await _cancel();
      return false;
    }
    if (_call.state == CallState.active) {
      await _endCall();
      return false;
    }
    return true;
  }

  Future<int?> _askRating() async {
    int stars = 5;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('${h.name} ke saath call kaisi rahi? ⭐'),
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
    final s = _call.summary ?? {};
    final secs = (s['duration_seconds'] as num?)?.toInt() ?? _call.elapsedSeconds;
    final cost = (s['total_cost'] as num?)?.toDouble() ?? _call.totalCost;
    final xp = (s['xp_gained'] as num?)?.toInt();
    final reason = _call.endReason;
    final exhausted = reason == CallEndReason.insufficientBalance;
    final lost = reason == CallEndReason.connectionLost;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(exhausted ? '🪫 Call ended' : (lost ? '📶 Call disconnected' : '📞 Call completed')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (exhausted || lost)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  exhausted ? 'Wallet balance khatam ho gaya — call automatically end ho gayi.' : 'Connection lost — call end ho gayi.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                ),
              ),
            _row('👤 Host', h.name),
            _row('⏱ Duration', '${secs ~/ 60}m ${secs % 60}s'),
            _row('🪙 Coins spent', cost % 1 == 0 ? cost.toInt().toString() : cost.toStringAsFixed(2)),
            _row('💰 Balance left', _fmt(_call.balance)),
            if (xp != null && xp > 0) _row('✨ XP earned', '+$xp'),
          ],
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
      ),
    );
  }

  static String _fmt(double v) => v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(2);

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(width: 12),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800))),
          ],
        ),
      );

  // ==========================================================================
  // UI
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Consumer<CallProvider>(
        builder: (context, call, _) {
          final connecting = call.state == CallState.connecting || (call.state == CallState.idle && !_closing);
          return Scaffold(
            backgroundColor: Colors.black,
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              child: connecting ? _connectingView(call) : _activeView(call),
            ),
          );
        },
      ),
    );
  }

  Widget _avatarBg() {
    return h.profilePic.isNotEmpty
        ? CachedNetworkImage(imageUrl: h.profilePic, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
        : Container(color: AppTheme.cardAlt);
  }

  Widget _connectingView(CallProvider call) {
    final total = call.connectingTotal <= 0 ? 1 : call.connectingTotal;
    final left = call.state == CallState.connecting ? call.connectingLeft : total;
    final firstHalf = left > total / 2;
    final status = widget.incoming ? 'Connecting…' : (firstHalf ? 'Calling…' : 'Connecting…');
    return Stack(
      key: const ValueKey('connecting'),
      fit: StackFit.expand,
      children: [
        ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: _avatarBg()),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black.withOpacity(0.55), AppTheme.bg.withOpacity(0.92)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 18),
              Text(widget.incoming ? '📲 Incoming video call' : '📹 Video call',
                  style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
              const Spacer(),
              SizedBox(
                width: 240,
                height: 240,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Stack(
                    alignment: Alignment.center,
                    children: [
                      for (int i = 0; i < 3; i++) _ring((_pulse.value + i / 3) % 1.0),
                      Container(
                        width: 132,
                        height: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          color: AppTheme.cardAlt,
                          image: h.profilePic.isNotEmpty
                              ? DecorationImage(image: CachedNetworkImageProvider(h.profilePic), fit: BoxFit.cover)
                              : null,
                        ),
                        child: h.profilePic.isEmpty ? const Center(child: Text('👤', style: TextStyle(fontSize: 60))) : null,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(h.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(status,
                    key: ValueKey(status),
                    style: const TextStyle(fontSize: 17, color: Colors.white70, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 70),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: call.state == CallState.connecting ? (total - left) / total : 0,
                    minHeight: 5,
                    color: AppTheme.primary,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(20)),
                child: Text('🪙 ${h.priceLabel}/min  ·  Balance 🪙${_fmt(call.balance)}',
                    style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              // Call button dabate hi backend se aaya host ka message (Inbox me bhi save)
              if (call.hostMessage != null) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('💬', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(call.hostMessage!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 44),
                child: _roundBtn(
                  emoji: '📵',
                  label: 'Cancel',
                  bg: AppTheme.danger,
                  size: 74,
                  onTap: call.state == CallState.connecting ? _cancel : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ring(double t) {
    final size = 132 + 108 * t;
    return Opacity(
      opacity: (1.0 - t) * 0.5,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.primary, width: 2)),
      ),
    );
  }

  Widget _activeView(CallProvider call) {
    final vp = _vp;
    final videoReady = vp != null && vp.value.isInitialized && !_videoFailed;
    return SafeArea(
      key: const ValueKey('active'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Host video (admin-uploaded) = the video call
          if (videoReady)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(width: vp!.value.size.width, height: vp!.value.size.height, child: VideoPlayer(vp!)),
            )
          else
            Stack(
              fit: StackFit.expand,
              children: [
                _avatarBg(),
                Center(
                  child: _videoFailed
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
                          child: const Text('🎥 Video unavailable', style: TextStyle(color: Colors.white70)),
                        )
                      : const CircularProgressIndicator(color: AppTheme.primary),
                ),
              ],
            ),
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
          // Top bar: timer + live wallet
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _pill(call.state == CallState.active ? '🔴 ${call.timerText}' : '⏹ ${call.timerText}'),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _pill('🪙 ${call.balance.toStringAsFixed(call.balance >= 100 ? 0 : 1)}', color: AppTheme.warning),
                    if (call.state == CallState.active) ...[
                      const SizedBox(height: 4),
                      Text('−🪙${call.totalCost.toStringAsFixed(2)} · ${call.remainingText} left',
                          style: const TextStyle(fontSize: 11, color: Colors.white70, shadows: [Shadow(blurRadius: 6, color: Colors.black)])),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Low balance warning
          if (call.lowBalance)
            Positioned(
              top: 74,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(color: AppTheme.danger.withOpacity(0.92), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('⚠️ Low balance! Sirf ${call.remainingText} ki call baaki hai',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTheme.danger,
                          padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
                      onPressed: () => openWallet(context),
                      child: const Text('Recharge', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
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
                      onTap: call.state == CallState.active
                          ? () => showGiftSheet(context, hostId: h.id, callId: call.callId)
                          : null,
                    ),
                    _roundBtn(
                      emoji: '📵',
                      label: 'End',
                      bg: AppTheme.danger,
                      size: 72,
                      onTap: call.state == CallState.active ? _endCall : null,
                    ),
                    _roundBtn(
                      emoji: vp != null && vp.value.volume > 0 ? '🔊' : '🔇',
                      label: 'Audio',
                      bg: AppTheme.cardAlt,
                      onTap: vp == null
                          ? null
                          : () async {
                              await vp.setVolume(vp.value.volume > 0 ? 0.0 : 1.0);
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
    );
  }

  Widget _pill(String text, {Color color = Colors.white}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
      );

  Widget _roundBtn({required String emoji, required String label, required Color bg, VoidCallback? onTap, double size = 60}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
