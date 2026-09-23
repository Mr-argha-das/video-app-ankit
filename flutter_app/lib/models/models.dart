import '../config/app_config.dart';

/// Backend relative paths (/static/...) → full URL.
String mediaUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  return '${AppConfig.baseUrl}$path';
}

num _num(dynamic v, [num fallback = 0]) => v is num ? v : fallback;

class Host {
  final String id;
  final String name;
  final int? age;
  final String gender;
  final int level;
  final String levelTitle;
  final double pricePerMinute;
  final String bio;
  final List<String> interests;
  final String? language;
  final String profilePic;
  final String previewVideo;
  final bool isOnline;
  final bool isFeatured;
  final double rating;
  final int reviewCount;
  final int totalCalls;
  final int totalMinutes;

  Host({
    required this.id,
    required this.name,
    this.age,
    this.gender = '',
    this.level = 1,
    this.levelTitle = 'Newcomer',
    this.pricePerMinute = 10,
    this.bio = '',
    this.interests = const [],
    this.language,
    this.profilePic = '',
    this.previewVideo = '',
    this.isOnline = false,
    this.isFeatured = false,
    this.rating = 0,
    this.reviewCount = 0,
    this.totalCalls = 0,
    this.totalMinutes = 0,
  });

  factory Host.fromJson(Map<String, dynamic> j) => Host(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        name: (j['name'] ?? 'Host').toString(),
        age: j['age'] is num ? (j['age'] as num).toInt() : null,
        gender: (j['gender'] ?? '').toString(),
        level: _num(j['level'], 1).toInt(),
        levelTitle: (j['level_title'] ?? 'Newcomer').toString(),
        pricePerMinute: _num(j['price_per_minute'], 10).toDouble(),
        bio: (j['bio'] ?? '').toString(),
        interests: j['interests'] is List ? (j['interests'] as List).map((e) => e.toString()).toList() : const [],
        language: j['language']?.toString(),
        profilePic: mediaUrl(j['profile_picture']?.toString()),
        previewVideo: mediaUrl(j['preview_video']?.toString()),
        isOnline: j['is_online'] == true,
        isFeatured: j['is_featured'] == true,
        rating: _num(j['rating']).toDouble(),
        reviewCount: _num(j['review_count']).toInt(),
        totalCalls: _num(j['total_calls']).toInt(),
        totalMinutes: _num(j['total_minutes']).toInt(),
      );

  String get genderEmoji => gender == 'male' ? '👨' : gender == 'female' ? '👩' : '🙂';
}

class GiftItem {
  final String id;
  final String name;
  final String emoji;
  final int coins;
  final String category;
  final String animation;

  GiftItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.coins,
    this.category = 'standard',
    this.animation = 'pop',
  });

  factory GiftItem.fromJson(Map<String, dynamic> j) => GiftItem(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        name: (j['name'] ?? 'Gift').toString(),
        emoji: (j['emoji'] ?? '🎁').toString(),
        coins: _num(j['coins']).toInt(),
        category: (j['category'] ?? 'standard').toString(),
        animation: (j['animation'] ?? 'pop').toString(),
      );
}

class CoinPackage {
  final String id;
  final String label;
  final int coins;
  final num price;
  final int bonus;

  CoinPackage({required this.id, required this.label, required this.coins, required this.price, this.bonus = 0});

  int get totalCoins => coins + bonus;

  factory CoinPackage.fromJson(Map<String, dynamic> j) => CoinPackage(
        id: (j['id'] ?? '').toString(),
        label: (j['label'] ?? '').toString(),
        coins: _num(j['coins']).toInt(),
        price: _num(j['price']),
        bonus: _num(j['bonus']).toInt(),
      );
}

class TxnItem {
  final String type;
  final double amount;
  final String description;
  final String status;
  final DateTime? date;

  TxnItem({required this.type, required this.amount, this.description = '', this.status = 'success', this.date});

  bool get isCredit => type == 'credit';

  factory TxnItem.fromJson(Map<String, dynamic> j) => TxnItem(
        type: (j['type'] ?? '').toString(),
        amount: _num(j['amount']).toDouble(),
        description: (j['description'] ?? '').toString(),
        status: (j['status'] ?? 'success').toString(),
        date: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}

class RechargeItem {
  final String id;
  final num amountInr;
  final int coins;
  final int bonus;
  final String status;
  final String? ref;
  final String? rejectReason;
  final DateTime? date;

  RechargeItem({
    required this.id,
    required this.amountInr,
    required this.coins,
    this.bonus = 0,
    required this.status,
    this.ref,
    this.rejectReason,
    this.date,
  });

  factory RechargeItem.fromJson(Map<String, dynamic> j) => RechargeItem(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        amountInr: _num(j['amount_inr']),
        coins: _num(j['coins_to_credit']).toInt(),
        bonus: _num(j['bonus_coins']).toInt(),
        status: (j['status'] ?? 'pending').toString(),
        ref: j['transaction_ref']?.toString(),
        rejectReason: j['reject_reason']?.toString(),
        date: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}

class CallLogItem {
  final String hostName;
  final String status;
  final int durationSeconds;
  final double totalCost;
  final int? rating;
  final DateTime? date;

  CallLogItem({
    required this.hostName,
    required this.status,
    this.durationSeconds = 0,
    this.totalCost = 0,
    this.rating,
    this.date,
  });

  factory CallLogItem.fromJson(Map<String, dynamic> j) => CallLogItem(
        hostName: (j['host_name'] ?? 'Host').toString(),
        status: (j['status'] ?? '').toString(),
        durationSeconds: _num(j['duration_seconds']).toInt(),
        totalCost: _num(j['total_cost']).toDouble(),
        rating: j['rating'] is num ? (j['rating'] as num).toInt() : null,
        date: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}

class ChatMsg {
  final String sender; // 'user' | 'bot'
  final String text;
  final DateTime? time;

  ChatMsg({required this.sender, required this.text, this.time});

  bool get isUser => sender == 'user';

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
        sender: (j['sender'] ?? 'bot').toString(),
        text: (j['message'] ?? '').toString(),
        time: DateTime.tryParse((j['timestamp'] ?? '').toString()),
      );
}

class LeaderboardUser {
  final int rank;
  final String name;
  final int level;
  final String levelTitle;
  final int xp;
  final String profilePic;

  LeaderboardUser({
    required this.rank,
    required this.name,
    required this.level,
    required this.levelTitle,
    required this.xp,
    this.profilePic = '',
  });

  factory LeaderboardUser.fromJson(Map<String, dynamic> j) => LeaderboardUser(
        rank: _num(j['rank']).toInt(),
        name: (j['name'] ?? 'User').toString(),
        level: _num(j['level'], 1).toInt(),
        levelTitle: (j['level_title'] ?? '').toString(),
        xp: _num(j['xp']).toInt(),
        profilePic: mediaUrl(j['profile_picture']?.toString()),
      );
}
