import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/host_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/recharge_prompt.dart';
import '../../widgets/widgets.dart';
import '../auth/convert_guest_screen.dart';
import '../call/call_screen.dart';
import '../chat/chat_screen.dart';
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
  late Host h = widget.host;
  final _headerPage = PageController();
  int _headerIndex = 0;

  @override
  void initState() {
    super.initState();
    _initHeaderVideo();
    // List wala host data purana ho sakta hai — latest profile (photos/videos/price) lao
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final fresh = await context.read<HostProvider>().hostDetail(h.id);
        if (!mounted) return;
        final videoChanged = fresh.previewVideo != h.previewVideo;
        setState(() => h = fresh);
        if (videoChanged) {
          _vp?.dispose();
          _vp = null;
          _initHeaderVideo();
        }
      } catch (_) {}
    });
  }

  void _initHeaderVideo() {
    if (h.previewVideo.isEmpty) return;
    final vp = VideoPlayerController.networkUrl(Uri.parse(h.previewVideo));
    _vp = vp;
    vp.initialize().then((_) {
      if (mounted && _vp == vp) {
        setState(() {});
        vp.setLooping(true);
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _vp?.dispose();
    _headerPage.dispose();
    super.dispose();
  }

  Future<void> _startCall() async {
    if (!await requireRegistered(context)) return;
    if (!mounted) return;
    _vp?.pause();
    final balance = context.read<AuthProvider>().balance;
    if (balance < h.pricePerMinute) {
      await showRechargePrompt(
        context,
        requiredCoins: h.pricePerMinute,
        message: '${h.name} ko call karne ke liye kam se kam 🪙${h.priceLabel} (1 minute) chahiye. Wallet recharge karein.',
      );
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(host: h)));
  }

  void _openChat() {
    _vp?.pause();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(hostId: h.id, pushed: true)));
  }

  void _openPhotos(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PhotoViewer(images: h.galleryImages, initial: index),
    ));
  }

  void _openVideo(String url) {
    _vp?.pause();
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _VideoViewer(url: url, title: h.name),
    ));
  }

  Widget _header() {
    final vp = _vp;
    if (h.previewVideo.isNotEmpty && vp != null && vp.value.isInitialized) {
      return GestureDetector(
        onTap: () {
          vp.value.isPlaying ? vp.pause() : vp.play();
          setState(() {});
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(width: vp.value.size.width, height: vp.value.size.height, child: VideoPlayer(vp)),
            ),
            if (!vp.value.isPlaying)
              const Center(child: Icon(Icons.play_circle_fill, size: 72, color: Colors.white70)),
          ],
        ),
      );
    }
    final imgs = h.galleryImages;
    if (imgs.isEmpty) {
      return Container(color: AppTheme.cardAlt, child: const Center(child: Text('👤', style: TextStyle(fontSize: 90))));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _headerPage,
          itemCount: imgs.length,
          onPageChanged: (i) => setState(() => _headerIndex = i),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _openPhotos(i),
            child: CachedNetworkImage(imageUrl: imgs[i], fit: BoxFit.cover),
          ),
        ),
        if (imgs.length > 1)
          Positioned(
            bottom: 14,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                imgs.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _headerIndex ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _headerIndex ? Colors.white : Colors.white54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = h.galleryImages;
    final videos = h.galleryVideos;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            title: Text(h.name),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _header(),
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.transparent, Colors.black54],
                          begin: Alignment.center,
                          end: Alignment.bottomCenter,
                        ),
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
                                if (h.city.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  Text('📍 ${h.city}', style: const TextStyle(fontSize: 13, color: AppTheme.textMuted)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      LevelBadge(level: h.level, title: h.levelTitle),
                    ],
                  ),
                  if (h.bio.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(h.bio, style: const TextStyle(color: AppTheme.textMain, fontStyle: FontStyle.italic, height: 1.4)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _stat('⭐ ${h.rating}', '${h.reviewCount} reviews'),
                      const SizedBox(width: 10),
                      _stat('📞 ${h.totalCalls}', 'calls'),
                      const SizedBox(width: 10),
                      _stat('🪙 ${h.priceLabel}', 'per min'),
                    ],
                  ),
                  if (h.description.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('About', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 6),
                    Text(h.description, style: const TextStyle(color: AppTheme.textMuted, height: 1.5)),
                  ],
                  if (photos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Photos (${photos.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => _openPhotos(i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(imageUrl: photos[i], width: 95, height: 120, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (videos.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Videos (${videos.length})', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: videos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => _openVideo(videos[i]),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              children: [
                                h.profilePic.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: photos.isNotEmpty ? photos[i % photos.length] : h.profilePic,
                                        width: 160,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        color: Colors.black38,
                                        colorBlendMode: BlendMode.darken,
                                      )
                                    : Container(width: 160, height: 120, color: AppTheme.cardAlt),
                                const Positioned.fill(
                                  child: Center(child: Icon(Icons.play_circle_fill, size: 44, color: Colors.white)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (h.interests.isNotEmpty) ...[
                    const SizedBox(height: 20),
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
                  const SizedBox(height: 100),
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
              _squareBtn('🎁', 'Gift', () async {
                if (!await requireRegistered(context)) return;
                if (!context.mounted) return;
                await showGiftSheet(context, hostId: h.id);
              }),
              if (h.hasBot) ...[
                const SizedBox(width: 10),
                _squareBtn('💬', 'Chat', _openChat),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: h.isOnline ? _startCall : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.cardAlt,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  icon: const Text('📹'),
                  label: Text(h.isOnline ? 'Video Call · 🪙${h.priceLabel}/min' : 'Offline'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _squareBtn(String emoji, String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 17)),
          Text(label, style: const TextStyle(fontSize: 10.5)),
        ],
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

/// Fullscreen swipeable photo viewer with pinch-zoom.
class _PhotoViewer extends StatefulWidget {
  final List<String> images;
  final int initial;
  const _PhotoViewer({required this.images, this.initial = 0});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pc = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${_index + 1} / ${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 4,
          child: Center(child: CachedNetworkImage(imageUrl: widget.images[i], fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

/// Fullscreen video player for admin-uploaded host videos.
class _VideoViewer extends StatefulWidget {
  final String url;
  final String title;
  const _VideoViewer({required this.url, required this.title});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _vp = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _vp.initialize().then((_) {
      if (!mounted) return;
      _vp.setLooping(true);
      _vp.play();
      setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    _vp.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vp.removeListener(_onTick);
    _vp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.title)),
      body: Center(
        child: _failed
            ? const Text('🎥 Video load nahi ho payi', style: TextStyle(color: Colors.white70))
            : !_vp.value.isInitialized
                ? const CircularProgressIndicator(color: AppTheme.primary)
                : GestureDetector(
                    onTap: () => _vp.value.isPlaying ? _vp.pause() : _vp.play(),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(aspectRatio: _vp.value.aspectRatio, child: VideoPlayer(_vp)),
                        if (!_vp.value.isPlaying) const Icon(Icons.play_circle_fill, size: 72, color: Colors.white70),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: VideoProgressIndicator(_vp, allowScrubbing: true, colors: const VideoProgressColors(playedColor: AppTheme.primary)),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}
