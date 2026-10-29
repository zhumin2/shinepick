import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/feed_card.dart';
import '../auth/auth_controller.dart';
import '../checkin/checkin_controller.dart';
import '../checkin/checkin_sheet.dart';

/// 今日页（S3-07）：问候语 + 今日已拾起卡 + 近期打卡列表 + 中央"+"打卡。
/// S4 接 Feed（同路人流/今日微光）与光点动画完整版。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    final c = context.read<CheckinController>();
    Future.microtask(c.load);
  }

  Future<void> _openCheckinSheet() async {
    final published = await CheckinSheet.show(context);
    if (published && mounted) {
      setState(() => _celebrating = true);
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _celebrating = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final checkin = context.watch<CheckinController>();
    final nickname = auth.user?.nickname ?? '拾光用户';

    return Scaffold(
      appBar: AppBar(
        title: const Text('拾光'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline, color: AppTheme.textSub),
            tooltip: '我的',
            onPressed: () => context.push('/profile'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.textSub),
            tooltip: '退出登录',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCheckinSheet,
        tooltip: '今日打卡',
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            color: AppTheme.primary,
            onRefresh: () => checkin.load(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text('${_greeting()}，$nickname',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMain)),
                const SizedBox(height: 4),
                const Text('拾起生活里的小光阴',
                    style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
                const SizedBox(height: 16),
                // 今日已拾起
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.14),
                        AppTheme.primary.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.wb_sunny_outlined,
                          color: AppTheme.primary, size: 34),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              checkin.todayCount > 0
                                  ? '今天已拾起 ${checkin.todayCount} 束光'
                                  : '今天你还没打卡，要拾起一点光阴吗？',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textMain),
                            ),
                            const SizedBox(height: 4),
                            const Text('每打卡一次，你的拾光树就多一颗光点',
                                style: TextStyle(
                                    fontSize: 12, color: AppTheme.textSub)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 近期打卡
                if (checkin.loading && checkin.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                        child: CircularProgressIndicator(color: AppTheme.primary)),
                  )
                else if (checkin.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 40,
                            color: AppTheme.textSub.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text('还没有打卡记录',
                            style: TextStyle(
                                fontSize: 14, color: AppTheme.textSub)),
                        const SizedBox(height: 4),
                        const Text('点下方的 +，拾起今天的第一束光',
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textSub)),
                      ],
                    ),
                  )
                else
                  for (final c in checkin.items)
                    FeedCard(checkin: c, nickname: nickname),
              ],
            ),
          ),
          // 光点落下动画（S4-04 完整版，S3 先做仪式感最小实现）
          if (_celebrating) const _LightDrop(),
        ],
      ),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了';
    if (h < 11) return '早上好';
    if (h < 14) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }
}

/// 发布成功后的光点落下动画（800ms，对齐原型 drop-in）。
class _LightDrop extends StatefulWidget {
  const _LightDrop();

  @override
  State<_LightDrop> createState() => _LightDropState();
}

class _LightDropState extends State<_LightDrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fall;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fall = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _fade = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.6, 1, curve: Curves.easeIn),
      ),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Positioned(
          left: size.width / 2 - 22,
          top: size.height * (0.25 + 0.3 * _fall.value),
          child: Opacity(
            opacity: _fade.value,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.9),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.5),
                    blurRadius: 24,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: const Icon(Icons.wb_sunny, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
