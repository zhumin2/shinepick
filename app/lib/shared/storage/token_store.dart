import 'package:hive_flutter/hive_flutter.dart';

import '../models/user.dart';

/// Token 存取：Hive 本地持久化。
class TokenStore {
  Future<void> init() async {
    if (!Hive.isBoxOpen('auth')) {
      await Hive.openBox('auth');
    }
  }

  Future<String?> readAccessToken() async {
    final box = Hive.box('auth');
    return box.get(AuthBox.keyAccess) as String?;
  }

  Future<String?> readRefreshToken() async {
    final box = Hive.box('auth');
    return box.get(AuthBox.keyRefresh) as String?;
  }

  Future<User?> readUser() async {
    final box = Hive.box('auth');
    final raw = box.get(AuthBox.keyUser);
    if (raw is Map) {
      return User.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }

  Future<void> saveTokens(String access, String refresh) async {
    final box = Hive.box('auth');
    await box.put(AuthBox.keyAccess, access);
    await box.put(AuthBox.keyRefresh, refresh);
  }

  Future<void> clear() => AuthBox.clear();
}
