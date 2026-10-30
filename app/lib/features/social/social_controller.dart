import 'package:flutter/foundation.dart';

import '../../core/error/app_error.dart';
import '../../shared/models/checkin.dart';
import '../auth/auth_controller.dart';

/// 通知 / 拉黑 / 举报（S6-04/S6-03）。
class SocialController extends ChangeNotifier {
  final AuthController auth;

  List<NotificationVO> _items = [];
  int _unread = 0;
  bool _loading = false;

  SocialController(this.auth);

  List<NotificationVO> get items => List.unmodifiable(_items);
  int get unread => _unread;
  bool get loading => _loading;

  /// 拉通知列表（含未读数）。
  Future<void> loadNotifications({int cursor = 0, bool refresh = true}) async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final data = await auth.api.get<Map<String, dynamic>>(
        '/notifications${cursor > 0 ? '?cursor=$cursor' : ''}',
        parser: (d) => Map<String, dynamic>.from(d as Map),
      );
      final raw = data['items'] as List<dynamic>? ?? const [];
      final list = raw
          .map((e) =>
              NotificationVO.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      _items = cursor > 0 ? [..._items, ...list] : list;
      _unread = (data['unread_count'] as num?)?.toInt() ?? 0;
    } catch (_) {
      // 弱网保留旧数据
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 轻量刷新未读数（首页铃铛）。
  Future<void> refreshUnread() async {
    try {
      final data = await auth.api.get<Map<String, dynamic>>(
        '/notifications',
        parser: (d) => Map<String, dynamic>.from(d as Map),
      );
      _unread = (data['unread_count'] as num?)?.toInt() ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  /// 全部已读。
  Future<void> markAllRead() async {
    await auth.api.post('/notifications/read');
    _unread = 0;
    _items = [
      for (final n in _items) n,
    ];
    notifyListeners();
    await loadNotifications();
  }

  /// 拉黑用户（静默生效）。
  Future<void> block(int userId) async {
    await auth.api.post('/blocks', data: {'user_id': userId});
  }

  /// 取消拉黑。
  Future<void> unblock(int userId) async {
    await auth.api.delete('/blocks/$userId');
  }

  /// 举报（1打卡 2留言 3用户）。
  Future<void> report({
    required int targetType,
    required int targetId,
    int reason = 1,
    String detail = '',
  }) async {
    try {
      await auth.api.post('/reports', data: {
        'target_type': targetType,
        'target_id': targetId,
        'reason': reason,
        'detail': detail,
      });
    } on AppError {
      rethrow;
    }
  }
}
