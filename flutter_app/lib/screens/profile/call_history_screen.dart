import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/widgets.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<CallLogItem> _calls = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiService>();
      final data = await api.get('${AppConfig.apiPrefix}/calls/history', query: {'limit': '50'});
      setState(() {
        _calls = ((data['calls'] ?? []) as List).map((e) => CallLogItem.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('📞 Call History')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? EmptyView(emoji: '📡', title: 'Load nahi hua', subtitle: _error)
              : _calls.isEmpty
                  ? const EmptyView(emoji: '📞', title: 'No calls yet', subtitle: 'Discover se kisi host ko call karo')
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _calls.length,
                        separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16, height: 1),
                        itemBuilder: (context, i) {
                          final c = _calls[i];
                          final mins = c.durationSeconds ~/ 60;
                          final secs = c.durationSeconds % 60;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.purple.withOpacity(0.15),
                              child: const Text('📹'),
                            ),
                            title: Text(c.hostName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${c.durationSeconds > 0 ? '${mins}m ${secs}s · ' : ''}🪙 ${c.totalCost % 1 == 0 ? c.totalCost.toInt() : c.totalCost} · ${c.status}',
                              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (c.rating != null)
                                  Text('⭐ ${c.rating}', style: const TextStyle(fontSize: 12, color: AppTheme.warning)),
                                Text(formatDate(c.date), style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
