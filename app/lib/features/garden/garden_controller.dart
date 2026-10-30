import 'package:flutter/foundation.dart';

import '../../shared/models/checkin.dart';
import '../auth/auth_controller.dart';

/// 拾光树与徽章状态（S7）。
class GardenController extends ChangeNotifier {
  final AuthController auth;

  TreeVO? _tree;
  List<BadgeVO> _badges = [];
  bool _loading = false;

  GardenController(this.auth);

  TreeVO? get tree => _tree;
  List<BadgeVO> get badges => List.unmodifiable(_badges);
  bool get loading => _loading;

  /// 已获得的徽章数。
  int get ownedCount => _badges.where((b) => b.owned).length;

  /// 加载树 + 徽章（先幂等补发历史徽章，再拉取）。
  /// 弱网时保留旧数据，不打断页面。
  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      await _evaluateBadges();
      await Future.wait([_loadTree(), _loadBadges()]);
    } catch (_) {
      // 弱网/测试环境：保留现有数据
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadTree() async {
    final data = await auth.api.get<Map<String, dynamic>>(
      '/tree',
      parser: (d) => Map<String, dynamic>.from(d as Map),
    );
    _tree = TreeVO.fromJson(data);
  }

  Future<void> _loadBadges() async {
    final data = await auth.api.get<Map<String, dynamic>>(
      '/badges',
      parser: (d) => Map<String, dynamic>.from(d as Map),
    );
    final raw = data['items'] as List<dynamic>? ?? const [];
    _badges = raw
        .map((e) => BadgeVO.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> _evaluateBadges() async {
    try {
      await auth.api.post('/badges/evaluate');
    } catch (_) {
      // 补发失败不阻塞树页
    }
  }
}
