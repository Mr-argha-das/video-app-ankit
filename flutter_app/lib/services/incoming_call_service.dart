import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../providers/app_settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../screens/call/incoming_call_screen.dart';
import 'api_service.dart';

/// Shows an incoming host call roughly every N seconds (admin setting, default
/// 180s = 3 min) while the user is actively using the app.
///
/// Only *active usage* counts: time with the app in foreground, logged in
/// (non-guest), and not already in a call or ringing. After a call / ring the
/// counter restarts, so calls never stack up.
class IncomingCallService extends ChangeNotifier with WidgetsBindingObserver {
  final ApiService api;
  final AuthProvider auth;
  final CallProvider callP;
  final AppSettingsProvider settingsP;
  final GlobalKey<NavigatorState> navigatorKey;

  IncomingCallService({
    required this.api,
    required this.auth,
    required this.callP,
    required this.settingsP,
    required this.navigatorKey,
  });

  Timer? _timer;
  bool _running = false;
  bool _foreground = true;
  bool _fetching = false;
  bool ringing = false;
  int _activeSeconds = 0;

  int get secondsUntilNextCall {
    final left = settingsP.settings.incomingCallIntervalSeconds - _activeSeconds;
    return left < 0 ? 0 : left;
  }

  void start() {
    if (_running) return;
    _running = true;
    _activeSeconds = 0;
    WidgetsBinding.instance.addObserver(this);
    settingsP.load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void stop() {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Restart the countdown (e.g. user just finished a call).
  void resetCountdown() => _activeSeconds = 0;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) settingsP.load(); // admin ne interval badla ho toh pick karo
  }

  bool get _eligible =>
      _foreground &&
      auth.loggedIn &&
      !auth.isGuest &&
      settingsP.settings.incomingCallEnabled &&
      callP.state == CallState.idle;

  void _tick() {
    if (ringing || _fetching) return;
    if (callP.isBusy || callP.state == CallState.ended) {
      _activeSeconds = 0; // call ke baad fresh 3 min
      return;
    }
    if (!_eligible) return;
    _activeSeconds++;
    if (_activeSeconds >= settingsP.settings.incomingCallIntervalSeconds) {
      _activeSeconds = 0;
      _ring();
    }
  }

  Future<void> _ring() async {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    _fetching = true;
    Host? host;
    int timeout = settingsP.settings.incomingRingTimeoutSeconds;
    try {
      final data = await api.get('${AppConfig.apiPrefix}/calls/random-host');
      if (data['success'] == true && data['host'] != null) {
        host = Host.fromJson(Map<String, dynamic>.from(data['host']));
        timeout = (data['ring_timeout_seconds'] as num?)?.toInt() ?? timeout;
      }
    } catch (_) {
      // server down — agli baar try karenge
    } finally {
      _fetching = false;
    }
    if (host == null || !_eligible || ringing) return;

    ringing = true;
    notifyListeners();
    try {
      await nav.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => IncomingCallScreen(host: host!, ringTimeoutSeconds: timeout),
      ));
    } finally {
      ringing = false;
      _activeSeconds = 0;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
