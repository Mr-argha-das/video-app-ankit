import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: error ? AppTheme.danger : null),
  );
}

String formatDate(DateTime? d) {
  if (d == null) return '-';
  return DateFormat('dd MMM, hh:mm a').format(d.toLocal());
}

/// 💘 Full-width gradient button — dating app style CTA.
class GradientButton extends StatelessWidget {
  final String label;
  final String? emoji;
  final VoidCallback? onPressed;
  final bool loading;
  final double? width;
  final EdgeInsetsGeometry? padding;

  const GradientButton({
    super.key,
    required this.label,
    this.emoji,
    this.onPressed,
    this.loading = false,
    this.width,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: Container(
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: AppTheme.primary.withOpacity(0.45), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: loading ? null : onPressed,
            child: Padding(
              padding: padding ?? const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Center(
                child: loading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        '${emoji != null ? '$emoji ' : ''}$label',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular photo widget with graceful fallback.
class AvatarPhoto extends StatelessWidget {
  final String url;
  final double size;
  final String letter;
  const AvatarPhoto({super.key, required this.url, this.size = 48, this.letter = '💘'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.cardAlt,
        image: url.isNotEmpty ? DecorationImage(image: CachedNetworkImageProvider(url), fit: BoxFit.cover) : null,
      ),
      child: url.isEmpty ? Center(child: Text(letter, style: TextStyle(fontSize: size * 0.45))) : null,
    );
  }
}

/// Small glassy pill chip (photo overlays ke liye).
class GlassPill extends StatelessWidget {
  final String text;
  final Color? color;
  final Color? textColor;
  const GlassPill(this.text, {super.key, this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color ?? Colors.black45,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor ?? Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class CoinChip extends StatelessWidget {
  final double amount;
  final double fontSize;
  const CoinChip(this.amount, {super.key, this.fontSize = 13});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.warning.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            amount % 1 == 0 ? amount.toInt().toString() : amount.toStringAsFixed(1),
            style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w800, fontSize: fontSize),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.purple.withOpacity(0.55), AppTheme.primary.withOpacity(0.55)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'Lv.$level${title != null && title!.isNotEmpty ? ' $title' : ''}',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// 💘 Dating-style host card (grid mode) — full-bleed photo + overlay info.
class HostCard extends StatelessWidget {
  final Host host;
  final VoidCallback onTap;
  const HostCard({super.key, required this.host, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: AppTheme.cardAlt),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            host.profilePic.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: host.profilePic,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: AppTheme.cardAlt),
                    errorWidget: (_, __, ___) => Container(color: AppTheme.cardAlt),
                  )
                : Container(color: AppTheme.cardAlt, child: const Center(child: Text('💃', style: TextStyle(fontSize: 44)))),
            const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: AppTheme.photoOverlay))),
            // online dot
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: host.isOnline ? AppTheme.success : AppTheme.textMuted,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: host.isOnline ? [BoxShadow(color: AppTheme.success.withOpacity(0.8), blurRadius: 8)] : null,
                ),
              ),
            ),
            // price pill
            Positioned(
              top: 8,
              right: 8,
              child: GlassPill('🪙 ${host.pricePerMinute % 1 == 0 ? host.pricePerMinute.toInt() : host.pricePerMinute}/min',
                  color: Colors.black54, textColor: AppTheme.warning),
            ),
            if (host.isFeatured)
              const Positioned(
                top: 40,
                left: 10,
                child: GlassPill('⭐ Featured', color: AppTheme.warning, textColor: Colors.black),
              ),
            // bottom info
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${host.name}, ${host.age ?? '?'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Colors.white, shadows: [Shadow(blurRadius: 6, color: Colors.black)]),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text('Lv.${host.level}', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text('⭐ ${host.rating}', style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
                      if (host.interests.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(host.interests.first,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        ),
                      ],
                    ],
                  ),
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
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.textMain), textAlign: TextAlign.center),
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
          Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.textMain)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
