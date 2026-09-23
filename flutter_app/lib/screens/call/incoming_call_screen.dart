import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import 'call_screen.dart';

/// Simulated incoming call from a host (backend: GET /calls/random-host).
class IncomingCallScreen extends StatelessWidget {
  final Host host;
  const IncomingCallScreen({super.key, required this.host});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1F1B3A), AppTheme.bg],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primary, width: 3),
                  color: AppTheme.cardAlt,
                  image: host.profilePic.isNotEmpty
                      ? DecorationImage(image: NetworkImage(host.profilePic), fit: BoxFit.cover)
                      : null,
                ),
                child: host.profilePic.isEmpty ? const Center(child: Text('👤', style: TextStyle(fontSize: 60))) : null,
              ),
              const SizedBox(height: 20),
              Text(host.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('Incoming video call… 📹', style: TextStyle(color: AppTheme.textMuted)),
              const SizedBox(height: 6),
              Text('🪙 ${host.pricePerMinute % 1 == 0 ? host.pricePerMinute.toInt() : host.pricePerMinute}/min',
                  style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _action(
                      emoji: '❌',
                      label: 'Decline',
                      bg: AppTheme.danger,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    _action(
                      emoji: '📹',
                      label: 'Accept',
                      bg: AppTheme.success,
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => CallScreen(host: host)),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action({required String emoji, required String label, required Color bg, required VoidCallback onTap}) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 30))),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
