import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/host_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../call/call_screen.dart';
import '../gifts/gift_sheet.dart';
import 'host_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final PageController _page = PageController();
  final ScrollController _gridScroll = ScrollController();
  bool _gridMode = false;
  String? _likedHostId;

  @override
  void initState() {
    super.initState();
    _gridScroll.addListener(() {
      if (_gridScroll.position.pixels > _gridScroll.position.maxScrollExtent - 300) {
        context.read<HostProvider>().loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HostProvider>().loadInitial();
    });
  }

  @override
  void dispose() {
    _page.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  void _pass() {
    if (_page.hasClients) {
      _page.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    }
  }

  void _like(Host h) {
    setState(() => _likedHostId = h.id);
    Future.delayed(const Duration(milliseconds: 550), () {
      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => HostDetailScreen(host: h)))
          .then((_) {
        if (mounted) setState(() => _likedHostId = null);
      });
    });
  }

  Future<void> _callHost(Host h) async {
    if (!await requireRegistered(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CallScreen(host: h)));
  }

  Future<void> _giftHost(Host h) async {
    if (!await requireRegistered(context)) return;
    if (!mounted) return;
    await showGiftSheet(context, hostId: h.id);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Custom dating header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 14, 6),
                child: Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => AppTheme.brandGradient.createShader(b),
                      child: const Text('VibeCall',
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5)),
                    ),
                    const Text('  🔥', style: TextStyle(fontSize: 20)),
                    const Spacer(),
                    IconButton(
                      tooltip: _gridMode ? 'Swipe mode' : 'Grid mode',
                      icon: Icon(_gridMode ? Icons.style : Icons.grid_view_rounded, color: AppTheme.textMuted),
                      onPressed: () => setState(() => _gridMode = !_gridMode),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh, color: AppTheme.textMuted),
                      onPressed: () => context.read<HostProvider>().refresh(),
                    ),
                    CoinChip(auth.balance),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<HostProvider>(
                  builder: (context, hp, _) {
                    if (hp.loading && hp.hosts.isEmpty) {
                      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                    }
                    if (hp.error != null && hp.hosts.isEmpty) {
                      return EmptyView(emoji: '📡', title: 'Server se connect nahi hua', subtitle: hp.error);
                    }
                    if (hp.hosts.isEmpty) {
                      return const EmptyView(emoji: '💔', title: 'Koi hosts nahi mile', subtitle: 'Refresh karke dekho');
                    }
                    return _gridMode ? _GridFeed(hp: hp, scroll: _gridScroll) : _SwipeFeed();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== SWIPE MODE =====================
  Widget _SwipeFeed() {
    final hp = context.read<HostProvider>();
    return Stack(
      children: [
        PageView.builder(
          controller: _page,
          scrollDirection: Axis.vertical,
          physics: const BouncingScrollPhysics(),
          itemCount: hp.hosts.length,
          onPageChanged: (i) {
            if (i >= hp.hosts.length - 2) hp.loadMore();
          },
          itemBuilder: (context, i) => _SwipeCard(
            host: hp.hosts[i],
            liked: _likedHostId == hp.hosts[i].id,
            onPass: _pass,
            onLike: () => _like(hp.hosts[i]),
            onCall: () => _callHost(hp.hosts[i]),
            onGift: () => _giftHost(hp.hosts[i]),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => HostDetailScreen(host: hp.hosts[i])),
            ),
          ),
        ),
      ],
    );
  }
}

class _SwipeCard extends StatelessWidget {
  final Host host;
  final bool liked;
  final VoidCallback onPass;
  final VoidCallback onLike;
  final VoidCallback onCall;
  final VoidCallback onGift;
  final VoidCallback onTap;

  const _SwipeCard({
    required this.host,
    required this.liked,
    required this.onPass,
    required this.onLike,
    required this.onCall,
    required this.onGift,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: AppTheme.cardAlt,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo
            host.profilePic.isNotEmpty
                ? CachedNetworkImage(imageUrl: host.profilePic, fit: BoxFit.cover)
                : Container(color: AppTheme.cardAlt, child: const Center(child: Text('💃', style: TextStyle(fontSize: 100)))),
            const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.photoOverlay))),

            // Top: online + price
            Positioned(
              top: 16,
              left: 16,
              child: GlassPill(
                host.isOnline ? '● Online' : '● Offline',
                color: host.isOnline ? AppTheme.success.withOpacity(0.25) : Colors.black38,
                textColor: host.isOnline ? AppTheme.success : AppTheme.textMuted,
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: GlassPill(
                '🪙 ${host.pricePerMinute % 1 == 0 ? host.pricePerMinute.toInt() : host.pricePerMinute}/min',
                color: Colors.black54,
                textColor: AppTheme.warning,
              ),
            ),

            // Bottom info + actions
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        '${host.name}, ${host.age ?? '?'}',
                        style: const TextStyle(
                            fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(blurRadius: 8, color: Colors.black)]),
                      ),
                      if (host.isFeatured) const GlassPill('⭐', color: AppTheme.warning, textColor: Colors.black),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('⭐ ${host.rating}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 10),
                      const GlassPill('video call', color: Colors.black38),
                      if (host.language != null && host.language!.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(host.language!,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                      ],
                    ],
                  ),
                  if (host.interests.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(host.interests.take(3).join('  •  '),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                  const SizedBox(height: 16),
                  // Dating action row: pass / gift / call / like
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundAction(emoji: '✖️', size: 54, bg: Colors.white, onTap: onPass),
                      _RoundAction(emoji: '🎁', size: 48, bg: AppTheme.purple, onTap: onGift),
                      _RoundAction(emoji: '📹', size: 66, bg: AppTheme.primary, glow: true, onTap: host.isOnline ? onCall : null),
                      _RoundAction(emoji: '❤️', size: 54, bg: AppTheme.success, onTap: onLike),
                    ],
                  ),
                ],
              ),
            ),

            // Like burst overlay 💘
            if (liked)
              IgnorePointer(
                child: Container(
                  color: AppTheme.primary.withOpacity(0.18),
                  child: const Center(child: Text('❤️', style: TextStyle(fontSize: 130, shadows: [Shadow(blurRadius: 30, color: Colors.black54)]))),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final String emoji;
  final double size;
  final Color bg;
  final VoidCallback? onTap;
  final bool glow;

  const _RoundAction({required this.emoji, required this.size, required this.bg, this.onTap, this.glow = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
            boxShadow: glow
                ? [BoxShadow(color: AppTheme.primary.withOpacity(0.6), blurRadius: 20, spreadRadius: 2)]
                : [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Center(child: Text(emoji, style: TextStyle(fontSize: size * 0.42))),
        ),
      ),
    );
  }
}

// ===================== GRID MODE =====================
class _GridFeed extends StatelessWidget {
  final HostProvider hp;
  final ScrollController scroll;
  const _GridFeed({required this.hp, required this.scroll});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: hp.refresh,
      child: CustomScrollView(
        controller: scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _FilterBar(hp: hp)),
          if (hp.featured.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionTitle('⭐ Featured')),
            SliverToBoxAdapter(child: _FeaturedRow(hosts: hp.featured)),
          ],
          const SliverToBoxAdapter(child: SectionTitle('💘 Everyone')),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) => HostCard(
                  host: hp.hosts[i],
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostDetailScreen(host: hp.hosts[i]))),
                ),
                childCount: hp.hosts.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.72,
              ),
            ),
          ),
          if (hp.loadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _FeaturedRow extends StatelessWidget {
  final List hosts;
  const _FeaturedRow({required this.hosts});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: hosts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final h = hosts[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostDetailScreen(host: h))),
            child: Container(
              width: 155,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primary.withOpacity(0.6), width: 1.6),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  h.profilePic.isNotEmpty
                      ? CachedNetworkImage(imageUrl: h.profilePic, fit: BoxFit.cover)
                      : Container(color: AppTheme.cardAlt, child: const Center(child: Text('💃', style: TextStyle(fontSize: 48)))),
                  const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.photoOverlay))),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.white)),
                        Text('🪙 ${h.pricePerMinute % 1 == 0 ? h.pricePerMinute.toInt() : h.pricePerMinute}/min · ⭐ ${h.rating}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.warning)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final HostProvider hp;
  const _FilterBar({required this.hp});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            _mini(hp.sortBy == 'created_at' ? '✨ New' : hp.sortBy == 'price_per_minute' ? '💰 Price' : hp.sortBy == 'level' ? '🏆 Level' : '🔤 A-Z', () {
              _cycleSort(hp);
            }, active: true),
            _mini('👩 Female', () => hp.setGender('female'), active: hp.gender == 'female'),
            _mini('👨 Male', () => hp.setGender('male'), active: hp.gender == 'male'),
            ...hp.interests.take(6).map((it) => _mini(it, () => hp.setInterest(it), active: hp.interest == it)),
          ],
        ),
      ),
    );
  }

  void _cycleSort(HostProvider hp) {
    const order = ['created_at', 'price_per_minute', 'level', 'name'];
    final i = order.indexOf(hp.sortBy);
    hp.setSort(order[(i + 1) % order.length]);
  }

  Widget _mini(String label, VoidCallback onTap, {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
