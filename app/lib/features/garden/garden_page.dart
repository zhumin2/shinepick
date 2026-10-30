import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../auth/auth_controller.dart';
import 'garden_controller.dart';
import 'tree_painter.dart';

/// 拾光树页（S7-03/04/05）：树 + 光点呼吸 + 徽章横滑 + 年进度。
class GardenPage extends StatefulWidget {
  const GardenPage({super.key});

  @override
  State<GardenPage> createState() => _GardenPageState();
}

class _GardenPageState extends State<GardenPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    final c = context.read<GardenController>();
    Future.microtask(c.load);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final garden = context.watch<GardenController>();
    final nickname = context.watch<AuthController>().user?.nickname ?? '';
    final tree = garden.tree;

    return Scaffold(
      appBar: AppBar(title: const Text('拾光树')),
      body: garden.loading && tree == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : RefreshIndicator(
              color: AppTheme.primary,
              onRefresh: () => context.read<GardenController>().load(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Center(
                    child: Text(
                      tree == null
                          ? ''
                          : '${treeStageName(tree.level)} · $nickname 的拾光树',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textMain),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: tree == null
                        ? const SizedBox()
                        : Text(
                            '${seasonName(tree.season)}季 · 已拾起 ${tree.points} 颗光点 · 连续 ${tree.streakDays} 天',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSub),
                          ),
                  ),
                  const SizedBox(height: 8),
                  // 树
                  SizedBox(
                    height: 320,
                    child: AnimatedBuilder(
                      animation: _breath,
                      builder: (_, __) => CustomPaint(
                        painter: TreePainter(
                          level: tree?.level ?? 1,
                          season: tree?.season ?? 1,
                          lightPoints: tree?.lightPoints ?? const [],
                          breath: _breath.value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 年进度（S7-05）
                  if (tree != null) _YearProgress(tree: tree),
                  const SizedBox(height: 20),
                  // 徽章（S7-04：横滑，未得置灰）
                  Row(
                    children: [
                      const Text('徽章',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textMain)),
                      const SizedBox(width: 8),
                      Text('已点亮 ${garden.ownedCount}/${garden.badges.length}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSub)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 108,
                    child: garden.badges.isEmpty
                        ? const Center(
                            child: Text('还没有徽章，打卡就能点亮第一枚',
                                style: TextStyle(
                                    fontSize: 12, color: AppTheme.textSub)))
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: garden.badges.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (_, i) =>
                                _BadgeCard(badge: garden.badges[i]),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// 年进度条：year_count / year_target。
class _YearProgress extends StatelessWidget {
  final TreeVO tree;
  const _YearProgress({required this.tree});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('今年的拾光',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain)),
              Text('${tree.yearCount} / ${tree.yearTarget}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSub)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: tree.yearProgress,
              minHeight: 8,
              backgroundColor: AppTheme.divider,
              color: AppTheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 徽章卡：已得亮色，未得置灰。
class _BadgeCard extends StatelessWidget {
  final BadgeVO badge;
  const _BadgeCard({required this.badge});

  IconData get _icon {
    switch (badge.icon) {
      case 'wb_sunny':
        return Icons.wb_sunny_outlined;
      case 'local_florist':
        return Icons.local_florist_outlined;
      case 'eco':
        return Icons.eco_outlined;
      case 'forest':
        return Icons.forest_outlined;
      case 'auto_awesome':
        return Icons.auto_awesome_outlined;
      case 'directions_run':
        return Icons.directions_run_outlined;
      case 'menu_book':
        return Icons.menu_book_outlined;
      case 'flight_takeoff':
        return Icons.flight_takeoff_outlined;
      default:
        return Icons.emoji_events_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final owned = badge.owned;
    final color = owned ? AppTheme.primary : AppTheme.textSub;
    return Container(
      width: 96,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: owned ? AppTheme.primary.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: owned
              ? AppTheme.primary.withValues(alpha: 0.4)
              : AppTheme.divider,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: owned
                  ? AppTheme.primary.withValues(alpha: 0.18)
                  : AppTheme.bg,
            ),
            child: owned
                ? Icon(_icon, size: 20, color: color)
                : const Icon(Icons.lock_outline, size: 16, color: AppTheme.textSub),
          ),
          const SizedBox(height: 6),
          Text(badge.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: owned ? AppTheme.textMain : AppTheme.textSub)),
          Text(badge.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSub)),
        ],
      ),
    );
  }
}
