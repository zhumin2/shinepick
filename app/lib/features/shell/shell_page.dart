import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../checkin/checkin_controller.dart';
import '../checkin/checkin_sheet.dart';
import '../discover/discover_page.dart';
import '../garden/garden_controller.dart';
import '../garden/garden_page.dart';
import '../home/home_page.dart';
import '../profile/profile_page.dart';
import '../social/social_controller.dart';

/// 底部导航壳（原型 tabbar）：今日 / 发现 / [中央打卡钮] / 拾光树 / 我的。
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    final social = context.read<SocialController>();
    Future.microtask(() => social.refreshUnread());
  }

  /// 中央打卡钮：全局可发布；成功后刷新数据并展示仪式感动画。
  Future<void> _openCheckin() async {
    // 先取控制器（避免跨 async 使用 BuildContext）
    final checkin = context.read<CheckinController>();
    final garden = context.read<GardenController>();
    final social = context.read<SocialController>();
    final published = await CheckinSheet.show(context);
    if (!published || !mounted) return;
    await checkin.load();
    await checkin.loadFeed();
    await garden.load();
    await social.refreshUnread();
    if (!mounted) return;
    setState(() => _celebrating = true);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<SocialController>().unread;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: const [
              HomePage(embedded: true),
              DiscoverPage(),
              GardenPage(),
              ProfilePage(embedded: true),
            ],
          ),
          if (_celebrating) const SuccessOverlay(),
        ],
      ),
      // 中央凸起打卡钮（原型 tab-btn：琥珀圆 + 白描边 + 上浮）
      floatingActionButton: FloatingActionButton(
        onPressed: _openCheckin,
        tooltip: '拾起今天',
        backgroundColor: AppTheme.primary,
        elevation: 8,
        shape: const CircleBorder(
          side: BorderSide(color: Colors.white, width: 4),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
      floatingActionButtonLocation: const _CenterDockedLocation(),
      // 自定义 TabBar：4 项 + 中缝留位（原型 84px 高）
      bottomNavigationBar: _ShellTabBar(
        index: _index,
        unread: unread,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

/// 自定义底栏（原型：白底 84px，选中琥珀深色，中缝 56px 给打卡钮）。
class _ShellTabBar extends StatelessWidget {
  final int index;
  final int unread;
  final ValueChanged<int> onTap;

  const _ShellTabBar({
    required this.index,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(
        children: [
          _tab(0, Icons.home_outlined, Icons.home, '今日'),
          _tab(1, Icons.explore_outlined, Icons.explore, '发现'),
          const SizedBox(width: 56), // 中缝给中央打卡钮
          _tab(2, Icons.park_outlined, Icons.park, '拾光树'),
          _tab(3, Icons.person_outlined, Icons.person, '我的',
              showDot: unread > 0),
        ],
      ),
    );
  }

  Widget _tab(int i, IconData outline, IconData filled, String label,
      {bool showDot = false}) {
    final selected = index == i;
    final color = selected ? AppTheme.primaryDark : AppTheme.textFaint;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? filled : outline, size: 22, color: color),
                if (showDot)
                  Positioned(
                    right: -3,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

/// FAB 居中悬浮于底栏上（原型 bottom:56px + 上浮 28px）。
class _CenterDockedLocation extends FloatingActionButtonLocation {
  const _CenterDockedLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final w = scaffoldGeometry.scaffoldSize.width;
    final fabW = scaffoldGeometry.floatingActionButtonSize.width;
    const bottomBarH = 84.0;
    return Offset(
      (w - fabW) / 2,
      scaffoldGeometry.scaffoldSize.height - bottomBarH - fabW / 2 - 4.0,
    );
  }
}


/// 发布成功全屏仪式感（原型 success：遮罩 + 大光点 dropIn + 文案）。
class SuccessOverlay extends StatefulWidget {
  const SuccessOverlay({super.key});

  @override
  State<SuccessOverlay> createState() => _SuccessOverlayState();
}

class _SuccessOverlayState extends State<SuccessOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drop = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0, 0.44, curve: Curves.easeOutCubic),
    );
    final fadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.78, 1, curve: Curves.easeIn),
      ),
    );
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        if (_ctrl.isCompleted) return const SizedBox.shrink();
        final t = drop.value;
        final y = -200 * (1 - t);
        final scale = t < 0.6
            ? 0.5 + 0.6 * (t / 0.6)
            : 1.1 - 0.1 * ((t - 0.6) / 0.4);
        return Opacity(
          opacity: fadeOut.value,
          child: Container(
            color: AppTheme.bg.withValues(alpha: 0.96),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(0, y),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primary,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.6),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('今天，拾起了 ✓',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain)),
                const SizedBox(height: 6),
                const Text('每一颗光点都会落在你的拾光树上',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
              ],
            ),
          ),
        );
      },
    );
  }
}
