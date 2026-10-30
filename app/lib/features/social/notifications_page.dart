import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/toast.dart';
import 'social_controller.dart';

/// 通知页（S6-04）：文案由服务端生成（含匿名聚合），点击全部已读。
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    final c = context.read<SocialController>();
    Future.microtask(() => c.loadNotifications());
  }

  Future<void> _markAll() async {
    try {
      await context.read<SocialController>().markAllRead();
      if (mounted) Toast.show(context, '已全部标记为读过');
    } catch (_) {
      if (mounted) Toast.show(context, '操作失败，请重试');
    }
  }

  IconData _icon(int type) {
    switch (type) {
      case 1:
        return Icons.light_mode_outlined;
      case 2:
        return Icons.favorite_outline;
      case 3:
        return Icons.spa_outlined;
      case 4:
        return Icons.chat_bubble_outline;
      default:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final social = context.watch<SocialController>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('通知'),
        actions: [
          TextButton(
            onPressed: social.items.isEmpty ? null : _markAll,
            child: const Text('全部已读', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
      body: social.loading && social.items.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : social.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 40,
                          color: AppTheme.textSub.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      const Text('还没有通知',
                          style:
                              TextStyle(fontSize: 14, color: AppTheme.textSub)),
                      const SizedBox(height: 4),
                      const Text('有人点亮你的拾光时会安静地出现在这里',
                          style:
                              TextStyle(fontSize: 12, color: AppTheme.textSub)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primary,
                  onRefresh: () =>
                      context.read<SocialController>().loadNotifications(),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: social.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final n = social.items[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: n.isRead
                              ? Colors.white
                              : AppTheme.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(_icon(n.type),
                                size: 20,
                                color: n.isRead
                                    ? AppTheme.textSub
                                    : AppTheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.copy,
                                      style: TextStyle(
                                          fontSize: 14,
                                          height: 1.5,
                                          color: AppTheme.textMain,
                                          fontWeight: n.isRead
                                              ? FontWeight.w400
                                              : FontWeight.w600)),
                                  const SizedBox(height: 3),
                                  Text(n.timeLabel,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSub)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
