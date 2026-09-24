import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'app_settings_provider.dart';
import 'auth_provider.dart';

/// idle → connecting ("Calling…/Connecting…", ~10s, not billed)
///      → active (host video playing, wallet billed per second)
///      → ended  (user hung up / balance exhausted / cancelled)
enum CallState { idle, connecting, active, ended }

/// Why the call ended — drives the end-of-call UI.
class CallEndReason {
  static const user = 'user';
  static const cancelled = 'cancelled';
  static const insufficientBalance = 'insufficient_balance';
  static const connectionLost = 'connection_lost';
  static const error = 'error';
}

/// Thrown when the wallet can't cover even 1 minute (HTTP 402 from /calls/initiate).
class InsufficientBalanceException implements Exception {
  final String message;
  InsufficientBalanceException(this.message);
  @override
  String toString() => message;
}

/// Video call session. Same flow for outgoing calls (host profile / Priya page)
/// and accepted incoming calls:
///
///   initiate → connecting screen (N sec) → answer → host video + billing loop
///   → balance exhausted ⇒ server ends call ⇒ recharge prompt.
///
/// Billing is server-side and time based. The app syncs every
/// `billing_tick_seconds` and interpolates the balance locally in between so
/// the user sees the wallet going down continuously.
class CallProvider extends ChangeNotifier {
  final ApiService api;
  final AuthProvider auth;
  final AppSettingsProvider settingsP;
  CallProvider(this.api, this.auth, this.settingsP);

  CallState state = CallState.idle;
  Host? host;
  bool isIncoming = false;
  String? callId;
  String callVideoUrl = '';
  double pricePerMinute = 0;

  // Connecting phase
  int connectingTotal = 10;
  int connectingLeft = 10;

  // Active phase
  int elapsedSeconds = 0;
  double _serverBalance = 0;
  double _serverCost = 0;
  DateTime? _lastSyncAt;
  DateTime? _activeSince;

  String? warning;
  String? endReason;
  String? endMessage;
  String? error;
  Map<String, dynamic>? summary;

  Timer? _connectTimer;
  Timer? _ticker;
  Timer? _billingTimer;
  bool _billingInFlight = false;
  bool _answering = false;
  int _billingTick = AppConfig.billingCheckSeconds;

  bool get isActive => state == CallState.active;
  bool get isBusy => state == CallState.connecting || state == CallState.active;
  double get ratePerSecond => pricePerMinute / 60.0;

  double get _sinceSync =>
      _lastSyncAt == null ? 0 : DateTime.now().difference(_lastSyncAt!).inMilliseconds / 1000.0;

  /// Live wallet balance (server balance minus time talked since last sync).
  double get balance {
    if (state != CallState.active) return _serverBalance;
    final b = _serverBalance - _sinceSync * ratePerSecond;
    return b < 0 ? 0 : b;
  }

  /// Live amount spent on this call.
  double get totalCost {
    if (state != CallState.active) return _serverCost;
    final spent = _serverBalance - balance;
    return _serverCost + spent;
  }

  /// Seconds of talk time left at the current rate.
  int get secondsRemaining => ratePerSecond <= 0 ? 0 : (balance / ratePerSecond).floor();

  bool get lowBalance => state == CallState.active && secondsRemaining <= 60;

  // --------------------------------------------------------------------------
  // Start: outgoing call or accepted incoming call
  // --------------------------------------------------------------------------
  Future<void> startCall(Host h, {bool incoming = false}) async {
    reset();
    host = h;
    isIncoming = incoming;
    callVideoUrl = h.playableCallVideo;
    pricePerMinute = h.pricePerMinute;
    final cfg = settingsP.settings;
    connectingTotal = cfg.connectingSeconds;
    connectingLeft = connectingTotal;
    _billingTick = cfg.billingTickSeconds;
    state = CallState.connecting;
    notifyListeners();

    final connectStart = DateTime.now();
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/calls/initiate', {
        'host_id': h.id,
        'call_type': incoming ? 'incoming' : 'outgoing',
      });
      if (state != CallState.connecting) {
        // User ne request ke beech hi cancel kar diya
        final id = data['call_id']?.toString();
        if (id != null) _endOnServer(id);
        return;
      }
      callId = data['call_id']?.toString();
      pricePerMinute = (data['price_per_minute'] as num?)?.toDouble() ?? h.pricePerMinute;
      _serverBalance = (data['your_balance'] as num?)?.toDouble() ?? auth.balance;
      final serverVideo = mediaUrl(data['call_video']?.toString());
      if (serverVideo.isNotEmpty) callVideoUrl = serverVideo;
      connectingTotal = (data['connecting_seconds'] as num?)?.toInt() ?? connectingTotal;
      _billingTick = ((data['billing_tick_seconds'] as num?)?.toInt() ?? _billingTick).clamp(2, 60).toInt();
      auth.updateBalance(_serverBalance);
    } on ApiException catch (e) {
      state = CallState.idle;
      error = e.message;
      notifyListeners();
      if (e.status == 402) throw InsufficientBalanceException(e.message);
      rethrow;
    } catch (e) {
      state = CallState.idle;
      error = e.toString();
      notifyListeners();
      rethrow;
    }

    // "Calling… → Connecting…" countdown (request time bhi isi me count hota hai)
    void tick() {
      final passed = DateTime.now().difference(connectStart).inSeconds;
      connectingLeft = (connectingTotal - passed).clamp(0, connectingTotal).toInt();
      notifyListeners();
      if (connectingLeft <= 0) _answer();
    }

    tick();
    if (state == CallState.connecting) {
      _connectTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
  }

  /// Connecting screen finished → host "picks up" → video + billing start.
  Future<void> _answer() async {
    if (_answering || state != CallState.connecting || callId == null) return;
    _answering = true;
    _connectTimer?.cancel();
    _connectTimer = null;
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/calls/answer/$callId', {});
      if (state != CallState.connecting) return; // cancelled meanwhile
      if (data['success'] != true) {
        _finishLocally(CallEndReason.error, message: data['message']?.toString() ?? 'Call connect nahi ho payi');
        return;
      }
      if (data['balance'] is num) _serverBalance = (data['balance'] as num).toDouble();
      _serverCost = 0;
      _lastSyncAt = DateTime.now();
      _activeSince = DateTime.now();
      state = CallState.active;

      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (state != CallState.active) return;
        elapsedSeconds = DateTime.now().difference(_activeSince!).inSeconds;
        // Local estimate khatam → turant server se confirm karo (auto-end fast)
        if (secondsRemaining <= 0) _billingCheck();
        notifyListeners();
      });
      _billingTimer = Timer.periodic(Duration(seconds: _billingTick), (_) => _billingCheck());
      notifyListeners();
    } catch (e) {
      if (state == CallState.connecting) {
        _finishLocally(CallEndReason.error, message: 'Call connect nahi ho payi — network check karo');
        if (callId != null) _endOnServer(callId!);
      }
    } finally {
      _answering = false;
    }
  }

  Future<void> _billingCheck() async {
    if (_billingInFlight || callId == null || state != CallState.active) return;
    _billingInFlight = true;
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/calls/billing-check', {'call_id': callId});
      if (state != CallState.active) return;
      final nb = data['new_balance'] ?? data['balance'];
      if (nb is num) _serverBalance = nb.toDouble();
      if (data['total_cost'] is num) _serverCost = (data['total_cost'] as num).toDouble();
      _lastSyncAt = DateTime.now();
      warning = data['warning']?.toString();
      auth.updateBalance(_serverBalance);

      if (data['action'] == 'end_call') {
        final reason = data['reason']?.toString();
        _finishLocally(
          reason == 'insufficient_balance'
              ? CallEndReason.insufficientBalance
              : (reason == 'connection_lost' ? CallEndReason.connectionLost : CallEndReason.error),
          message: data['message']?.toString(),
          autoEnd: true,
          serverData: Map<String, dynamic>.from(data),
        );
        auth.refreshUser().catchError((_) {});
      } else {
        notifyListeners();
      }
    } catch (_) {
      // network blip — server next sync pe elapsed time settle kar lega
    } finally {
      _billingInFlight = false;
    }
  }

  void _finishLocally(String reason,
      {String? message, bool autoEnd = false, Map<String, dynamic>? serverData}) {
    _cancelTimers();
    final secs = (serverData?['duration_seconds'] as num?)?.toInt() ?? elapsedSeconds;
    final cost = (serverData?['total_cost'] as num?)?.toDouble() ?? _serverCost;
    _serverCost = cost;
    elapsedSeconds = secs;
    state = CallState.ended;
    endReason = reason;
    endMessage = message;
    summary = {
      'duration_seconds': secs,
      'total_cost': cost,
      'auto_end': autoEnd,
      'reason': reason,
      if (message != null) 'message': message,
    };
    notifyListeners();
  }

  /// User cancelled while "Calling…/Connecting…" — no charge.
  Future<void> cancelCall() async {
    if (state != CallState.connecting) return;
    final id = callId;
    _finishLocally(CallEndReason.cancelled);
    if (id != null) await _endOnServer(id);
  }

  Future<void> _endOnServer(String id, {int? rating}) async {
    try {
      await api.postJson('${AppConfig.apiPrefix}/calls/end', {
        'call_id': id,
        if (rating != null) 'rating': rating,
      });
    } catch (_) {}
  }

  /// User hung up — backend does the final settlement.
  Future<Map<String, dynamic>> endCall({int? rating, String? review}) async {
    if (callId == null) return {};
    final wasAutoEnded = state == CallState.ended;
    _cancelTimers();
    if (!wasAutoEnded) {
      state = CallState.ended;
      endReason = CallEndReason.user;
      notifyListeners();
    }
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/calls/end', {
        'call_id': callId,
        if (rating != null) 'rating': rating,
        if (review != null && review.isNotEmpty) 'review': review,
      });
      if (!wasAutoEnded) {
        summary = Map<String, dynamic>.from(data);
        _serverCost = (data['total_cost'] as num?)?.toDouble() ?? _serverCost;
        if (data['duration_seconds'] != null) elapsedSeconds = (data['duration_seconds'] as num).toInt();
        if (data['status'] == 'ended_insufficient_balance' || data['auto_ended'] == true) {
          endReason = CallEndReason.insufficientBalance;
          summary!['reason'] = CallEndReason.insufficientBalance;
        }
      }
    } catch (e) {
      summary ??= {'duration_seconds': elapsedSeconds, 'total_cost': _serverCost, 'error': e.toString()};
    }
    await auth.refreshUser().catchError((_) {});
    _serverBalance = auth.balance;
    notifyListeners();
    return summary ?? {};
  }

  /// Call screen closing (back button etc.) — never leave a call running.
  Future<void> leaveScreen() async {
    if (state == CallState.connecting) {
      await cancelCall();
    } else if (state == CallState.active) {
      await endCall();
    }
    reset();
    notifyListeners();
  }

  void _cancelTimers() {
    _connectTimer?.cancel();
    _connectTimer = null;
    _ticker?.cancel();
    _ticker = null;
    _billingTimer?.cancel();
    _billingTimer = null;
  }

  void reset() {
    _cancelTimers();
    state = CallState.idle;
    host = null;
    isIncoming = false;
    callId = null;
    callVideoUrl = '';
    pricePerMinute = 0;
    connectingLeft = connectingTotal;
    elapsedSeconds = 0;
    _serverCost = 0;
    _serverBalance = auth.balance;
    _lastSyncAt = null;
    _activeSince = null;
    warning = null;
    endReason = null;
    endMessage = null;
    error = null;
    summary = null;
    _answering = false;
    _billingInFlight = false;
  }

  String get timerText {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String get remainingText {
    final r = secondsRemaining;
    if (r >= 3600) return '${r ~/ 3600}h ${(r % 3600) ~/ 60}m';
    if (r >= 60) return '${r ~/ 60}m ${r % 60}s';
    return '${r}s';
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }
}
