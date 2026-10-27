import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';

/// 首页占位（S2 实现打卡流）。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('拾光'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.textSub),
            tooltip: '退出登录',
            onPressed: () => auth.logout(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  color: AppTheme.primary, size: 40),
            ),
            const SizedBox(height: 20),
            const Text(
              '今天，拾点什么好？',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '打卡流将在 S2 上线，先让账号体系跑起来。',
              style: TextStyle(fontSize: 14, color: AppTheme.textSub),
            ),
            const SizedBox(height: 16),
            Text(
              '你好，${auth.user?.nickname ?? '拾光用户'}',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSub),
            ),
          ],
        ),
      ),
    );
  }
}
