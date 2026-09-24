import '../config/app_config.dart';

/// Backend relative paths (/static/...) → full URL.
String mediaUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http')) return path;
  return '${AppConfig.baseUrl}$path';
}

num _num(dynamic v, [num fallback = 0]) => v is num ? v : fallback;

List<String> _urlList(dynamic v) =>
    v is List ? v.map((e) => mediaUrl(e?.toString())).where((e) => e.isNotEmpty).toList() : const <String>[];

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
  final String description;
  final String city;
  final List<String> images;
  final List<String> videos;

  /// Admin-uploaded video that plays during a call (after the connecting screen).
  final String callVideo;
  final bool hasBot;
  final String botGreeting;
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
    this.description = '',
    this.city = '',
    this.images = const [],
    this.videos = const [],
    this.callVideo = '',
    this.hasBot = true,
    this.botGreeting = '',
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
        description: (j['description'] ?? '').toString(),
        city: (j['city'] ?? '').toString(),
        images: _urlList(j['images']),
        videos: _urlList(j['videos']),
        callVideo: mediaUrl((j['call_video'] ?? j['preview_video'])?.toString()),
        hasBot: j['has_bot'] != false,
        botGreeting: (j['bot_greeting'] ?? '').toString(),
        isOnline: j['is_online'] == true,
        isFeatured: j['is_featured'] == true,
        rating: _num(j['rating']).toDouble(),
        reviewCount: _num(j['review_count']).toInt(),
        totalCalls: _num(j['total_calls']).toInt(),
        totalMinutes: _num(j['total_minutes']).toInt(),
      );

  /// Video to play during calls: dedicated call video → preview → first gallery video.
  String get playableCallVideo =>
      callVideo.isNotEmpty ? callVideo : (previewVideo.isNotEmpty ? previewVideo : (videos.isNotEmpty ? videos.first : ''));

  /// All photos for the profile gallery (profile pic first, no duplicates).
  List<String> get galleryImages {
    final out = <String>[];
    if (profilePic.isNotEmpty) out.add(profilePic);
    for (final i in images) {
      if (!out.contains(i)) out.add(i);
    }
    return out;
  }

  /// All videos for the profile page (no duplicates).
  List<String> get galleryVideos {
    final out = <String>[];
    for (final v in [...videos, previewVideo, callVideo]) {
      if (v.isNotEmpty && !out.contains(v)) out.add(v);
    }
    return out;
  }

  String get priceLabel => pricePerMinute % 1 == 0 ? pricePerMinute.toInt().toString() : pricePerMinute.toStringAsFixed(1);

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
  final bool isIncoming;
  final int durationSeconds;
  final double totalCost;
  final int? rating;
  final DateTime? date;

  CallLogItem({
    required this.hostName,
    required this.status,
    this.isIncoming = false,
    this.durationSeconds = 0,
    this.totalCost = 0,
    this.rating,
    this.date,
  });

  factory CallLogItem.fromJson(Map<String, dynamic> j) => CallLogItem(
        hostName: (j['host_name'] ?? 'Host').toString(),
        status: (j['status'] ?? '').toString(),
        isIncoming: j['call_type'] == 'incoming',
        durationSeconds: _num(j['duration_seconds']).toInt(),
        totalCost: _num(j['total_cost']).toDouble(),
        rating: j['rating'] is num ? (j['rating'] as num).toInt() : null,
        date: DateTime.tryParse((j['created_at'] ?? '').toString()),
      );
}

/// Server `datetime.utcnow().isoformat()` strings have no timezone → treat as UTC.
DateTime? parseServerTime(dynamic v) {
  final raw = (v ?? '').toString();
  if (raw.isEmpty) return null;
  final hasZone = raw.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(raw);
  return DateTime.tryParse(hasZone ? raw : '${raw}Z')?.toLocal();
}

class ChatMsg {
  final String sender; // 'user' | 'bot'
  final String text;
  final DateTime? time;

  /// '' = normal chat; 'call' / 'low_balance' = host ka auto message (video call button)
  final String kind;

  ChatMsg({required this.sender, required this.text, this.time, this.kind = ''});

  bool get isUser => sender == 'user';
  bool get isCallMessage => kind == 'call' || kind == 'low_balance';

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
        sender: (j['sender'] ?? 'bot').toString(),
        text: (j['message'] ?? '').toString(),
        time: parseServerTime(j['timestamp']),
        kind: (j['kind'] ?? '').toString(),
      );
}

/// Inbox row (GET /chat/inbox): a host (or default Priya) + last message.
class InboxItem {
  final String? hostId; // null = default Priya persona
  final String name;
  final String avatar;
  final bool isOnline;
  final Host? host;
  final String? conversationId;
  final String lastMessage;
  final String lastSender;
  final DateTime? lastTime;
  final int unread;

  const InboxItem({
    required this.hostId,
    required this.name,
    this.avatar = '',
    this.isOnline = true,
    this.host,
    this.conversationId,
    this.lastMessage = '',
    this.lastSender = '',
    this.lastTime,
    this.unread = 0,
  });

  bool get hasChat => lastTime != null;

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        hostId: j['host_id']?.toString(),
        name: (j['name'] ?? 'Host').toString(),
        avatar: mediaUrl(j['avatar']?.toString()),
        isOnline: j['is_online'] != false,
        host: j['host'] is Map ? Host.fromJson(Map<String, dynamic>.from(j['host'])) : null,
        conversationId: j['conversation_id']?.toString(),
        lastMessage: (j['last_message'] ?? '').toString(),
        lastSender: (j['last_sender'] ?? '').toString(),
        lastTime: parseServerTime(j['last_time']),
        unread: _num(j['unread']).toInt(),
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


/// Runtime settings configured by admin (GET /settings/app).
class AppSettings {
  final int connectingSeconds;
  final int billingTickSeconds;
  final bool incomingCallEnabled;
  final int incomingCallIntervalSeconds;
  final int incomingRingTimeoutSeconds;
  final String? priyaHostId;
  final String priyaName;

  const AppSettings({
    this.connectingSeconds = 10,
    this.billingTickSeconds = 5,
    this.incomingCallEnabled = true,
    this.incomingCallIntervalSeconds = 300,
    this.incomingRingTimeoutSeconds = 30,
    this.priyaHostId,
    this.priyaName = 'Priya',
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        connectingSeconds: _num(j['connecting_seconds'], 10).toInt(),
        billingTickSeconds: _num(j['billing_tick_seconds'], 5).toInt().clamp(2, 60).toInt(),
        incomingCallEnabled: j['incoming_call_enabled'] != false,
        incomingCallIntervalSeconds: _num(j['incoming_call_interval_seconds'], 300).toInt(),
        incomingRingTimeoutSeconds: _num(j['incoming_ring_timeout_seconds'], 30).toInt(),
        priyaHostId: j['priya_host_id']?.toString(),
        priyaName: (j['priya_name'] ?? 'Priya').toString(),
      );
}

/// Priya page bot persona (GET /chat/bot/persona).
class ChatPersona {
  final String name;
  final String? hostId;
  final bool isDefault;
  final String avatar;
  final String greeting;
  final Host? host;
  final bool aiPowered;

  const ChatPersona({
    required this.name,
    this.hostId,
    this.isDefault = true,
    this.avatar = '',
    this.greeting = '',
    this.host,
    this.aiPowered = false,
  });

  factory ChatPersona.fromJson(Map<String, dynamic> j) => ChatPersona(
        name: (j['name'] ?? 'Priya').toString(),
        hostId: j['host_id']?.toString(),
        isDefault: j['is_default'] == true,
        avatar: mediaUrl(j['avatar']?.toString()),
        greeting: (j['greeting'] ?? '').toString(),
        host: j['host'] is Map ? Host.fromJson(Map<String, dynamic>.from(j['host'])) : null,
        aiPowered: j['ai_powered'] == true,
      );
}
