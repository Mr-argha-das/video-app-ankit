import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../services/api_service.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService api;
  AuthProvider(this.api);

  static const _tokenKey = 'auth_token';

  Map<String, dynamic>? user;
  bool checking = true; // splash ke liye
  bool busy = false;

  bool get loggedIn => api.token != null && user != null;
  bool get isGuest => user?['is_guest'] == true;

  String get displayName => (user?['name'] ?? 'User').toString();
  double get balance => (user?['wallet_balance'] is num) ? (user!['wallet_balance'] as num).toDouble() : 0;
  int get xp => (user?['xp'] is num) ? (user!['xp'] as num).toInt() : 0;
  int get level => (user?['level'] is num) ? (user!['level'] as num).toInt() : 1;
  String get levelTitle => (user?['level_title'] ?? 'Newcomer').toString();

  String get avatarUrl {
    final p = user?['profile_picture']?.toString();
    if (p == null || p.isEmpty) return '';
    return p.startsWith('http') ? p : '${AppConfig.baseUrl}$p';
  }

  /// App start — saved token se auto login.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_tokenKey);
    if (saved != null && saved.isNotEmpty) {
      api.token = saved;
      try {
        await refreshUser();
      } catch (_) {
        await _clear();
      }
    }
    checking = false;
    notifyListeners();
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    api.token = data['access_token']?.toString();
    user = Map<String, dynamic>.from(data['user'] ?? {});
    final prefs = await SharedPreferences.getInstance();
    if (api.token != null) await prefs.setString(_tokenKey, api.token!);
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() job) async {
    busy = true;
    notifyListeners();
    try {
      await job();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> login(String mobile, String password) => _run(() async {
        final data = await api.postForm('${AppConfig.apiPrefix}/auth/login', {
          'mobile': mobile,
          'password': password,
        });
        await _saveSession(Map<String, dynamic>.from(data));
      });

  Future<void> register({
    required String name,
    required String mobile,
    required String password,
    String gender = 'other',
    List<int>? photoBytes,
    String? photoName,
  }) =>
      _run(() async {
        final fields = <String, String>{
          'name': name,
          'mobile': mobile,
          'password': password,
          'gender': gender,
        };
        final files = <http.MultipartFile>[];
        if (photoBytes != null && photoName != null) {
          files.add(http.MultipartFile.fromBytes('profile_picture', photoBytes, filename: photoName));
        }
        final data = await api.multipart('POST', '${AppConfig.apiPrefix}/auth/register', fields: fields, files: files);
        await _saveSession(Map<String, dynamic>.from(data));
      });

  Future<void> guestLogin() => _run(() async {
        final data = await api.postJson('${AppConfig.apiPrefix}/auth/guest-login', {});
        await _saveSession(Map<String, dynamic>.from(data));
      });

  Future<void> refreshUser() async {
    final data = await api.get('${AppConfig.apiPrefix}/auth/me');
    user = Map<String, dynamic>.from(data['user'] ?? {});
    notifyListeners();
  }

  Future<void> updateProfile({
    String? name,
    String? gender,
    String? interestsCsv,
    List<int>? photoBytes,
    String? photoName,
  }) =>
      _run(() async {
        final fields = <String, String>{};
        if (name != null && name.isNotEmpty) fields['name'] = name;
        if (gender != null && gender.isNotEmpty) fields['gender'] = gender;
        if (interestsCsv != null && interestsCsv.isNotEmpty) fields['interests'] = interestsCsv;

        if (photoBytes != null && photoName != null) {
          final files = [http.MultipartFile.fromBytes('profile_picture', photoBytes, filename: photoName)];
          await api.multipart('PUT', '${AppConfig.apiPrefix}/auth/profile', fields: fields, files: files);
        } else {
          await api.putForm('${AppConfig.apiPrefix}/auth/profile', fields);
        }
        await refreshUser();
      });

  Future<void> convertGuest({required String name, required String mobile, required String password}) =>
      _run(() async {
        await api.postForm('${AppConfig.apiPrefix}/auth/convert-guest', {
          'name': name,
          'mobile': mobile,
          'password': password,
        });
        await refreshUser();
      });

  /// Wallet/calls/gifts se balance sync karne ke liye.
  void updateBalance(double newBalance) {
    if (user != null) {
      user!['wallet_balance'] = newBalance;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _clear();
    notifyListeners();
  }

  Future<void> _clear() async {
    api.token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }
}
