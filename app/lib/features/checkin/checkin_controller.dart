import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/error/app_error.dart';
import '../../shared/models/checkin.dart';
import '../auth/auth_controller.dart';

/// 发布打卡请求体。
class PublishCheckinReq {
  final CheckinCategory category;
  final String content;
  final List<String> imageUrls;
  final CheckinVisibility visibility;

  const PublishCheckinReq({
    required this.category,
    required this.content,
    this.imageUrls = const [],
    this.visibility = CheckinVisibility.companion,
  });
}

/// 打卡状态（S3-05/S3-07）。
class CheckinController extends ChangeNotifier {
  final AuthController auth;

  List<Checkin> _items = [];
  bool _loading = false;
  bool _publishing = false;

  CheckinController(this.auth);

  List<Checkin> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get publishing => _publishing;

  /// 今日打卡数（按 checkin_date 东八区归属日）。
  int get todayCount {
    final today = _todayLabel();
    return _items.where((c) => c.checkinDate == today).length;
  }

  static String _todayLabel() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// 拉取我的打卡列表（GET /users/{uid}/checkins）。
  /// 网络失败保持现有列表（离线可看最近内容），不打断页面。
  Future<void> load() async {
    final uid = auth.user?.id;
    if (uid == null) return;
    _loading = true;
    notifyListeners();
    try {
      final data = await auth.api.get<Map<String, dynamic>>(
        '/users/$uid/checkins',
        parser: (d) => Map<String, dynamic>.from(d as Map),
      );
      final raw = data['items'] as List<dynamic>? ?? const [];
      _items = raw
          .map((e) => Checkin.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      // 弱网/测试环境：保留现有数据
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 发布打卡（client_token 幂等防重复提交）。
  Future<void> publish(PublishCheckinReq req) async {
    if (_publishing) return;
    _publishing = true;
    notifyListeners();
    try {
      final data = await auth.api.post<Map<String, dynamic>>(
        '/checkins',
        data: {
          'category': req.category.code,
          'content': req.content,
          'image_urls': req.imageUrls,
          'visibility': req.visibility.code,
          'client_token': _clientToken(),
        },
        parser: (d) => Map<String, dynamic>.from(d as Map),
      );
      final c = Checkin.fromJson(data);
      _items.insert(0, c);
      notifyListeners();
    } on AppError {
      rethrow;
    } finally {
      _publishing = false;
      notifyListeners();
    }
  }

  /// 上传单张配图，返回可访问 URL（POST /uploads/images）。
  Future<String> uploadImage(String filePath) async {
    final data = await auth.api.upload<Map<String, dynamic>>(
      '/uploads/images',
      filePath,
      field: 'files',
      parser: (d) => Map<String, dynamic>.from(d as Map),
    );
    final urls = data['urls'] as List<dynamic>? ?? const [];
    if (urls.isEmpty) throw AppError.internal();
    return urls.first as String;
  }

  /// 删除自己的打卡（软删）。
  Future<void> delete(int id) async {
    await auth.api.delete('/checkins/$id');
    _items.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  String _clientToken() =>
      'ct-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
}
