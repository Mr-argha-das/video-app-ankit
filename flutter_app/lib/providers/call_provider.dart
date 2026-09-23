import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

enum CallState { idle, connecting, active, ended }

/// Video call session — simulated call ko real billing flow ke saath chalata hai.
/// Backend time-based billing karta hai; app har 60 sec pe billing-check bhejta hai.
class CallProvider extends ChangeNotifier {
  final ApiService api;
  final AuthProvider auth;
  CallProvider(this.api, this.auth);

  CallState state = CallState.idle;
  Host? host;
  String? callId;
  double pricePerMinute = 0;
  double balance = 0;
  double totalCost = 0;
  int elapsedSeconds = 0;
  String? warning;
  String? endReason;
  String? error;
  Map<String, dynamic>? summary;

  Timer? _ticker;
  Timer? _billingTimer;
  bool _billingInFlight = false;

  bool get isActive => state == CallState.active;

  Future<void> startCall(Host h) async {
    reset();
    host = h;
    state = CallState.connecting;
    notifyListeners();
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/calls/initiate', {'host_id': h.id});
      callId = data['call_id']?.toString();
      pricePerMinute = (data['price_per_minute'] as num?)?.toDouble() ?? h.pricePerMinute;
      balance = (data['your_balance'] as num?)?.toDouble() ?? auth.balance;

      // Simulate ringing: call ko active mark karo
      await api.postJson('${AppConfig.apiPrefix}/calls/answer/$callId', {});

      state = CallState.active;
      auth.updateBalance(balance);

      // UI timer — har second
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsedSeconds++;
        notifyListeners();
      });
      // Billing — har 60 sec (server elapsed minutes khud calculate karta hai)
      _billingTimer = Timer.periodic(
        const Duration(seconds: AppConfig.billingCheckSeconds),
        (_) => _billingCheck(),
      );
      notifyListeners();
    } on ApiException catch (e) {
      error = e.message;
      state = CallState.idle;
      notifyListeners();
      rethrow;
    } catch (e) {
      error = e.toString();
      state = CallState.idle;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _billingCheck() async {
    if (_billingInFlight || callId == null || state != CallState.active) return;
    _billingInFlight = true;
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/calls/billing-check', {'call_id': callId});
      if (data['new_balance'] != null) {
        balance = (data['new_balance'] as num).toDouble();
        auth.updateBalance(balance);
      }
      if (data['deducted'] != null) {
        totalCost += (data['deducted'] as num).toDouble();
      }
      warning = data['warning']?.toString();

      if (data['action'] == 'end_call') {
        endReason = data['reason']?.toString() ?? 'ended';
        await _serverEndCleanup();
      }
      notifyListeners();
    } catch (_) {
      // network blip — ek tick miss hua toh server next tick pe elapsed minutes settle kar lega
    } finally {
      _billingInFlight = false;
    }
  }

  /// Server side se call end ho gayi (insufficient balance) — local cleanup only.
  Future<void> _serverEndCleanup() async {
    _cancelTimers();
    state = CallState.ended;
    summary = {
      'duration_seconds': elapsedSeconds,
      'total_cost': totalCost,
      'auto_end': true,
      'reason': endReason,
    };
    await auth.refreshUser().catchError((_) {});
    notifyListeners();
  }

  /// User ne call end ki — final settlement backend karega.
  Future<Map<String, dynamic>> endCall({int? rating, String? review}) async {
    if (callId == null) return {};
    _cancelTimers();
    state = CallState.ended;
    notifyListeners();
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/calls/end', {
        'call_id': callId,
        if (rating != null) 'rating': rating,
        if (review != null && review.isNotEmpty) 'review': review,
      });
      summary = Map<String, dynamic>.from(data);
      totalCost = (data['total_cost'] as num?)?.toDouble() ?? totalCost;
      if (data['duration_seconds'] != null) {
        elapsedSeconds = (data['duration_seconds'] as num).toInt();
      }
    } catch (e) {
      summary = {'duration_seconds': elapsedSeconds, 'total_cost': totalCost, 'error': e.toString()};
    }
    await auth.refreshUser().catchError((_) {});
    balance = auth.balance;
    state = CallState.ended;
    notifyListeners();
    return summary ?? {};
  }

  /// Screen dispose — agar call active hai toh silently end karo (settlement server pe).
  Future<void> forceEndIfActive({int? rating}) async {
    if (state == CallState.active) {
      await endCall(rating: rating);
    }
  }

  void _cancelTimers() {
    _ticker?.cancel();
    _ticker = null;
    _billingTimer?.cancel();
    _billingTimer = null;
  }

  void reset() {
    _cancelTimers();
    state = CallState.idle;
    host = null;
    callId = null;
    pricePerMinute = 0;
    totalCost = 0;
    elapsedSeconds = 0;
    warning = null;
    endReason = null;
    error = null;
    summary = null;
  }

  String get timerText {
    final m = elapsedSeconds ~/ 60;
    final s = elapsedSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _cancelTimers();
    super.dispose();
  }
}
