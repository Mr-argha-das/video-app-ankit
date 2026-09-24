import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../models/models.dart';
import '../services/api_service.dart';

class HostProvider extends ChangeNotifier {
  final ApiService api;
  HostProvider(this.api);

  List<Host> hosts = [];
  List<Host> featured = [];
  List<Host> online = [];
  List<String> interests = [];

  bool loading = false;
  bool loadingMore = false;
  String? error;

  int page = 1;
  int totalPages = 1;
  bool hasNext = false;
  static const int limit = 20;

  // Filters
  String? interest;
  String? gender;
  String sortBy = 'created_at';

  Future<void> loadInitial() async {
    loading = true;
    error = null;
    page = 1;
    notifyListeners();
    try {
      await Future.wait([_fetchDiscover(1), _fetchFeatured(), _fetchInterests()]);
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadInitial();

  Future<void> loadMore() async {
    if (loadingMore || !hasNext) return;
    loadingMore = true;
    notifyListeners();
    try {
      await _fetchDiscover(page + 1, append: true);
    } catch (_) {
      // silent — retry on next scroll
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _fetchDiscover(int targetPage, {bool append = false}) async {
    final query = <String, String>{
      'page': '$targetPage',
      'limit': '$limit',
      'sort_by': sortBy,
    };
    if (interest != null && interest!.isNotEmpty) query['interest'] = interest!;
    if (gender != null && gender!.isNotEmpty) query['gender'] = gender!;

    final data = await api.get('${AppConfig.apiPrefix}/hosts/discover', query: query);
    final list = ((data['hosts'] ?? []) as List).map((e) => Host.fromJson(Map<String, dynamic>.from(e))).toList();
    if (append) {
      hosts = [...hosts, ...list];
    } else {
      hosts = list;
    }
    page = data['page'] is num ? (data['page'] as num).toInt() : targetPage;
    totalPages = data['total_pages'] is num ? (data['total_pages'] as num).toInt() : 1;
    hasNext = data['has_next'] == true;
  }

  Future<void> _fetchFeatured() async {
    final data = await api.get('${AppConfig.apiPrefix}/hosts/featured');
    featured = ((data['hosts'] ?? []) as List).map((e) => Host.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> _fetchInterests() async {
    try {
      final data = await api.get('${AppConfig.apiPrefix}/chat/random-match/interests');
      interests = ((data['interests'] ?? []) as List).map((e) => e.toString()).toList();
    } catch (_) {}
  }

  Future<void> fetchOnline() async {
    final data = await api.get('${AppConfig.apiPrefix}/hosts/online');
    online = ((data['hosts'] ?? []) as List).map((e) => Host.fromJson(Map<String, dynamic>.from(e))).toList();
    notifyListeners();
  }

  Future<Host> hostDetail(String id) async {
    final data = await api.get('${AppConfig.apiPrefix}/hosts/$id');
    return Host.fromJson(Map<String, dynamic>.from(data['host']));
  }

  void setInterest(String? value) {
    interest = (value == interest) ? null : value;
    loadInitial();
  }

  void setGender(String? value) {
    gender = (value == gender) ? null : value;
    loadInitial();
  }

  void setSort(String value) {
    sortBy = value;
    loadInitial();
  }

  /// Random match — interest filter optional.
  Future<Host?> randomMatch({String? interest}) async {
    final data = await api.postJson('${AppConfig.apiPrefix}/chat/random-match', {
      if (interest != null && interest.isNotEmpty) 'interest': interest,
    });
    if (data['success'] != true) return null;
    return Host.fromJson(Map<String, dynamic>.from(data['matched_host']));
  }
}
