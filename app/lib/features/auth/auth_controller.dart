import 'package:flutter/foundation.dart';

import '../../core/error/app_error.dart';
import '../../core/network/api_client.dart';
import '../../shared/models/user.dart';
import '../../shared/storage/token_store.dart';

/// 认证状态机。
enum AuthStatus { unknown, unauthenticated, authenticated }

class AuthController extends ChangeNotifier {
  final TokenStore _tokenStore;
  final ApiClient _api;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  bool _sendingCode = false;
  int _cooldownSeconds = 0;

  AuthStatus get status => _status;
  User? get user => _user;
  bool get sendingCode => _sendingCode;
  int get cooldownSeconds => _cooldownSeconds;

  AuthController(this._tokenStore) : _api = ApiClient(_tokenStore);

  /// 启动时恢复登录态。
  Future<void> restore() async {
    final user = await _tokenStore.readUser();
    if (user != null) {
      _user = user;
      _status = AuthStatus.authenticated;
    } else {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  /// 发送验证码，成功后进入 60s 冷却。
  Future<void> sendSmsCode(String phone) async {
    if (_sendingCode) return;
    _sendingCode = true;
    notifyListeners();
    try {
      await _api.post('/auth/sms-code', data: {'phone': phone});
      _startCooldown(60);
    } on AppError {
      rethrow;
    } finally {
      _sendingCode = false;
      notifyListeners();
    }
  }

  /// 手机号 + 验证码登录（首次自动注册）。
  Future<void> login(String phone, String code) async {
    final data = await _api.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'phone': phone, 'code': code},
      parser: (d) => Map<String, dynamic>.from(d as Map),
    );
    final access = data['access_token'] as String;
    final refresh = data['refresh_token'] as String;
    final user = User.fromJson(
      Map<String, dynamic>.from(data['user'] as Map),
    );
    await _tokenStore.saveTokens(access, refresh);
    await AuthBox.save(accessToken: access, refreshToken: refresh, user: user);
    _user = user;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> logout() async {
    await _tokenStore.clear();
    _user = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  void _startCooldown(int seconds) {
    _cooldownSeconds = seconds;
    notifyListeners();
    Future.delayed(const Duration(seconds: 1), () {
      if (_cooldownSeconds <= 1) {
        _cooldownSeconds = 0;
        notifyListeners();
        return;
      }
      _cooldownSeconds -= 1;
      notifyListeners();
      // 继续倒计时
      _startCooldown(_cooldownSeconds);
    });
  }
}
