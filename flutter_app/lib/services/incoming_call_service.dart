import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../main.dart' show navigatorKey;
import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../screens/call/incoming_call_screen.dart';
import 'api_service.dart';

/// Simulated incoming-call scheduler.
///
/// Jab tak app open hai (MainShell mounted) aur user registered hai,
/// har [AppConfig.incomingCallIntervalSeconds] (default 3 min) pe ek
/// random host ki incoming call screen aa jaati hai.
///
/// - Call chal rahi ho / ringing ho → skip, agli tick pe retry
/// - Incoming screen already khuli ho → skip
/// - Reject/accept → screen band hone ke baad timer fresh 3 min se restart
class IncomingCallService {
  IncomingCallService(this.api, this.auth, this.callP);

  final ApiService api;
  final AuthProvider auth;
  final CallProvider callP;

  Timer? _timer;
  bool _running = false;
  bool _showing = false;

  /// MainShell mount hone pe start.
  void start() {
    if (_running) return;
    _running = true;
    _arm();
  }

  /// MainShell dispose/logout pe stop.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void _arm() {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer(const Duration(seconds: AppConfig.incomingCallIntervalSeconds), _fire);
  }

  Future<void> _fire() async {
    if (!_running) return;
    try {
      // Guards — kisi bhi busy state me is tick ko skip karo
      if (!auth.loggedIn || auth.isGuest) return;
      if (callP.state != CallState.idle) return; // outgoing/incoming call busy
      if (_showing) return;

      final data = await api.get('${AppConfig.apiPrefix}/calls/random-host');
      if (data is! Map || data['success'] != true || data['host'] == null) return;

      final host = Host.fromJson(Map<String, dynamic>.from(data['host'] as Map));
      final nav = navigatorKey.currentState;
      if (nav == null || !_running) return;
      // fetch ke dauraan state badal gayi ho toh dobara check
      if (callP.state != CallState.idle || _showing) return;

      _showing = true;
      try {
        await nav.push(
          MaterialPageRoute(
            builder: (_) => IncomingCallScreen(host: host),
            fullscreenDialog: true,
          ),
        );
      } finally {
        _showing = false;
      }
    } catch (_) {
      // network/server issue — agli tick pe phir try
    } finally {
      // screen dismiss/end hone ke baad timer fresh se — matlab
      // last activity ke ~3 min baad hi agli call aayegi
      _arm();
    }
  }
}
