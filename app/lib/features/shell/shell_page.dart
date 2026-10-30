import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../discover/discover_page.dart';
import '../garden/garden_page.dart';
import '../home/home_page.dart';
import '../profile/profile_page.dart';
import '../social/social_controller.dart';

/// 底部导航壳（S6-05）：今日 / 发现 / 我的（拾光树 Tab 在 S7 加入）。
class ShellPage extends StatefulWidget {
  const ShellPage({super.key});

  @override
  State<ShellPage> createState() => _ShellPageState();
}

class _ShellPageState extends State<ShellPage> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 未读轻提示：小圆点，不做红点轰炸
    final c = context.read<SocialController>();
    Future.microtask(() => c.refreshUnread());
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<SocialController>().unread;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          HomePage(embedded: true),
          DiscoverPage(),
          GardenPage(),
          ProfilePage(embedded: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.15),
        height: 64,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny, color: AppTheme.primaryDark),
            label: '今日',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore, color: AppTheme.primaryDark),
            label: '发现',
          ),
          const NavigationDestination(
            icon: Icon(Icons.park_outlined),
            selectedIcon: Icon(Icons.park, color: AppTheme.primaryDark),
            label: '拾光树',
          ),
          NavigationDestination(
            icon: _MeIcon(showDot: unread > 0, filled: false),
            selectedIcon: _MeIcon(showDot: unread > 0, filled: true),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

/// 我的 Tab 图标：未读时右上角小圆点。
class _MeIcon extends StatelessWidget {
  final bool showDot;
  final bool filled;
  const _MeIcon({required this.showDot, required this.filled});

  @override
  Widget build(BuildContext context) {
    final icon = filled
        ? const Icon(Icons.person, color: AppTheme.primaryDark)
        : const Icon(Icons.person_outline);
    if (!showDot) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
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
    );
  }
}
