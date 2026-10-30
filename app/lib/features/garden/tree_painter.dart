import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';

/// 拾光树画笔（S7-03）：12 阶段树 + 光点呼吸 + 季节色调。
/// 树随 level 长大：树干变高变粗、树冠变大变密；光点 = 打卡历史，
/// 以品类色散落在树冠周围，呼吸式闪烁（对齐原型 glow 动画）。
class TreePainter extends CustomPainter {
  final int level; // 1-12
  final int season; // 1春 2夏 3秋 4冬
  final List<LightPoint> lightPoints;
  final double breath; // 0..1 呼吸相位

  TreePainter({
    required this.level,
    required this.season,
    required this.lightPoints,
    required this.breath,
  });

  static const _trunkColor = Color(0xFF8B6F52);

  Color get _leafBase {
    switch (season) {
      case 1:
        return const Color(0xFFA9C99A); // 春：嫩绿
      case 2:
        return const Color(0xFF6FA97C); // 夏：深绿
      case 3:
        return const Color(0xFFD9A85C); // 秋：暖橙
      default:
        return const Color(0xFFC9D6DC); // 冬：雪色（枝干为主）
    }
  }

  Color get _leafDark {
    switch (season) {
      case 1:
        return const Color(0xFF8FB584);
      case 2:
        return const Color(0xFF5C8F68);
      case 3:
        return const Color(0xFFC98F45);
      default:
        return const Color(0xFFB4C4CC);
    }
  }

  Color _dotColor(int category) {
    switch (category) {
      case 1:
        return const Color(0xFFE89B3C);
      case 2:
        return const Color(0xFF7FA98F);
      case 3:
        return const Color(0xFF7FA8C9);
      case 4:
        return const Color(0xFFDDA5A0);
      case 5:
        return const Color(0xFFD9B36C);
      default:
        return const Color(0xFFB8A6D9);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final groundY = h - 28;
    final f = ((level - 1) / 11).clamp(0.0, 1.0); // 0..1 成长进度

    // 地面光晕
    final groundPaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.10 + 0.06 * breath)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawCircle(Offset(cx, groundY + 8), 60 + 30 * f, groundPaint);

    // 树干（梯形，越高级越粗越高）
    final trunkW = 7.0 + 16.0 * f;
    final trunkH = 58.0 + 96.0 * f;
    final trunk = Path()
      ..moveTo(cx - trunkW / 2, groundY)
      ..lineTo(cx - trunkW / 4, groundY - trunkH)
      ..lineTo(cx + trunkW / 4, groundY - trunkH)
      ..lineTo(cx + trunkW / 2, groundY)
      ..close();
    canvas.drawPath(trunk, Paint()..color = _trunkColor);

    // 枝干线条（level>=5 明显；冬天光秃更突出）
    final branchPaint = Paint()
      ..color = _trunkColor
      ..strokeWidth = 2.5 + 2.0 * f
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final branchCount = season == 4 ? 5 : 3;
    for (var i = 0; i < branchCount; i++) {
      final side = i.isEven ? 1.0 : -1.0;
      final len = 16.0 + 26.0 * f;
      final path = Path()
        ..moveTo(cx, groundY - trunkH * 0.72)
        ..quadraticBezierTo(
          cx + side * len * 0.7,
          groundY - trunkH * (0.85 + 0.06 * i),
          cx + side * len,
          groundY - trunkH * (1.0 + 0.05 * i),
        );
      canvas.drawPath(path, branchPaint);
    }

    // 树冠：圆簇（数量/半径随 level 增长；冬天稀疏如落雪后的残叶）
    final foliageCount = season == 4 ? (2 + level ~/ 3) : (3 + level);
    final baseR = 13.0 + 17.0 * f;
    final topY = groundY - trunkH - baseR * 0.4;
    final rng = Random(7); // 确定性：同一 level 每次绘制相同
    for (var i = 0; i < foliageCount; i++) {
      final angle = i * 2.39996; // 黄金角
      final dist = baseR * (0.35 + 0.75 * rng.nextDouble() * (0.4 + 0.6 * f));
      final ox = cos(angle) * dist * 1.25;
      final oy = sin(angle) * dist * 0.62;
      final r = baseR * (0.55 + 0.45 * rng.nextDouble());
      final shade = i.isEven ? _leafBase : _leafDark;
      canvas.drawCircle(
        Offset(cx + ox, topY + oy),
        r,
        Paint()..color = shade.withValues(alpha: 0.92),
      );
    }
    // 冬季：枝头挂雪
    if (season == 4) {
      final snow = Paint()..color = Colors.white.withValues(alpha: 0.9);
      for (var i = 0; i < 6 + level; i++) {
        final angle = i * 2.39996;
        final dist = baseR * (0.3 + 0.9 * rng.nextDouble());
        canvas.drawCircle(
          Offset(cx + cos(angle) * dist, topY + sin(angle) * dist * 0.6),
          1.6,
          snow,
        );
      }
    }

    // 光点：打卡历史散落在树冠外围两圈，品类着色，呼吸闪烁
    final dots = lightPoints.take(60).toList();
    for (var i = 0; i < dots.length; i++) {
      final ring = i < 20 ? 0 : 1;
      final idx = ring == 0 ? i : i - 20;
      final angle = idx * 2.39996 + (ring == 1 ? 0.8 : 0.0);
      final dist = baseR * (1.5 + 0.8 * ring) + 14.0;
      final phase = (breath + i * 0.13) % 1.0;
      final glow = 0.45 + 0.55 * (0.5 + 0.5 * sin(phase * 2 * pi));
      final c = _dotColor(dots[i].category);
      final center = Offset(
        cx + cos(angle) * dist * 1.35,
        topY + 20 + sin(angle) * dist * 0.75,
      );
      canvas.drawCircle(
        center,
        3.2 + 1.4 * glow,
        Paint()..color = c.withValues(alpha: 0.55 + 0.4 * glow),
      );
      canvas.drawCircle(
        center,
        7.0 + 3.0 * glow,
        Paint()..color = c.withValues(alpha: 0.12 * glow),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TreePainter oldDelegate) =>
      oldDelegate.level != level ||
      oldDelegate.season != season ||
      oldDelegate.breath != breath ||
      oldDelegate.lightPoints.length != lightPoints.length;
}

/// 树的阶段名（对齐产品「看见树长大」）。
String treeStageName(int level) {
  const names = [
    '种子',
    '破土',
    '小苗',
    '抽芽',
    '幼苗',
    '小树',
    '成长',
    '枝繁',
    '挺拔',
    '茂盛',
    '参天',
    '拾光之树',
  ];
  if (level < 1 || level > 12) return names[0];
  return names[level - 1];
}

/// 季节名。
String seasonName(int season) {
  switch (season) {
    case 1:
      return '春';
    case 2:
      return '夏';
    case 3:
      return '秋';
    default:
      return '冬';
  }
}
