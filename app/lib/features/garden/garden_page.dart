import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
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
                  // 页头（原型 garden-head：连续天数强调 + 副句）
                  Center(
                    child: tree == null
                        ? const SizedBox()
                        : Text('连续拾起 · ${tree.streakDays} 天',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                                color: AppTheme.primaryDark)),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text('我的拾光树',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textMain)),
                  ),
                  const SizedBox(height: 4),
                  const Center(
                    child: Text('每打一次卡，树就长大一点。',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSub)),
                  ),
                  const SizedBox(height: 8),
                  // 树画布（原型 garden-canvas：白卡 + 天空/地面分层）
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      height: 300,
                      child: Stack(
                        children: [
                          // 天空
                          const Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            height: 180,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFFDF6E8),
                                    AppTheme.bg,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 地面
                          const Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 105,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFE8E4D2),
                                    Color(0xFFD8D4C0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _breath,
                            builder: (_, __) => CustomPaint(
                              size: const Size(double.infinity, 300),
                              painter: TreePainter(
                                level: tree?.level ?? 1,
                                season: tree?.season ?? 1,
                                lightPoints: tree?.lightPoints ?? const [],
                                breath: _breath.value,
                              ),
                            ),
                          ),
                        ],
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
                      Text('${garden.ownedCount} / ${garden.badges.length}',
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

  int _daysLeft() {
    final now = DateTime.now();
    final end = DateTime(now.year + 1, 1, 1);
    return end.difference(now).inDays;
  }

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
              Text('${DateTime.now().year} 拾光册',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain)),
              Text('已收集 ${tree.points} 个光点',
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('年进度 ${(tree.yearProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSub)),
              Text('距年底还有 ${_daysLeft()} 天',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSub)),
            ],
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
