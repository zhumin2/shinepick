import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/error/app_error.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/checkin.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/feed_card.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';
import '../checkin/checkin_controller.dart';
import '../comment/comment_sheet.dart';

/// 今日页：问候 + 今日卡（N/5 + 品类勾选）+ 同品类横滑 + 今日微光 + 我的拾光。
/// 打卡入口在底部导航中央凸起按钮（ShellPage），发布成功由壳层展示仪式感动画。
class HomePage extends StatefulWidget {
  final bool embedded;
  const HomePage({super.key, this.embedded = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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

  /// 互动与留言入口（S5-04/S5-05）。
  Future<void> _onAction(
    String action, {
    required int checkinId,
    required int ownerId,
  }) async {
    final ctrl = context.read<CheckinController>();
    if (action == 'comment') {
      await CommentSheet.show(
        context,
        checkinId: checkinId,
        checkinOwnerId: ownerId,
      );
      return;
    }
    final type = switch (action) {
      'light' => 1,
      'hug' => 2,
      'companion' => 3,
      _ => 0,
    };
    if (type == 0) return;
    try {
      await ctrl.toggleReaction(checkinId, type);
      if (!mounted) return;
      if (type == 3) Toast.show(context, '已加入同路，你们可以互相看见彼此的拾光');
    } on AppError catch (e) {
      if (mounted) Toast.show(context, e.message);
    } catch (_) {
      if (mounted) Toast.show(context, '操作失败，请稍后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final checkin = context.watch<CheckinController>();
    final nickname = auth.user?.nickname ?? '拾光用户';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('拾光'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppTheme.textSub),
            tooltip: '通知',
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: RefreshIndicator(
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
            const Text('不必是大事，跑 3 公里也算。',
                style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
            const SizedBox(height: 16),
            _TodayCard(
              todayCount: checkin.todayCount,
              doneCategories: checkin.todayCategories,
            ),
            const SizedBox(height: 16),
            if (checkin.feedOffline)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          style:
                              TextStyle(fontSize: 12, color: AppTheme.textSub)),
                    ),
                  ],
                ),
              ),
            // 同品类横滑：今天也在打卡的陌生人（原型 companion 卡）
            if (checkin.doing.isNotEmpty) ...[
              const _SectionTitle('今天和你同路的人'),
              const SizedBox(height: 10),
              SizedBox(
                height: 138,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: checkin.doing.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => _DoingCard(item: checkin.doing[i]),
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
                  avatarUrl: item.user.avatarUrl,
                  onAction: (a) => _onAction(
                    a,
                    checkinId: item.checkin.id,
                    ownerId: item.user.id,
                  ),
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
                    child:
                        CircularProgressIndicator(color: AppTheme.primary)),
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
                FeedCard(
                  checkin: c,
                  nickname: nickname,
                  avatarUrl: auth.user?.avatarUrl,
                  onAction: (a) =>
                      _onAction(a, checkinId: c.id, ownerId: c.userId),
                ),
          ],
        ),
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

/// 今日卡（原型 checkin-card）：大数字 N/想做的5件事 + 品类勾选行。
class _TodayCard extends StatelessWidget {
  final int todayCount;
  final Set<int> doneCategories;
  const _TodayCard({required this.todayCount, required this.doneCategories});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.sand, AppTheme.bg],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFF5D8A8).withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('今日已拾起',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      color: AppTheme.primaryDark)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$todayCount',
                      style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: AppTheme.textMain)),
                  const SizedBox(width: 4),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('/ 想做的 5 件事',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textSub)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_categoryLine(),
                  style:
                      const TextStyle(fontSize: 13, color: AppTheme.textSub)),
            ],
          ),
        ],
      ),
    );
  }

  String _categoryLine() {
    final names = ['运动', '阅读', '旅行', '社交', '宠物'];
    final line = [
      for (var i = 0; i < names.length; i++)
        '${names[i]}${doneCategories.contains(i + 1) ? ' ✓' : ''}',
    ].join(' · ');
    // 自定义=兜底门类「其他」
    final other = doneCategories.contains(CheckinCategory.custom.code);
    return other ? '\$line · 其他 ✓' : line;
  }
}

/// 同品类横滑卡（原型 companion：色块头像 + 名 + 在做什么 + 连续天数）。
class _DoingCard extends StatelessWidget {
  final FeedItem item;
  const _DoingCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(url: item.user.avatarUrl, nickname: item.user.nickname, size: 40),
          const SizedBox(height: 8),
          Text(item.user.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMain)),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              item.checkin.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11, height: 1.4, color: AppTheme.textSub),
            ),
          ),
          if (item.user.streakDays > 0)
            Text('连续第 ${item.user.streakDays} 天',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.primaryDark)),
        ],
      ),
    );
  }
}
