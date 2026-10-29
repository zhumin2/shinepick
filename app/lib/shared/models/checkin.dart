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

  const Checkin({
    required this.id,
    required this.userId,
    required this.category,
    required this.content,
    this.imageUrls = const [],
    this.visibility = 2,
    required this.checkinDate,
    this.createdAt,
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
    );
  }

  CheckinCategory? get categoryEnum => CheckinCategory.byCode(category);
}
