import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../models/checkin.dart';
import 'avatar.dart';

/// 微光流打卡卡片（对齐原型 feed-card）：
/// 品类渐变封面（无图也有）+ meta 行 + 一句话 + 配图 + 胶囊互动钮 + 留言预览。
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
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面：无图时用品类渐变（原型 cover），有图走配图区
          if (c.imageUrls.isEmpty) _CoverGradient(category: cat),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                Avatar(url: avatarUrl, nickname: nickname, size: 26),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$nickname · ${cat.label} · ${_timeLabel()}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSub),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(c.visibilityLabel,
                    style: TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSub.withValues(alpha: 0.7))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text(c.content,
                style: const TextStyle(
                    fontSize: 14, height: 1.55, color: AppTheme.textMain)),
          ),
          // 配图
          if (c.imageUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: c.imageUrls.length == 1
                  ? _FullImage(url: c.imageUrls.first)
                  : _ImageGrid(urls: c.imageUrls),
            ),
          // 留言预览（我们的增强：作者图钉指定优先）
          if (c.previewComments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            ),
          // 胶囊互动钮（原型 act-btn：描边胶囊，选中暖沙底）
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActPill(
                  icon: Icons.light_mode_outlined,
                  label: '点亮',
                  selected: c.hasReaction(1),
                  onTap: () => onAction?.call('light'),
                ),
                _ActPill(
                  icon: Icons.favorite_border,
                  label: '拥抱',
                  selected: c.hasReaction(2),
                  onTap: () => onAction?.call('hug'),
                ),
                _ActPill(
                  icon: Icons.spa_outlined,
                  label: '同路',
                  selected: c.hasReaction(3),
                  onTap: () => onAction?.call('companion'),
                ),
                _ActPill(
                  icon: Icons.chat_bubble_outline,
                  label: '留言',
                  onTap: () => onAction?.call('comment'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 时间标签：今天 HH:mm / 昨天 HH:mm / 更早 MM-DD HH:mm。
  String _timeLabel() {
    final t = checkin.createdAt;
    if (t == null) return checkin.checkinDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final diffDays = today.difference(day).inDays;
    if (diffDays <= 0) return hm;
    if (diffDays == 1) return '昨天 $hm';
    final md =
        '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    if (t.year == now.year) return '$md $hm';
    return '${t.year}-$md $hm';
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

/// 品类渐变封面（原型 .cov-*：无图打卡也有视觉锚）。
class _CoverGradient extends StatelessWidget {
  final CheckinCategory category;
  const _CoverGradient({required this.category});

  @override
  Widget build(BuildContext context) {
    final (c1, c2, icon) = switch (category) {
      CheckinCategory.sport => (
          const Color(0xFFF5D8A8),
          const Color(0xFFF0C98A),
          Icons.directions_run_outlined
        ),
      CheckinCategory.read => (
          const Color(0xFFD8E0D0),
          const Color(0xFFB8C8A8),
          Icons.menu_book_outlined
        ),
      CheckinCategory.travel => (
          const Color(0xFFC8DCE8),
          const Color(0xFFA8C5DA),
          Icons.flight_takeoff_outlined
        ),
      CheckinCategory.social => (
          const Color(0xFFF0D0CC),
          const Color(0xFFE8B5B0),
          Icons.groups_outlined
        ),
      CheckinCategory.pet => (
          const Color(0xFFF0E4CC),
          const Color(0xFFE8D4A8),
          Icons.pets_outlined
        ),
      _ => (
          const Color(0xFFE4DCF0),
          const Color(0xFFB8A6D9),
          Icons.auto_awesome_outlined
        ),
    };
    return Container(
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 44, color: Colors.white.withValues(alpha: 0.9)),
    );
  }
}

/// 多图宫格。
class _ImageGrid extends StatelessWidget {
  final List<String> urls;
  const _ImageGrid({required this.urls});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            urls[i],
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
    );
  }
}

/// 单图全宽完整显示（最大高度 360，不裁切）。
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

/// 胶囊互动钮（原型 act-btn：描边胶囊；选中暖沙底 + 琥珀描边）。
class _ActPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ActPill({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.sand : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? AppTheme.primaryDark : AppTheme.textSub),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppTheme.primaryDark : AppTheme.textSub,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 留言预览行：小头像 + 昵称 + 一句话（作者指定的末尾带图钉）。
class _PreviewLine extends StatelessWidget {
  final CommentVO comment;
  const _PreviewLine({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Avatar(url: comment.avatarUrl, nickname: comment.nickname, size: 20),
        const SizedBox(width: 7),
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
        if (comment.isFeatured) ...[
          const SizedBox(width: 4),
          const Icon(Icons.push_pin_outlined,
              size: 12, color: AppTheme.primary),
        ],
      ],
    );
  }
}
