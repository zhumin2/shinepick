import 'package:hive/hive.dart';

/// 用户模型（对齐后端 /auth/login 返回的 user 对象）。
class User {
  final int id;
  final String nickname;
  final String avatarUrl;
  final String phoneMasked;

  const User({
    required this.id,
    required this.nickname,
    required this.avatarUrl,
    required this.phoneMasked,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num).toInt(),
      nickname: json['nickname'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      phoneMasked: json['phone_masked'] as String? ?? '',
    );
  }
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
      await box.put(keyUser, {
        'id': user.id,
        'nickname': user.nickname,
        'avatar_url': user.avatarUrl,
        'phone_masked': user.phoneMasked,
      });
    }
  }

  static Future<void> clear() async {
    final box = _box();
    await box.delete(keyAccess);
    await box.delete(keyRefresh);
    await box.delete(keyUser);
  }
}
