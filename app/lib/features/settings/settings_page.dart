import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/toast.dart';
import '../auth/auth_controller.dart';

/// 设置页（S6-06）：夜间免打扰 + 情绪安全中心 + 退出登录。
/// 推送通道（极光）待接入前，免打扰先作用于本地提醒偏好。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _nightDnd = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      try {
        final box = await Hive.openBox('settings');
        if (!mounted) return;
        setState(() => _nightDnd = box.get('night_dnd', defaultValue: false) as bool);
      } catch (_) {}
    });
  }

  Future<void> _toggleNightDnd(bool v) async {
    setState(() => _nightDnd = v);
    try {
      final box = await Hive.openBox('settings');
      await box.put('night_dnd', v);
    } catch (_) {
      if (mounted) Toast.show(context, '保存失败');
    }
  }

  Future<void> _showSafetyCenter() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('情绪安全中心',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain)),
            ),
            SizedBox(height: 16),
            Text(
              '拾光的社区底线是「不伤人」：\n\n'
              '· 不制造身材与容貌焦虑——运动品类不打「瘦了 X 斤」类标签\n'
              '· 不卷阅读——没有读完本书的排行榜，只有今年读过的书\n'
              '· 讽刺、说教、优越感、拉踩类内容会被拦截；一次警告，二次封号\n'
              '· 留言与打卡同一标准，打卡作者可删除自己内容下的任意留言\n'
              '· 拉黑静默生效，对方不会收到通知\n'
              '· 举报 24 小时内处理\n'
              '· 23:00 - 7:00 不推送、不催促，好好睡觉\n\n'
              '如果某个内容让你不舒服，长按卡片可以举报或拉黑。',
              style: TextStyle(fontSize: 13, height: 1.8, color: AppTheme.textSub),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text('退出登录？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AuthController>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  value: _nightDnd,
                  onChanged: _toggleNightDnd,
                  activeThumbColor: AppTheme.primary,
                  title: const Text('夜间免打扰',
                      style: TextStyle(fontSize: 15, color: AppTheme.textMain)),
                  subtitle: const Text('23:00 - 7:00 不接收提醒',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSub)),
                ),
                const Divider(height: 1, indent: 16, color: AppTheme.divider),
                ListTile(
                  title: const Text('情绪安全中心',
                      style: TextStyle(fontSize: 15, color: AppTheme.textMain)),
                  trailing: const Icon(Icons.chevron_right,
                      size: 18, color: AppTheme.textSub),
                  onTap: _showSafetyCenter,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppTheme.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              title: const Text('退出登录',
                  style: TextStyle(fontSize: 15, color: Color(0xFFC25B4E))),
              trailing: const Icon(Icons.logout,
                  size: 18, color: Color(0xFFC25B4E)),
              onTap: _logout,
            ),
          ),
        ],
      ),
    );
  }
}
