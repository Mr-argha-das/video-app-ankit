import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../auth/convert_guest_screen.dart';
import '../call/call_screen.dart';
import '../gifts/gift_sheet.dart';

/// Guest restricted actions pe upgrade sheet.
Future<bool> requireRegistered(BuildContext context) async {
  final auth = context.read<AuthProvider>();
  if (!auth.isGuest) return true;
  final go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔒💘', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('Guests can\'t use this feature', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Calls, gifts aur wallet ke liye register karo', style: TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 20),
          GradientButton(label: 'Unlock full account', emoji: '🚀', onPressed: () => Navigator.of(ctx).pop(true)),
        ],
      ),
    ),
  );
  if (go == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConvertGuestScreen()));
  }
  return context.mounted ? !context.read<AuthProvider>().isGuest : false;
}

class HostDetailScreen extends StatefulWidget {
  final Host host;
  const HostDetailScreen({super.key, required this.host});

  @override
  State<HostDetailScreen> createState() => _HostDetailScreenState();
}

class _HostDetailScreenState extends State<HostDetailScreen> {
  VideoPlayerController? _vp;

  Host get h => widget.host;

  @override
  void initState() {
    super.initState();
    if (h.previewVideo.isNotEmpty) {
      _vp = VideoPlayerController.networkUrl(Uri.parse(h.previewVideo))
        ..initialize().then((_) {
          if (mounted) {
            setState(() {});
            _vp?.setLooping(true);
          }
        });
    }
  }

  @override
  void dispose() {
    _vp?.dispose();
    super.dispose();
  }

  Future<void> _startCall() async {
    if (!await requireRegistered(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(host: h)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 480,
              pinned: true,
              backgroundColor: AppTheme.bg,
              title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w900)),
              actions: [
                if (h.isFeatured)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Center(child: GlassPill('⭐ Featured', color: AppTheme.warning, textColor: Colors.black)),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    h.previewVideo.isNotEmpty && _vp != null && _vp!.value.isInitialized
                        ? GestureDetector(
                            onTap: () => setState(() => _vp!.value.isPlaying ? _vp!.pause() : _vp!.play()),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _vp!.value.size.width,
                                    height: _vp!.value.size.height,
                                    child: VideoPlayer(_vp!),
                                  ),
                                ),
                                if (!_vp!.value.isPlaying)
                                  const Center(child: Icon(Icons.play_circle_fill, size: 78, color: Colors.white70)),
                              ],
                            ),
                          )
                        : h.profilePic.isNotEmpty
                            ? CachedNetworkImage(imageUrl: h.profilePic, fit: BoxFit.cover)
                            : Container(color: AppTheme.cardAlt, child: const Center(child: Text('💃', style: TextStyle(fontSize: 100)))),
                    const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.photoOverlay))),
                    // Bottom overlaid name block (dating style)
                    Positioned(
                      left: 20,
                      right: 20,
                      bottom: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${h.name}, ${h.age ?? '?'}',
                              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white,
                                  shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              GlassPill(
                                h.isOnline ? '● Online' : '● Offline',
                                color: h.isOnline ? AppTheme.success.withOpacity(0.25) : Colors.black38,
                                textColor: h.isOnline ? AppTheme.success : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 8),
                              GlassPill('⭐ ${h.rating} (${h.reviewCount})', color: Colors.black45),
                              const SizedBox(width: 8),
                              GlassPill('Lv.${h.level} ${h.levelTitle}', color: AppTheme.purple.withOpacity(0.45)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats row
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _stat('🪙', '${h.pricePerMinute % 1 == 0 ? h.pricePerMinute.toInt() : h.pricePerMinute}', 'per min'),
                          _divider(),
                          _stat('📞', '${h.totalCalls}', 'calls'),
                          _divider(),
                          _stat('⏱', '${h.totalMinutes}m', 'on cam'),
                          _divider(),
                          _stat('👀', h.genderEmoji, h.gender.isEmpty ? '—' : h.gender),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (h.bio.isNotEmpty) ...[
                      const Text('💫 About me', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                      const SizedBox(height: 8),
                      Text(h.bio, style: const TextStyle(color: AppTheme.textMuted, height: 1.55, fontSize: 14.5)),
                    ],
                    if (h.interests.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text('❤️ Passions', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: h.interests
                            .map((i) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: AppTheme.primary.withOpacity(0.5)),
                                  ),
                                  child: Text(i, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
                                ))
                            .toList(),
                      ),
                    ],
                    if (h.language != null && h.language!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text('🗣 Languages', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                      const SizedBox(height: 6),
                      Text(h.language!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 14.5)),
                    ],
                    const SizedBox(height: 110),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Floating bottom CTA — dating style
      bottomSheet: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              GestureDetector(
                onTap: () async {
                  if (!await requireRegistered(context)) return;
                  if (!context.mounted) return;
                  await showGiftSheet(context, hostId: h.id);
                },
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.purple,
                    boxShadow: [BoxShadow(color: AppTheme.purple.withOpacity(0.5), blurRadius: 14)],
                  ),
                  child: const Center(child: Text('🎁', style: TextStyle(fontSize: 26))),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: GradientButton(
                  emoji: '📹',
                  label: h.isOnline
                      ? 'Video Call · 🪙${h.pricePerMinute % 1 == 0 ? h.pricePerMinute.toInt() : h.pricePerMinute}/min'
                      : 'Offline abhi',
                  onPressed: h.isOnline ? _startCall : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ],
    );
  }

  Widget _divider() => Container(width: 1, height: 34, color: AppTheme.border);
}
