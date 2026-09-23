import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/level_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../auth/convert_guest_screen.dart';
import '../auth/login_screen.dart';
import '../levels/leaderboard_screen.dart';
import 'call_history_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LevelProvider>().loadMyLevel();
    });
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Account se bahar nikal jaoge.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Logout')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (r) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final lp = context.watch<LevelProvider>();
    final user = auth.user ?? {};
    final lvl = lp.levelData;
    final progress = ((lvl?['progress_percent'] ?? 0) as num).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('👤 Profile', style: TextStyle(fontWeight: FontWeight.w900))),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: () async {
          await auth.refreshUser();
          await context.read<LevelProvider>().loadMyLevel();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 20),
            // Header
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 48,
                    backgroundColor: AppTheme.purple,
                    backgroundImage: auth.avatarUrl.isNotEmpty ? NetworkImage(auth.avatarUrl) : null,
                    child: auth.avatarUrl.isEmpty
                        ? Text(auth.displayName.isNotEmpty ? auth.displayName[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900))
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Text(auth.displayName, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(user['mobile']?.toString() ?? 'Guest user',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                      if (auth.isGuest) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                          child: const Text('GUEST', style: TextStyle(fontSize: 10, color: AppTheme.warning, fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Level card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.purple.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(lp.myLevel?['badge']?.toString() ?? '🌱', style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Level ${auth.level} ${auth.levelTitle}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            Text('${auth.xp} XP', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          ],
                        ),
                      ),
                      LevelBadge(level: auth.level),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (progress / 100).clamp(0.0, 1.0),
                      minHeight: 8,
                      backgroundColor: AppTheme.cardAlt,
                      valueColor: const AlwaysStoppedAnimation(AppTheme.primary),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Next level: ${lvl?['next_level_xp'] ?? '-'} XP · ${progress.toStringAsFixed(0)}% done',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  if ((lp.myLevel?['perks'] as List?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ((lp.myLevel!['perks'] as List).map((p) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                            child: Text('🎖 $p', style: const TextStyle(fontSize: 10, color: AppTheme.accent)),
                          ))).toList(),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Stats row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _stat('📞', '${user['call_count'] ?? 0}', 'Calls'),
                  const SizedBox(width: 10),
                  _stat('🎁', '${user['gifts_sent'] ?? 0}', 'Gifts'),
                  const SizedBox(width: 10),
                  _stat('🪙', '${(user['wallet_balance'] as num?)?.toInt() ?? 0}', 'Coins'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Menu
            _menuTile(Icons.edit, 'Edit profile', 'Name, photo, interests', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EditProfileScreen()));
            }),
            if (auth.isGuest)
              _menuTile(Icons.rocket_launch, 'Unlock full account', 'Calls, gifts & wallet ke liye', () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ConvertGuestScreen()));
              }, highlight: true),
            _menuTile(Icons.emoji_events, 'Leaderboard', 'Top XP users', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
            }),
            _menuTile(Icons.history, 'Call history', 'Past calls & ratings', () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CallHistoryScreen()));
            }),
            const Divider(indent: 16, endIndent: 16),
            _menuTile(Icons.logout, 'Logout', '', _logout, danger: true),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _stat(String emoji, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String title, String subtitle, VoidCallback onTap, {bool highlight = false, bool danger = false}) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: danger
            ? AppTheme.danger.withOpacity(0.15)
            : highlight
                ? AppTheme.success.withOpacity(0.15)
                : AppTheme.purple.withOpacity(0.15),
        child: Icon(icon, size: 20, color: danger ? AppTheme.danger : highlight ? AppTheme.success : const Color(0xFFB4AEF7)),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: danger ? AppTheme.danger : AppTheme.textMain)),
      subtitle: subtitle.isEmpty ? null : Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
      onTap: onTap,
    );
  }
}
