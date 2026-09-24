import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/host_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import 'host_detail_screen.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        context.read<HostProvider>().loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HostProvider>().loadInitial();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎥 VideoCall', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: CoinChip(auth.balance)),
          ),
        ],
      ),
      body: Consumer<HostProvider>(
        builder: (context, hp, _) {
          if (hp.loading && hp.hosts.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (hp.error != null && hp.hosts.isEmpty) {
            return EmptyView(
              emoji: '📡',
              title: 'Server se connect nahi ho paya',
              subtitle: hp.error,
            );
          }
          return RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: hp.refresh,
            child: CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Featured banner
                if (hp.featured.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionTitle('⭐ Featured Hosts')),
                  SliverToBoxAdapter(child: _FeaturedRow(hosts: hp.featured)),
                ],
                // Filters
                SliverToBoxAdapter(child: _FilterBar(hp: hp)),
                const SliverToBoxAdapter(child: SectionTitle('All Hosts')),
                // Grid
                if (hp.hosts.isEmpty)
                  const SliverToBoxAdapter(
                    child: EmptyView(emoji: '📭', title: 'Koi hosts nahi mile', subtitle: 'Filters change karke dekho'),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => HostCard(
                          host: hp.hosts[i],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => HostDetailScreen(host: hp.hosts[i])),
                          ),
                        ),
                        childCount: hp.hosts.length,
                      ),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.66,
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
        },
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
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: hosts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final h = hosts[i];
          return GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HostDetailScreen(host: h))),
            child: Container(
              width: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primary.withOpacity(0.5), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  h.profilePic.isNotEmpty
                      ? CachedNetworkImage(imageUrl: h.profilePic, fit: BoxFit.cover)
                      : Container(color: AppTheme.cardAlt, child: const Center(child: Text('👤', style: TextStyle(fontSize: 48)))),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.transparent, Colors.black87],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
    return Column(
      children: [
        if (hp.interests.isNotEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 16, top: 8),
              children: [
                ...hp.interests.map(
                  (it) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(it),
                      selected: hp.interest == it,
                      onSelected: (_) => hp.setInterest(it),
                      selectedColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        color: hp.interest == it ? Colors.white : AppTheme.textMuted,
                        fontSize: 12,
                      ),
                      backgroundColor: AppTheme.cardAlt,
                      side: BorderSide(color: hp.interest == it ? AppTheme.primary : AppTheme.border),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _GenderChip(hp: hp, value: 'female', label: '👩 Female'),
              const SizedBox(width: 8),
              _GenderChip(hp: hp, value: 'male', label: '👨 Male'),
              const Spacer(),
              DropdownButton<String>(
                value: hp.sortBy,
                dropdownColor: AppTheme.cardAlt,
                underline: const SizedBox(),
                icon: const Icon(Icons.sort, color: AppTheme.textMuted, size: 18),
                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                items: const [
                  DropdownMenuItem(value: 'created_at', child: Text('Newest')),
                  DropdownMenuItem(value: 'price_per_minute', child: Text('Price')),
                  DropdownMenuItem(value: 'level', child: Text('Level')),
                  DropdownMenuItem(value: 'name', child: Text('Name')),
                ],
                onChanged: (v) => hp.setSort(v ?? 'created_at'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GenderChip extends StatelessWidget {
  final HostProvider hp;
  final String value;
  final String label;
  const _GenderChip({required this.hp, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final selected = hp.gender == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => hp.setGender(value),
      selectedColor: AppTheme.purple,
      labelStyle: TextStyle(color: selected ? Colors.white : AppTheme.textMuted, fontSize: 12),
      backgroundColor: AppTheme.cardAlt,
      side: const BorderSide(color: AppTheme.border),
    );
  }
}
