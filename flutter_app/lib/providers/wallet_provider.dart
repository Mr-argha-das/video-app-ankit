import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import 'auth_provider.dart';

class WalletProvider extends ChangeNotifier {
  final ApiService api;
  final AuthProvider auth;
  WalletProvider(this.api, this.auth);

  List<CoinPackage> packages = [];
  List<TxnItem> transactions = [];
  List<RechargeItem> recharges = [];
  String payToUpid = '';

  bool loading = false;
  bool submitting = false;
  String? error;

  Future<void> loadAll() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await Future.wait([
        _loadPackages(),
        _loadTransactions(),
        _loadRecharges(),
        _loadUpid(),
        auth.refreshUser(),
      ]);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadPackages() async {
    final data = await api.get('${AppConfig.apiPrefix}/wallet/packages');
    packages = ((data['packages'] ?? []) as List).map((e) => CoinPackage.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> _loadTransactions() async {
    final data = await api.get('${AppConfig.apiPrefix}/wallet/transactions', query: {'limit': '50'});
    transactions = ((data['transactions'] ?? []) as List).map((e) => TxnItem.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> _loadRecharges() async {
    try {
      final data = await api.get('${AppConfig.apiPrefix}/wallet/my-recharges', query: {'limit': '20'});
      recharges = ((data['recharges'] ?? []) as List).map((e) => RechargeItem.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      recharges = [];
    }
  }

  Future<void> _loadUpid() async {
    try {
      final data = await api.get('${AppConfig.apiPrefix}/upid/get');
      payToUpid = (data['upid'] ?? '').toString();
    } catch (_) {
      payToUpid = '';
    }
  }

  /// Razorpay order banayein — frontend checkout isse use karega.
  Future<Map<String, dynamic>> createRazorpayOrder({required num payAmount, String? packId}) async {
    submitting = true;
    notifyListeners();
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/wallet/pay/create-order', {
        if (packId != null && packId.isNotEmpty) 'pack_id': packId,
        if (packId == null) 'amount': payAmount,
      });
      return Map<String, dynamic>.from(data);
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  /// Razorpay payment verify karke coins credit karo (idempotent).
  Future<bool> verifyRazorpayPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    submitting = true;
    notifyListeners();
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/wallet/pay/verify', {
        'razorpay_order_id': orderId,
        'razorpay_payment_id': paymentId,
        'razorpay_signature': signature,
      });
      await auth.refreshUser();
      await _loadTransactions();
      return data['success'] == true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  /// Recharge request create karo — coins tabhi milenge jab admin approve kare.
  Future<RechargeItem> createRecharge({required num amount, String? transactionRef}) async {
    submitting = true;
    notifyListeners();
    try {
      final data = await api.postJson('${AppConfig.apiPrefix}/wallet/recharge', {
        'amount': amount,
        'payment_method': 'upi',
        if (transactionRef != null && transactionRef.isNotEmpty) 'transaction_ref': transactionRef,
      });
      if (data['pay_to_upid'] != null) payToUpid = data['pay_to_upid'].toString();
      await _loadRecharges();
      return RechargeItem(
        id: (data['request_id'] ?? '').toString(),
        amountInr: amount,
        coins: (data['coins_to_receive'] as num?)?.toInt() ?? 0,
        status: 'pending',
      );
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
