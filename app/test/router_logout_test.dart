import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'package:shinepick/core/router/app_router.dart';
import 'package:shinepick/features/auth/auth_controller.dart';
import 'package:shinepick/shared/models/user.dart';
import 'package:shinepick/shared/storage/token_store.dart';

/// 路由随登录态跳转：退出登录后应回到登录页（回归：refreshListenable）。
/// 注：testWidgets 是 fake-async 环境，Hive 文件写不会完成——
/// 种子数据放 setUpAll（普通异步区），测试体内覆写 clear() 跳过文件删除。
class _NoWriteStore extends TokenStore {
  @override
  Future<void> clear() async {}
}

void main() {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('shinepick_router');
    Hive.init(tmp.path);
    final seed = TokenStore();
    await seed.init();
    await AuthBox.save(
      accessToken: 'at_test',
      refreshToken: 'rt_test',
      user: const User(
        id: 2,
        nickname: 'pig',
        avatarUrl: '',
        phoneMasked: '139****0001',
      ),
    );
  });

  testWidgets('已登录启动进首页，点退出后回到登录页', (tester) async {
    final auth = AuthController(_NoWriteStore());
    await auth.restore();
    expect(auth.status, AuthStatus.authenticated, reason: '预置后应为已登录态');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp.router(
          routerConfig: AppRouter.createRouter(auth),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('你好，pig'), findsOneWidget, reason: '已登录应进入首页');

    // 点 AppBar 的退出登录按钮
    await tester.tap(find.byTooltip('退出登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(auth.status, AuthStatus.unauthenticated, reason: '退出后状态应为未登录');
    expect(find.text('登录 / 注册'), findsOneWidget, reason: '应回到登录页');
    expect(find.text('你好，pig'), findsNothing, reason: '首页应已卸载');
  });
}
