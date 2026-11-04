import 'dart:convert';

import 'package:flutter/material.dart';

/// 解析服务端 ISO 时间并归一到本地时区。
/// 必须显式 toLocal()：Dart 对带时区偏移的串（如 +08:00）解析后返回的是
/// UTC 换算值（isUtc=true），直接取字段显示会差 8 小时。
DateTime? parseLocalTime(String? s) =>
    s == null ? null : DateTime.tryParse(s)?.toLocal();

/// 友好时间标签（打卡/留言/通知共用）：
/// 今天 → HH:mm；昨天 → 昨天 HH:mm；今年 → MM-DD HH:mm；跨年 → yyyy-MM-DD HH:mm。
String friendlyTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final hm =
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final diffDays = today.difference(day).inDays;
  if (diffDays <= 0) return hm; // 今天
  if (diffDays == 1) return '昨天 $hm';
  final md =
      '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  if (t.year == now.year) return '$md $hm';
  return '${t.year}-$md $hm';
}

/// 打卡品类（对齐产品设计文档 §3.2 五大品类；6=自定义 S3 暂不开放）。
enum CheckinCategory {
  sport(1, '运动', Color(0xFFE89B3C)),
  read(2, '阅读', Color(0xFF7FA98F)),
  travel(3, '旅行', Color(0xFF7FA8C9)),
  social(4, '社交', Color(0xFFDDA5A0)),
  pet(5, '宠物', Color(0xFFD9B36C)),
  custom(6, '其他', Color(0xFFB8A6D9));

  const CheckinCategory(this.code, this.label, this.color);
  final int code;
  final String label;
  final Color color;

  static CheckinCategory? byCode(int code) {
    for (final c in values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// 可见范围（对齐后端 1仅自己 2同路人 3小树洞）。
enum CheckinVisibility {
  private(1, '仅自己'),
  companion(2, '同路人'),
  treehole(3, '我的小树洞');

  const CheckinVisibility(this.code, this.label);
  final int code;
  final String label;
}

/// 打卡数据（对齐后端 CheckinVO）。
class Checkin {
  final int id;
  final int userId;
  final int category;

  /// category=6（自定义）时的品类名
  final String customName;
  final String content;
  final List<String> imageUrls;
  final int visibility;
  final String checkinDate;
  final DateTime? createdAt;

  /// 当前观众已点的互动类型（S5：1点亮 2拥抱 3同路）
  final List<int> myReactions;

  /// 卡片展示的留言（最多 2 条；作者指定优先，不暴露总数）
  final List<CommentVO> previewComments;

  /// 情绪标签（emoji 列表，如 ["😊","💪"]；存于 extra.moods）
  final List<String> moods;

  const Checkin({
    required this.id,
    required this.userId,
    required this.category,
    required this.content,
    this.imageUrls = const [],
    this.visibility = 2,
    required this.checkinDate,
    this.createdAt,
    this.myReactions = const [],
    this.previewComments = const [],
    this.customName = '',
    this.moods = const [],
  });

  factory Checkin.fromJson(Map<String, dynamic> json) {
    return Checkin(
      id: (json['id'] as num).toInt(),
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      category: (json['category'] as num?)?.toInt() ?? 1,
      content: json['content'] as String? ?? '',
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      customName: json['custom_name'] as String? ?? '',
      visibility: (json['visibility'] as num?)?.toInt() ?? 2,
      checkinDate: json['checkin_date'] as String? ?? '',
      createdAt: parseLocalTime(json['created_at'] as String?),
      myReactions: (json['my_reactions'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      previewComments: (json['preview_comments'] as List<dynamic>?)
              ?.map((e) =>
                  CommentVO.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      moods: _parseMoods(json['extra']),
    );
  }

  /// 从 extra 解析 moods（后端透传的可能是 Map 或 JSON 字符串）。
  static List<String> _parseMoods(dynamic extra) {
    if (extra == null) return const [];
    try {
      final Map<dynamic, dynamic> m = extra is Map
          ? extra
          : (extra is String && extra.isNotEmpty
              ? Map.from(_jsonDecode(extra) as Map)
              : const {});
      final raw = m['moods'] as List<dynamic>?;
      return raw?.map((e) => e.toString()).toList() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static dynamic _jsonDecode(String s) {
    // ignore: avoid_dynamic_calls
    return const JsonDecoder().convert(s);
  }

  /// 带互动态/预览留言的新副本（乐观更新用）。
  Checkin copyWith(
          {List<int>? myReactions,
          List<CommentVO>? previewComments,
          String? customName,
          List<String>? moods,
          int? visibility}) =>
      Checkin(
        id: id,
        userId: userId,
        category: category,
        customName: customName ?? this.customName,
        content: content,
        imageUrls: imageUrls,
        visibility: visibility ?? this.visibility,
        checkinDate: checkinDate,
        createdAt: createdAt,
        myReactions: myReactions ?? this.myReactions,
        previewComments: previewComments ?? this.previewComments,
        moods: moods ?? this.moods,
      );

  bool hasReaction(int type) => myReactions.contains(type);

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'category': category,
        'content': content,
        'image_urls': imageUrls,
        'visibility': visibility,
        'checkin_date': checkinDate,
        'created_at': createdAt?.toIso8601String(),
        'my_reactions': myReactions,
        if (moods.isNotEmpty) 'extra': {'moods': moods},
      };

  CheckinCategory? get categoryEnum => CheckinCategory.byCode(category);

  /// 展示名（自定义=固定兜底门类「其他」）
  String get categoryLabel => categoryEnum?.label ?? '其他';
}

/// Feed 条目作者信息。
class FeedUser {
  final int id;
  final String nickname;
  final String avatarUrl;

  /// 连续打卡天数（同路人卡展示用；feed 树缓存里可能缺省）
  final int streakDays;

  const FeedUser({
    required this.id,
    required this.nickname,
    this.avatarUrl = '',
    this.streakDays = 0,
  });

  factory FeedUser.fromJson(Map<String, dynamic> json) => FeedUser(
        id: (json['id'] as num).toInt(),
        nickname: json['nickname'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String? ?? '',
        streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'avatar_url': avatarUrl,
        'streak_days': streakDays,
      };
}

/// Feed 条目（今日微光 / 同品类打卡的陌生人 / 发现页）。
class FeedItem {
  final Checkin checkin;
  final FeedUser user;

  const FeedItem({required this.checkin, required this.user});

  factory FeedItem.fromJson(Map<String, dynamic> json) => FeedItem(
        checkin: Checkin.fromJson(json),
        user: FeedUser.fromJson(
            Map<String, dynamic>.from(json['user'] as Map? ?? const {})),
      );

  FeedItem copyWith({Checkin? checkin}) =>
      FeedItem(checkin: checkin ?? this.checkin, user: user);

  Map<String, dynamic> toJson() => {
        ...checkin.toJson(),
        'user': user.toJson(),
      };
}

/// 拾光周报（对齐后端 WeeklyReportVO）。
class WeeklyReportVO {
  final String startDate;
  final String endDate;
  final int count;
  final int days;
  final int streakDays;
  final int lastCount;
  final int delta;
  final List<DailyPoint> daily;
  final List<CategoryStat> categories;

  const WeeklyReportVO({
    required this.startDate,
    required this.endDate,
    required this.count,
    required this.days,
    required this.streakDays,
    required this.lastCount,
    required this.delta,
    required this.daily,
    required this.categories,
  });

  factory WeeklyReportVO.fromJson(Map<String, dynamic> json) => WeeklyReportVO(
        startDate: json['start_date'] as String? ?? '',
        endDate: json['end_date'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        days: (json['days'] as num?)?.toInt() ?? 0,
        streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
        lastCount: (json['last_count'] as num?)?.toInt() ?? 0,
        delta: (json['delta'] as num?)?.toInt() ?? 0,
        daily: (json['daily'] as List<dynamic>? ?? const [])
            .map((e) => DailyPoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        categories: (json['categories'] as List<dynamic>? ?? const [])
            .map((e) =>
                CategoryStat.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

/// 周报单日：日期 + 星期序号（1=周一）+ 次数 + 主品类（0=无）。
class DailyPoint {
  final String date;
  final int weekday;
  final int count;
  final int category;

  const DailyPoint({
    required this.date,
    required this.weekday,
    required this.count,
    required this.category,
  });

  factory DailyPoint.fromJson(Map<String, dynamic> json) => DailyPoint(
        date: json['date'] as String? ?? '',
        weekday: (json['weekday'] as num?)?.toInt() ?? 1,
        count: (json['count'] as num?)?.toInt() ?? 0,
        category: (json['category'] as num?)?.toInt() ?? 0,
      );

  CheckinCategory? get categoryEnum =>
      category < 1 || category > 6 ? null : CheckinCategory.byCode(category);

  /// 柱状图日标签：一 二 三 四 五 六 日
  String get weekdayLabel => const ['一', '二', '三', '四', '五', '六', '日']
      [(weekday - 1).clamp(0, 6)];
}

/// 品类分布项。
class CategoryStat {
  final int category;
  final int count;

  const CategoryStat({required this.category, required this.count});

  factory CategoryStat.fromJson(Map<String, dynamic> json) => CategoryStat(
        category: (json['category'] as num?)?.toInt() ?? 6,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  CheckinCategory get categoryEnum =>
      CheckinCategory.byCode(category) ?? CheckinCategory.custom;
}

/// 小便签留言（对齐后端 CommentVO）。
class CommentVO {
  final int id;
  final int checkinId;
  final int userId;
  final String nickname;
  final String avatarUrl;
  final String content;

  /// 作者指定在卡片上展示
  final bool isFeatured;
  final DateTime? createdAt;

  const CommentVO({
    required this.id,
    required this.checkinId,
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.content,
    this.isFeatured = false,
    this.createdAt,
  });

  factory CommentVO.fromJson(Map<String, dynamic> json) => CommentVO(
        id: (json['id'] as num).toInt(),
        checkinId: (json['checkin_id'] as num?)?.toInt() ?? 0,
        userId: (json['user_id'] as num?)?.toInt() ?? 0,
        nickname: json['nickname'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String? ?? '',
        content: json['content'] as String? ?? '',
        isFeatured: json['is_featured'] == true,
        createdAt: parseLocalTime(json['created_at'] as String?),
      );

  CommentVO copyWith({bool? isFeatured}) => CommentVO(
        id: id,
        checkinId: checkinId,
        userId: userId,
        nickname: nickname,
        avatarUrl: avatarUrl,
        content: content,
        isFeatured: isFeatured ?? this.isFeatured,
        createdAt: createdAt,
      );

  /// 时间标签：带日期语义（今天 HH:mm / 昨天 HH:mm / MM-DD HH:mm）。
  String get timeLabel => friendlyTime(createdAt);
}

/// 应用内通知（对齐后端 NotificationVO）。
class NotificationVO {
  final int id;
  final int type; // 1点亮 2拥抱 3同路 4留言 5系统
  final int? actorId;
  final String actorName;
  final int? checkinId;
  final int? commentId;
  final int aggCount;
  final String copy;
  final bool isRead;
  final DateTime? createdAt;

  const NotificationVO({
    required this.id,
    required this.type,
    required this.copy,
    this.actorId,
    this.actorName = '',
    this.checkinId,
    this.commentId,
    this.aggCount = 1,
    this.isRead = false,
    this.createdAt,
  });

  factory NotificationVO.fromJson(Map<String, dynamic> json) =>
      NotificationVO(
        id: (json['id'] as num).toInt(),
        type: (json['type'] as num?)?.toInt() ?? 5,
        actorId: (json['actor_id'] as num?)?.toInt(),
        actorName: json['actor_name'] as String? ?? '',
        checkinId: (json['checkin_id'] as num?)?.toInt(),
        commentId: (json['comment_id'] as num?)?.toInt(),
        aggCount: (json['agg_count'] as num?)?.toInt() ?? 1,
        copy: json['copy'] as String? ?? '',
        isRead: json['is_read'] == true,
        createdAt: parseLocalTime(json['created_at'] as String?),
      );

  /// 相对时间。
  String get timeLabel {
    final t = createdAt;
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${t.month}-${t.day.toString().padLeft(2, '0')}';
  }
}

/// 拾光树状态（对齐后端 TreeVO）。
class TreeVO {
  final int level;
  final int points;
  final int season; // 1春 2夏 3秋 4冬
  final int yearCount;
  final int yearTarget;
  final int streakDays;
  final int total;
  final List<LightPoint> lightPoints;

  const TreeVO({
    required this.level,
    required this.points,
    required this.season,
    required this.yearCount,
    required this.yearTarget,
    required this.streakDays,
    required this.total,
    required this.lightPoints,
  });

  factory TreeVO.fromJson(Map<String, dynamic> json) {
    return TreeVO(
      level: (json['level'] as num?)?.toInt() ?? 1,
      points: (json['points'] as num?)?.toInt() ?? 0,
      season: (json['season'] as num?)?.toInt() ?? 1,
      yearCount: (json['year_count'] as num?)?.toInt() ?? 0,
      yearTarget: (json['year_target'] as num?)?.toInt() ?? 300,
      streakDays: (json['streak_days'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      lightPoints: (json['light_points'] as List<dynamic>? ?? const [])
          .map((e) => LightPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  double get yearProgress =>
      yearTarget <= 0 ? 0 : (yearCount / yearTarget).clamp(0.0, 1.0);
}

/// 树页光点（= 一次打卡）。
class LightPoint {
  final String date;
  final int category;

  const LightPoint({required this.date, required this.category});

  factory LightPoint.fromJson(Map<String, dynamic> json) => LightPoint(
        date: json['date'] as String? ?? '',
        category: (json['category'] as num?)?.toInt() ?? 1,
      );
}

/// 徽章（对齐后端 BadgeVO）。
class BadgeVO {
  final String code;
  final String name;
  final String icon;
  final String description;
  final bool owned;
  final DateTime? earnedAt;

  const BadgeVO({
    required this.code,
    required this.name,
    required this.icon,
    required this.description,
    required this.owned,
    this.earnedAt,
  });

  factory BadgeVO.fromJson(Map<String, dynamic> json) => BadgeVO(
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
        description: json['description'] as String? ?? '',
        owned: json['owned'] == true,
        earnedAt: parseLocalTime(json['earned_at'] as String?),
      );
}


/// 黑名单条目（对齐后端 BlockedUserRow）。
class BlockedUser {
  final int userId;
  final String nickname;
  final String avatarUrl;

  const BlockedUser({
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) => BlockedUser(
        userId: (json['user_id'] as num).toInt(),
        nickname: json['nickname'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String? ?? '',
      );
}
