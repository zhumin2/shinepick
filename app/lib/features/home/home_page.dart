import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/feed_card.dart';
import '../auth/auth_controller.dart';
import '../checkin/checkin_controller.dart';
import '../checkin/checkin_sheet.dart';

/// 今日页（S4-03）：问候 + 今日卡 + 同品类横滑 + 今日微光 + 我的拾光。
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
    Future.microtask(() async {
      await c.load();
      await c.loadFeed();
    });
  }

  Future<void> _refreshAll() async {
    final c = context.read<CheckinController>();
    await c.load();
    await c.loadFeed();
  }

  Future<void> _openCheckinSheet() async {
    final published = await CheckinSheet.show(context);
    if (published && mounted) {
      await _refreshAll();
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
            onRefresh: _refreshAll,
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
                _TodayCard(todayCount: checkin.todayCount),
                const SizedBox(height: 16),
                if (checkin.feedOffline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.wifi_off, size: 15, color: AppTheme.textSub),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('网络未连接，展示最近的内容',
                              style: TextStyle(
                                  fontSize: 12, color: AppTheme.textSub)),
                        ),
                      ],
                    ),
                  ),
                // 同路人横滑：今天也在打卡的陌生人（S4-03）
                if (checkin.doing.isNotEmpty) ...[
                  const _SectionTitle('今天也在打卡的人'),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 132,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: checkin.doing.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (_, i) =>
                          _DoingCard(item: checkin.doing[i]),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                // 今日微光
                if (checkin.dailySelected.isNotEmpty) ...[
                  const _SectionTitle('今日微光'),
                  const SizedBox(height: 10),
                  for (final item in checkin.dailySelected)
                    FeedCard(
                      checkin: item.checkin,
                      nickname: item.user.nickname,
                      onAction: (_) {},
                    ),
                  const SizedBox(height: 8),
                ],
                // 我的拾光
                const _SectionTitle('我的拾光'),
                const SizedBox(height: 10),
                if (checkin.loading && checkin.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(color: AppTheme.primary)),
                  )
                else if (checkin.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('点下方的 +，拾起今天的第一束光',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
                  )
                else
                  for (final c in checkin.items)
                    FeedCard(checkin: c, nickname: nickname),
              ],
            ),
          ),
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

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMain));
  }
}

class _TodayCard extends StatelessWidget {
  final int todayCount;
  const _TodayCard({required this.todayCount});

  @override
  Widget build(BuildContext context) {
    return Container(
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
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wb_sunny_outlined, color: AppTheme.primary, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  todayCount > 0
                      ? '今天已拾起 $todayCount 束光'
                      : '今天你还没打卡，要拾起一点光阴吗？',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain),
                ),
                const SizedBox(height: 4),
                const Text('每打卡一次，你的拾光树就多一颗光点',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 同品类横滑卡（对齐原型："今天也在运动的 3 个陌生人"）。
class _DoingCard extends StatelessWidget {
  final FeedItem item;
  const _DoingCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final cat = item.checkin.categoryEnum ?? CheckinCategory.sport;
    return Container(
      width: 200,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: cat.color.withValues(alpha: 0.15),
                child: Text(
                  item.user.nickname.isEmpty
                      ? '光'
                      : item.user.nickname.characters.first,
                  style: TextStyle(
                      fontSize: 11,
                      color: cat.color,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.user.nickname,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cat.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(cat.label,
                    style: TextStyle(fontSize: 10, color: cat.color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              item.checkin.content,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, height: 1.5, color: AppTheme.textSub),
            ),
          ),
        ],
      ),
    );
  }
}

/// 发布成功后的光点落下动画（S4-04：800ms 落下 + 光晕呼吸）。
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
  late final Animation<double> _glow;

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
    // 光晕呼吸：落下过程中两轮脉冲
    _glow = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.4, end: 0.9), weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 0.9, end: 0.4), weight: 50),
    ]).animate(_ctrl);
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
                    color: AppTheme.primary
                        .withValues(alpha: 0.5 * _glow.value),
                    blurRadius: 24,
                    spreadRadius: 6 + 6 * _glow.value,
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
