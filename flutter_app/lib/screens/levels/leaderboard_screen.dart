import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/level_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LevelProvider>().loadLeaderboard();
    });
  }

  String _medal(int rank) => rank == 1 ? '🥇' : rank == 2 ? '🥈' : rank == 3 ? '🥉' : '#$rank';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('🏆 Leaderboard')),
      body: Consumer<LevelProvider>(
        builder: (context, lp, _) {
          if (lp.loading && lp.leaderboard.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (lp.leaderboard.isEmpty) {
            return const EmptyView(emoji: '🏆', title: 'No rankings yet');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: lp.leaderboard.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final u = lp.leaderboard[i];
              final top3 = u.rank <= 3;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: top3 ? AppTheme.purple.withOpacity(0.12) : AppTheme.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: top3 ? AppTheme.purple.withOpacity(0.5) : AppTheme.border),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(_medal(u.rank),
                          style: TextStyle(fontSize: top3 ? 22 : 14, fontWeight: FontWeight.w800, color: AppTheme.textMuted),
                          textAlign: TextAlign.center),
                    ),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.purple,
                      backgroundImage: u.profilePic.isNotEmpty ? NetworkImage(u.profilePic) : null,
                      child: u.profilePic.isEmpty
                          ? Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?', style: const TextStyle(fontWeight: FontWeight.w800))
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
                          LevelBadge(level: u.level, title: u.levelTitle),
                        ],
                      ),
                    ),
                    Text('${u.xp} XP', style: const TextStyle(fontWeight: FontWeight.w900, color: AppTheme.accent)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
