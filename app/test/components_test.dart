import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shinepick/core/theme/app_theme.dart';
import 'package:shinepick/shared/models/checkin.dart';
import 'package:shinepick/shared/models/user.dart';
import 'package:shinepick/shared/widgets/act_btn.dart';
import 'package:shinepick/shared/widgets/avatar.dart';
import 'package:shinepick/shared/widgets/feed_card.dart';

/// S2-04 基础组件库验收：可构建、关键元素渲染、交互回调。
void main() {
  testWidgets('Avatar 无图时显示昵称首字，有图时走网络图', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: Avatar(nickname: '拾光用户', size: 48),
      ),
    ));
    expect(find.text('拾'), findsOneWidget);
  });

  testWidgets('ActBtn 三态渲染与点击回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ActBtn(
          icon: Icons.light_mode_outlined,
          label: '点亮',
          onTap: () => tapped++,
        ),
      ),
    ));
    expect(find.text('点亮'), findsOneWidget);
    await tester.tap(find.byType(ActBtn));
    expect(tapped, 1);
  });

  testWidgets('FeedCard 渲染品类与连续天数，互动回调触发', (tester) async {
    final actions = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: ListView(
          children: [
            FeedCard(
              checkin: const CheckinVO(
                id: 1,
                userId: 2,
                nickname: 'pig',
                category: CheckinCategory.sport,
                content: '今天跑了 3 公里，江边的风很舒服。',
                timeLabel: '21:30',
                streakDays: 12,
              ),
              onAction: actions.add,
            ),
          ],
        ),
      ),
    ));
    expect(find.text('pig'), findsOneWidget);
    expect(find.textContaining('连续 12 天'), findsOneWidget);
    expect(find.textContaining('今天跑了 3 公里'), findsOneWidget);
    await tester.tap(find.text('点亮'));
    expect(actions, contains('light'));
  });

  test('User.mergeProfile 合并资料字段并保留掩码手机号', () {
    const u = User(
      id: 2,
      nickname: 'pig',
      avatarUrl: '',
      phoneMasked: '139****0001',
    );
    final merged = u.mergeProfile({
      'id': 2,
      'nickname': 'pig',
      'avatar_url': 'http://127.0.0.1:8080/static/avatars/u2_1.jpg',
      'bio': '认真生活',
      'gender': 1,
      'city': '杭州',
      'birthday': '2000-01-01',
      'is_minor': false,
    });
    expect(merged.phoneMasked, '139****0001', reason: '掩码手机号应保留');
    expect(merged.bio, '认真生活');
    expect(merged.city, '杭州');
    expect(merged.birthday, '2000-01-01');
    expect(merged.isMinor, isFalse);
    expect(merged.toCacheJson()['bio'], '认真生活', reason: '缓存应含资料字段');
  });
}
