import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

/// 打卡状态（S3-05/S3-07；S4 加 Feed 与草稿）。
class CheckinController extends ChangeNotifier {
  final AuthController auth;

  List<Checkin> _items = [];
  bool _loading = false;
  bool _publishing = false;

  // S4: Feed 状态
  List<FeedItem> _dailySelected = [];
  List<FeedItem> _doing = [];
  bool _feedLoading = false;
  bool _feedOffline = false;

  static const _feedBox = 'feed_cache';
  static const _draftBox = 'draft';

  CheckinController(this.auth);

  List<Checkin> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  bool get publishing => _publishing;
  List<FeedItem> get dailySelected => List.unmodifiable(_dailySelected);
  List<FeedItem> get doing => List.unmodifiable(_doing);
  bool get feedLoading => _feedLoading;
  bool get feedOffline => _feedOffline;

  /// 今日打卡数（按 checkin_date 东八区归属日）。
  int get todayCount {
    final today = _todayLabel();
    return _items.where((c) => c.checkinDate == today).length;
  }

  /// 今日已打卡的品类集合（今日卡勾选态用）。
  Set<int> get todayCategories {
    final today = _todayLabel();
    return {
      for (final c in _items)
        if (c.checkinDate == today) c.category,
    };
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
  /// 传字节而非路径：Web 上 file_picker 只提供 bytes（没有本地路径）。
  Future<String> uploadImage(Uint8List bytes, String filename) async {
    final data = await auth.api.uploadBytes<Map<String, dynamic>>(
      '/uploads/images',
      bytes,
      filename: filename,
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

  /// 拉取首页 Feed（GET /feed）。
  /// 弱网/断网时回退到上次缓存（S4-06），页面提示"展示最近内容"。
  Future<void> loadFeed() async {
    _feedLoading = true;
    _feedOffline = false;
    notifyListeners();
    try {
      final data = await auth.api.get<Map<String, dynamic>>(
        '/feed',
        parser: (d) => Map<String, dynamic>.from(d as Map),
      );
      _dailySelected = _parseFeedItems(data['daily_selected']);
      _doing = _parseFeedItems(data['doing']);
      await _saveFeedCache();
    } catch (_) {
      final cached = await _readFeedCache();
      if (cached != null) {
        _dailySelected = cached.$1;
        _doing = cached.$2;
        _feedOffline = true;
      }
    } finally {
      _feedLoading = false;
      notifyListeners();
    }
  }

  List<FeedItem> _parseFeedItems(dynamic raw) =>
      (raw as List<dynamic>? ?? const [])
          .map((e) => FeedItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

  Future<void> _saveFeedCache() async {
    try {
      final box = await Hive.openBox(_feedBox);
      await box.put('v1', jsonEncode({
        'daily_selected': _dailySelected.map((e) => e.toJson()).toList(),
        'doing': _doing.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {
      // 缓存失败不影响主流程
    }
  }

  Future<(List<FeedItem>, List<FeedItem>)?> _readFeedCache() async {
    try {
      final box = await Hive.openBox(_feedBox);
      final raw = box.get('v1') as String?;
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return (
        _parseFeedItems(data['daily_selected']),
        _parseFeedItems(data['doing']),
      );
    } catch (_) {
      return null;
    }
  }

  // ---- 打卡草稿（S4-06：断网/退出弹层不丢内容） ----

  Future<void> saveDraft(String content) async {
    try {
      final box = await Hive.openBox(_draftBox);
      await box.put('checkin', content);
    } catch (_) {}
  }

  Future<String> readDraft() async {
    try {
      final box = await Hive.openBox(_draftBox);
      return box.get('checkin') as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> clearDraft() async {
    try {
      final box = await Hive.openBox(_draftBox);
      await box.delete('checkin');
    } catch (_) {}
  }

  /// client_token：时间戳 + 随机后缀，用于服务端幂等。
  /// 注：使用 1<<31（而非 1<<32）避开 Web(dart2js) 的 32 位位移边界。
  String _clientToken() =>
      'ct-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 31)}';

  // ---- S5-04 互动（乐观更新 + 失败回滚） ----

  /// 切换互动：已选中则取消，未选中则添加。同路额外建立同路人关系。
  Future<void> toggleReaction(int checkinId, int type) async {
    final snapshot = _findCheckin(checkinId);
    if (snapshot == null) return;
    final active = snapshot.hasReaction(type);
    // 乐观更新
    _applyReaction(checkinId, type, add: !active);
    notifyListeners();
    try {
      if (active) {
        await auth.api.delete('/checkins/$checkinId/reactions?type=$type');
      } else {
        await auth.api.post(
          '/checkins/$checkinId/reactions',
          data: {'type': type},
        );
      }
    } catch (_) {
      // 回滚
      _applyReaction(checkinId, type, add: active);
      notifyListeners();
      rethrow;
    }
  }

  Checkin? _findCheckin(int id) {
    for (final c in _items) {
      if (c.id == id) return c;
    }
    for (final f in _dailySelected) {
      if (f.checkin.id == id) return f.checkin;
    }
    for (final f in _doing) {
      if (f.checkin.id == id) return f.checkin;
    }
    return null;
  }

  void _applyReaction(int checkinId, int type, {required bool add}) {
    List<int> next(Checkin c) {
      final s = c.myReactions.toSet();
      add ? s.add(type) : s.remove(type);
      final l = s.toList()..sort();
      return l;
    }

    _items = [
      for (final c in _items)
        c.id == checkinId ? c.copyWith(myReactions: next(c)) : c
    ];
    _dailySelected = [
      for (final f in _dailySelected)
        f.checkin.id == checkinId
            ? f.copyWith(checkin: f.checkin.copyWith(myReactions: next(f.checkin)))
            : f
    ];
    _doing = [
      for (final f in _doing)
        f.checkin.id == checkinId
            ? f.copyWith(checkin: f.checkin.copyWith(myReactions: next(f.checkin)))
            : f
    ];
  }

  // ---- S5-05 留言 ----

  /// 拉取某条打卡的留言（新→旧）。
  Future<List<CommentVO>> loadComments(int checkinId, {int cursor = 0}) async {
    final data = await auth.api.get<Map<String, dynamic>>(
      '/checkins/$checkinId/comments${cursor > 0 ? '?cursor=$cursor' : ''}',
      parser: (d) => Map<String, dynamic>.from(d as Map),
    );
    final raw = data['items'] as List<dynamic>? ?? const [];
    return raw
        .map((e) => CommentVO.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// 发留言（≤80 字；client_token 幂等）。
  Future<CommentVO> addComment(int checkinId, String content) async {
    final data = await auth.api.post<Map<String, dynamic>>(
      '/checkins/$checkinId/comments',
      data: {'content': content, 'client_token': _clientToken()},
      parser: (d) => Map<String, dynamic>.from(d as Map),
    );
    return CommentVO.fromJson(data);
  }

  /// 删除留言（本人或打卡作者）。
  Future<void> deleteComment(int commentId) async {
    await auth.api.delete('/comments/$commentId');
  }

  /// 作者指定/取消某条留言在卡片上展示（S5 增强）。
  Future<void> setCommentFeatured(int commentId, bool featured) async {
    await auth.api.patch(
      '/comments/$commentId/feature',
      data: {'featured': featured},
    );
    // 让卡片预览立即反映（下次刷新服务端也会返回正确排序）
    await load();
    await loadFeed();
  }
}
