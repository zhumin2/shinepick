import 'package:hive/hive.dart';

/// 用户模型（登录返回 user + S2 GET/PATCH /users/me 的完整资料）。
class User {
  final int id;
  final String nickname;
  final String avatarUrl;
  final String phoneMasked;

  /// S2 资料字段（登录接口不返回，可空）
  final String bio;
  final int gender; // 0未知 1男 2女
  final String city;
  final String? birthday; // YYYY-MM-DD
  final bool isMinor;

  /// S3 打卡统计（/users/me 的 stats；登录接口无此数据）
  final int checkinCount;
  final int checkinDays;
  final int streakDays;
  final int companions;

  const User({
    required this.id,
    required this.nickname,
    required this.avatarUrl,
    required this.phoneMasked,
    this.bio = '',
    this.gender = 0,
    this.city = '',
    this.birthday,
    this.isMinor = false,
    this.checkinCount = 0,
    this.checkinDays = 0,
    this.streakDays = 0,
    this.companions = 0,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num).toInt(),
      nickname: json['nickname'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      phoneMasked: json['phone_masked'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      gender: (json['gender'] as num?)?.toInt() ?? 0,
      city: json['city'] as String? ?? '',
      birthday: json['birthday'] as String?,
      isMinor: parseMinor(json['is_minor']),
      checkinCount: (json['checkin_count'] as num?)?.toInt() ?? 0,
      checkinDays: (json['checkin_days'] as num?)?.toInt() ?? 0,
      streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      companions: (json['companions'] as num?)?.toInt() ?? 0,
    );
  }

  /// 兼容 bool（/users/me）与 0/1（本地缓存）两种表示。
  static bool parseMinor(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v.toInt() == 1;
    return false;
  }

  /// 合并资料接口返回（保留登录侧的掩码手机号）。
  User mergeProfile(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>?;
    return User(
      id: id,
      nickname: json['nickname'] as String? ?? nickname,
      avatarUrl: json['avatar_url'] as String? ?? avatarUrl,
      phoneMasked: json['phone_masked'] as String? ?? phoneMasked,
      bio: json['bio'] as String? ?? '',
      gender: (json['gender'] as num?)?.toInt() ?? 0,
      city: json['city'] as String? ?? '',
      birthday: json['birthday'] as String?,
      isMinor: parseMinor(json['is_minor']),
      checkinCount:
          (stats?['checkin_count'] as num?)?.toInt() ?? checkinCount,
      checkinDays:
          (stats?['checkin_days'] as num?)?.toInt() ?? checkinDays,
      streakDays: (stats?['streak_days'] as num?)?.toInt() ?? streakDays,
      companions: (stats?['companions'] as num?)?.toInt() ?? companions,
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'nickname': nickname,
        'avatar_url': avatarUrl,
        'phone_masked': phoneMasked,
        'bio': bio,
        'gender': gender,
        'city': city,
        'birthday': birthday,
        'is_minor': isMinor ? 1 : 0,
        'checkin_count': checkinCount,
        'checkin_days': checkinDays,
        'streak_days': streakDays,
        'companions': companions,
      };
}

/// 本地持久化的登录态（Hive box: auth）。
class AuthBox {
  static const boxName = 'auth';
  static const keyAccess = 'access_token';
  static const keyRefresh = 'refresh_token';
  static const keyUser = 'user';

  static Box _box() => Hive.box(boxName);

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    User? user,
  }) async {
    final box = _box();
    await box.put(keyAccess, accessToken);
    await box.put(keyRefresh, refreshToken);
    if (user != null) {
      await box.put(keyUser, user.toCacheJson());
    }
  }

  static Future<void> clear() async {
    final box = _box();
    await box.delete(keyAccess);
    await box.delete(keyRefresh);
    await box.delete(keyUser);
  }
}
