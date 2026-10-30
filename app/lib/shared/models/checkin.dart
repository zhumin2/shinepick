import 'package:flutter/material.dart';

/// 打卡品类（对齐产品设计文档 §3.2 五大品类；6=自定义 S3 暂不开放）。
enum CheckinCategory {
  sport(1, '运动', Color(0xFFE89B3C)),
  read(2, '阅读', Color(0xFF7FA98F)),
  travel(3, '旅行', Color(0xFF7FA8C9)),
  social(4, '社交', Color(0xFFDDA5A0)),
  pet(5, '宠物', Color(0xFFD9B36C)),
  custom(6, '自定义', Color(0xFFB8A6D9));

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
  final String content;
  final List<String> imageUrls;
  final int visibility;
  final String checkinDate;
  final DateTime? createdAt;

  /// 当前观众已点的互动类型（S5：1点亮 2拥抱 3同路）
  final List<int> myReactions;

  /// 卡片展示的留言（最多 2 条；作者指定优先，不暴露总数）
  final List<CommentVO> previewComments;

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
      visibility: (json['visibility'] as num?)?.toInt() ?? 2,
      checkinDate: json['checkin_date'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      myReactions: (json['my_reactions'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      previewComments: (json['preview_comments'] as List<dynamic>?)
              ?.map((e) =>
                  CommentVO.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }

  /// 带互动态/预览留言的新副本（乐观更新用）。
  Checkin copyWith({List<int>? myReactions, List<CommentVO>? previewComments}) =>
      Checkin(
        id: id,
        userId: userId,
        category: category,
        content: content,
        imageUrls: imageUrls,
        visibility: visibility,
        checkinDate: checkinDate,
        createdAt: createdAt,
        myReactions: myReactions ?? this.myReactions,
        previewComments: previewComments ?? this.previewComments,
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
      };

  CheckinCategory? get categoryEnum => CheckinCategory.byCode(category);
}

/// Feed 条目作者信息。
class FeedUser {
  final int id;
  final String nickname;
  final String avatarUrl;

  const FeedUser({
    required this.id,
    required this.nickname,
    this.avatarUrl = '',
  });

  factory FeedUser.fromJson(Map<String, dynamic> json) => FeedUser(
        id: (json['id'] as num).toInt(),
        nickname: json['nickname'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'nickname': nickname, 'avatar_url': avatarUrl};
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
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
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

  /// 相对时间：刚刚 / N 分钟前 / HH:mm。
  String get timeLabel {
    final t = createdAt;
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
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
        createdAt: json['created_at'] != null
            ? DateTime.tryParse(json['created_at'] as String)
            : null,
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
