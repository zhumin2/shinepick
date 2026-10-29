import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../models/checkin.dart';
import 'act_btn.dart';
import 'avatar.dart';

/// 微光流打卡卡片（对齐原型：左侧品类色条 + 一句话 + 连续天数 + 互动行）。
/// S2 为视觉骨架；互动回调在 S5 接入真实接口。
class FeedCard extends StatelessWidget {
  final CheckinVO checkin;
  final void Function(String action)? onAction;

  const FeedCard({super.key, required this.checkin, this.onAction});

  @override
  Widget build(BuildContext context) {
    final c = checkin;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, decoration: BoxDecoration(
              color: c.category.color,
              borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Avatar(nickname: c.nickname, size: 32),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.nickname,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textMain)),
                            Text('${c.category.label} · ${c.timeLabel}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textSub)),
                          ],
                        ),
                      ),
                      if (c.streakDays > 0)
                        Text('连续 ${c.streakDays} 天',
                            style: TextStyle(
                                fontSize: 11, color: c.category.color)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(c.content,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: AppTheme.textMain)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ActBtn(
                        icon: Icons.light_mode_outlined,
                        label: '点亮',
                        onTap: () => onAction?.call('light'),
                      ),
                      ActBtn(
                        icon: Icons.favorite_border,
                        label: '拥抱',
                        onTap: () => onAction?.call('hug'),
                      ),
                      ActBtn(
                        icon: Icons.spa_outlined,
                        label: '同路',
                        onTap: () => onAction?.call('companion'),
                      ),
                      ActBtn(
                        icon: Icons.chat_bubble_outline,
                        label: '留言',
                        onTap: () => onAction?.call('comment'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
