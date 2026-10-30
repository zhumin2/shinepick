import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'package:shinepick/core/router/app_router.dart';
import 'package:shinepick/features/auth/auth_controller.dart';
import 'package:shinepick/features/checkin/checkin_controller.dart';
import 'package:shinepick/features/garden/garden_controller.dart';
import 'package:shinepick/features/social/social_controller.dart';
import 'package:shinepick/shared/models/user.dart';
import 'package:shinepick/shared/storage/token_store.dart';

/// 路由随登录态跳转（S6 壳导航版）：
/// 已登录 → 底部导航壳（今日/发现/我的）；退出登录 → 登录页。
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
    // 预开盒子：openBox 在已打开时走快速路径（无 IO）
    await Hive.openBox('feed_cache');
    await Hive.openBox('draft');
    await Hive.openBox('settings');
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

  Widget app(AuthController auth) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: auth),
          ChangeNotifierProvider.value(value: CheckinController(auth)),
          ChangeNotifierProvider.value(value: SocialController(auth)),
          ChangeNotifierProvider.value(value: GardenController(auth)),
        ],
        child: MaterialApp.router(
          routerConfig: AppRouter.createRouter(auth),
        ),
      );

  testWidgets('已登录进壳页（今日），切发现/我的 Tab，退出后回登录页', (tester) async {
    // 大视口：我的页全部内容可见，免去滚动（滚动后点击会被路由过渡层拦截）
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final auth = AuthController(_NoWriteStore());
    await auth.restore();
    expect(auth.status, AuthStatus.authenticated, reason: '预置后应为已登录态');

    await tester.pumpWidget(app(auth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 今日 Tab：问候语 + 底部导航
    expect(find.textContaining('pig'), findsWidgets, reason: '问候语含昵称');
    expect(find.text('发现'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    // 切到发现 Tab
    await tester.tap(find.text('发现'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('这个品类还没有内容，去发第一条吧'),
        findsOneWidget, reason: '发现页空态');

    // 切到我的 Tab → 进设置 → 退出登录
    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('设置'), findsOneWidget, reason: '我的页有设置入口');

    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('夜间免打扰'), findsOneWidget, reason: '进入设置页');

    // 回归（S6）：push 进入的子页可返回（go() 平级替换导致无页可 pop 的老坑）
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('打卡次数'), findsOneWidget, reason: '返回应回到我的页');

    // 重新进设置页执行退出
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('退出登录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(TextButton, '退出'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(auth.status, AuthStatus.unauthenticated, reason: '退出后状态为未登录');
    expect(find.text('登录 / 注册'), findsOneWidget, reason: '应回到登录页');
  });
}
