import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.danger : null,
    ),
  );
}

String formatDate(DateTime? d) {
  if (d == null) return '-';
  return DateFormat('dd MMM, hh:mm a').format(d.toLocal());
}

/// Coin chip 🪙
class CoinChip extends StatelessWidget {
  final double amount;
  final double fontSize;
  const CoinChip(this.amount, {super.key, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(1),
            style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700, fontSize: fontSize),
          ),
        ],
      ),
    );
  }
}

class LevelBadge extends StatelessWidget {
  final int level;
  final String? title;
  const LevelBadge({super.key, required this.level, this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.purple.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Lv.$level${title != null && title!.isNotEmpty ? ' $title' : ''}',
        style: const TextStyle(color: Color(0xFFB4AEF7), fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Host card for grid
class HostCard extends StatelessWidget {
  final Host host;
  final VoidCallback onTap;
  const HostCard({super.key, required this.host, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  host.profilePic.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: host.profilePic,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(color: AppTheme.cardAlt, child: const Center(child: Text('👤', style: TextStyle(fontSize: 40)))),
                          errorWidget: (_, __, ___) => Container(color: AppTheme.cardAlt, child: const Center(child: Text('👤', style: TextStyle(fontSize: 40)))),
                        )
                      : Container(color: AppTheme.cardAlt, child: const Center(child: Text('👤', style: TextStyle(fontSize: 40)))),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: host.isOnline ? AppTheme.success : AppTheme.textMuted,
                        border: Border.all(color: AppTheme.bg, width: 2),
                      ),
                    ),
                  ),
                  if (host.isFeatured)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppTheme.warning, borderRadius: BorderRadius.circular(12)),
                        child: const Text('⭐ Featured', style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${host.name}, ${host.age ?? '?'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.textMain),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      LevelBadge(level: host.level),
                      const SizedBox(width: 6),
                      Text('⭐ ${host.rating}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  CoinChip(host.pricePerMinute, fontSize: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String emoji;
  final String title;
  final String? subtitle;
  const EmptyView({super.key, required this.emoji, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textMain), textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, style: const TextStyle(fontSize: 13, color: AppTheme.textMuted), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.textMain)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
