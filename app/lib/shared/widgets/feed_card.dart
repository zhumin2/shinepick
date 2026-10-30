import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../models/checkin.dart';
import 'act_btn.dart';
import 'avatar.dart';

/// 打卡卡片（对齐原型：左侧品类色条 + 一句话 + 配图 + 互动行）。
/// S3 用于"我的近期打卡"；S5 接互动、S6 接删除/举报等长按操作。
class FeedCard extends StatelessWidget {
  final Checkin checkin;
  final String nickname;
  final String? avatarUrl;
  final int streakDays;
  final void Function(String action)? onAction;

  const FeedCard({
    super.key,
    required this.checkin,
    this.nickname = '我',
    this.avatarUrl,
    this.streakDays = 0,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = checkin;
    final cat = c.categoryEnum ?? CheckinCategory.sport;
    final time = _timeLabel();
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
              color: cat.color,
              borderRadius: BorderRadius.circular(2),
            )),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Avatar(url: avatarUrl, nickname: nickname, size: 32),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nickname,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textMain)),
                            Text('${cat.label} · $time',
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textSub)),
                          ],
                        ),
                      ),
                      Text(c.visibilityLabel,
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textSub)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(c.content,
                      style: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: AppTheme.textMain)),
                  if (c.imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    // 单图：全宽完整显示；多图：宫格缩略（对齐主流内容流惯例）
                    if (c.imageUrls.length == 1)
                      _FullImage(url: c.imageUrls.first)
                    else
                      SizedBox(
                        height: 76,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: c.imageUrls.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              c.imageUrls[i],
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 76,
                                height: 76,
                                color: AppTheme.bg,
                                child: const Icon(Icons.broken_image_outlined,
                                    color: AppTheme.textSub, size: 20),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                  // 留言预览（最多 2 条，作者指定优先；不显示总数——产品 4.6）
                  if (c.previewComments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      decoration: BoxDecoration(
                        color: AppTheme.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < c.previewComments.length; i++) ...[
                            if (i > 0) const SizedBox(height: 6),
                            _PreviewLine(comment: c.previewComments[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ActBtn(
                        icon: Icons.light_mode_outlined,
                        label: '点亮',
                        selected: c.hasReaction(1),
                        onTap: () => onAction?.call('light'),
                      ),
                      ActBtn(
                        icon: Icons.favorite_border,
                        label: '拥抱',
                        selected: c.hasReaction(2),
                        onTap: () => onAction?.call('hug'),
                      ),
                      ActBtn(
                        icon: Icons.spa_outlined,
                        label: '同路',
                        selected: c.hasReaction(3),
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

  String _timeLabel() {
    final t = checkin.createdAt;
    if (t == null) return checkin.checkinDate;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

extension on Checkin {
  String get visibilityLabel {
    switch (visibility) {
      case 1:
        return '仅自己';
      case 3:
        return '小树洞';
      default:
        return '同路人';
    }
  }
}

/// 单条留言预览：小便签的视觉（作者指定的带小星标）。
class _PreviewLine extends StatelessWidget {
  final CommentVO comment;
  const _PreviewLine({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          comment.isFeatured ? Icons.push_pin_outlined : Icons.chat_bubble_outline,
          size: 12,
          color: comment.isFeatured
              ? AppTheme.primary
              : AppTheme.textSub.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 6),
        Text(comment.nickname,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSub)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            comment.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 12, height: 1.4, color: AppTheme.textMain),
          ),
        ),
      ],
    );
  }
}

/// 单图全宽完整显示（最大高度 360 超出按 contain 完整可见，不裁切）。
class _FullImage extends StatelessWidget {
  final String url;
  const _FullImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            height: 120,
            color: AppTheme.bg,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined,
                color: AppTheme.textSub, size: 28),
          ),
        ),
      ),
    );
  }
}
