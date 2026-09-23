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
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔒', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('Guests can\'t use this feature', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Calls, gifts aur wallet ke liye register karo', style: TextStyle(color: AppTheme.textMuted)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Unlock full account'),
            ),
          ),
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

  void _startCall() async {
    if (!await requireRegistered(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(host: h)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 380,
            pinned: true,
            title: Text(h.name),
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
                                const Center(
                                  child: Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
                                ),
                            ],
                          ),
                        )
                      : h.profilePic.isNotEmpty
                          ? CachedNetworkImage(imageUrl: h.profilePic, fit: BoxFit.cover)
                          : Container(color: AppTheme.cardAlt, child: const Center(child: Text('👤', style: TextStyle(fontSize: 90)))),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black54],
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                      ),
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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${h.name}, ${h.age ?? '?'} ${h.genderEmoji}',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: h.isOnline ? AppTheme.success : AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(h.isOnline ? 'Online now' : 'Offline',
                                    style: TextStyle(fontSize: 13, color: h.isOnline ? AppTheme.success : AppTheme.textMuted)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      LevelBadge(level: h.level, title: h.levelTitle),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _stat('⭐ ${h.rating}', '${h.reviewCount} reviews'),
                      const SizedBox(width: 10),
                      _stat('📞 ${h.totalCalls}', 'calls'),
                      const SizedBox(width: 10),
                      _stat('🪙 ${h.pricePerMinute % 1 == 0 ? h.pricePerMinute.toInt() : h.pricePerMinute}', 'per min'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (h.bio.isNotEmpty) ...[
                    const Text('About', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 6),
                    Text(h.bio, style: const TextStyle(color: AppTheme.textMuted, height: 1.5)),
                  ],
                  if (h.interests.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Interests', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: h.interests
                          .map((i) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.purple.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppTheme.purple.withOpacity(0.4)),
                                ),
                                child: Text(i, style: const TextStyle(fontSize: 12, color: Color(0xFFB4AEF7))),
                              ))
                          .toList(),
                    ),
                  ],
                  if (h.language != null && h.language!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('🗣 ${h.language}', style: const TextStyle(color: AppTheme.textMuted)),
                  ],
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        color: AppTheme.card,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (!await requireRegistered(context)) return;
                    if (!context.mounted) return;
                    await showGiftSheet(context, hostId: h.id);
                  },
                  icon: const Text('🎁'),
                  label: const Text('Gift'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: h.isOnline ? _startCall : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.cardAlt,
                  ),
                  icon: const Text('📹'),
                  label: Text(h.isOnline ? 'Video Call · 🪙${h.pricePerMinute % 1 == 0 ? h.pricePerMinute.toInt() : h.pricePerMinute}/min' : 'Offline'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }
}
