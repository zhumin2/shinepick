import 'package:flutter/material.dart';

/// 打卡品类（对齐产品设计文档 §3.2 五大品类）。
enum CheckinCategory {
  sport(1, '运动', Color(0xFFE89B3C)),
  read(2, '阅读', Color(0xFF7FA98F)),
  travel(3, '旅行', Color(0xFF7FA8C9)),
  social(4, '社交', Color(0xFFDDA5A0)),
  pet(5, '宠物', Color(0xFFD9B36C));

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

/// 打卡卡片数据（S2 组件骨架；S3 接入真实接口后扩展字段）。
class CheckinVO {
  final int id;
  final int userId;
  final String nickname;
  final CheckinCategory category;
  final String content;
  final String timeLabel;
  final int streakDays;

  const CheckinVO({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.category,
    required this.content,
    required this.timeLabel,
    this.streakDays = 0,
  });
}
