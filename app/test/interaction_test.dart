import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:shinepick/core/theme/app_theme.dart';
import 'package:shinepick/shared/models/checkin.dart';
import 'package:shinepick/shared/widgets/feed_card.dart';

/// S5-04/S5-05：互动按钮三态、留言模型、乐观更新回滚。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('shinepick_s5');
    Hive.init(tmp.path);
    await Hive.openBox('feed_cache');
    await Hive.openBox('draft');
  });

  group('Checkin 互动状态', () {
    test('hasReaction 判断与 copyWith 不可变更新', () {
      const c = Checkin(
        id: 1,
        userId: 2,
        category: 1,
        content: 'x',
        checkinDate: '2026-10-30',
        myReactions: [1, 3],
      );
      expect(c.hasReaction(1), isTrue);
      expect(c.hasReaction(2), isFalse);
      expect(c.hasReaction(3), isTrue);

      final off = c.copyWith(myReactions: [3]);
      expect(off.hasReaction(1), isFalse);
      expect(c.hasReaction(1), isTrue, reason: '原对象不变（不可变更新）');
    });

    test('fromJson 解析 my_reactions（缺省为空）', () {
      final withRe = Checkin.fromJson({
        'id': 5,
        'user_id': 9,
        'category': 2,
        'content': 'read a book',
        'checkin_date': '2026-10-30',
        'my_reactions': [1, 2],
      });
      expect(withRe.myReactions, [1, 2]);
      final without = Checkin.fromJson({
        'id': 6,
        'user_id': 9,
        'category': 2,
        'content': 'x',
        'checkin_date': '2026-10-30',
      });
      expect(without.myReactions, isEmpty);
    });
  });

  group('CommentVO', () {
    test('解析与相对时间', () {
      final c = CommentVO.fromJson({
        'id': 3,
        'checkin_id': 10,
        'user_id': 12,
        'nickname': 'pig',
        'avatar_url': 'http://x/a.png',
        'content': '江边跑步真的舒服',
        'created_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
      });
      expect(c.nickname, 'pig');
      expect(c.content, '江边跑步真的舒服');
      expect(c.timeLabel, '5 分钟前');
    });
  });

  group('FeedCard 互动按钮三态', () {
    testWidgets('已选中态渲染 + 回调携带动作名', (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            children: [
              FeedCard(
                checkin: const Checkin(
                  id: 1,
                  userId: 2,
                  category: 1,
                  content: '今天跑了 3 公里',
                  checkinDate: '2026-10-30',
                  myReactions: [1, 3],
                ),
                onAction: actions.add,
              ),
            ],
          ),
        ),
      ));
      expect(find.text('点亮'), findsOneWidget);
      expect(find.text('留言'), findsOneWidget);
      await tester.tap(find.text('拥抱'));
      expect(actions, ['hug']);
      await tester.tap(find.text('留言'));
      expect(actions, ['hug', 'comment']);
    });
  });

  group('FeedCard 留言预览', () {
    testWidgets('展示预览留言（含作者指定标记），不显示条数', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            children: const [
              FeedCard(
                checkin: Checkin(
                  id: 10,
                  userId: 2,
                  category: 1,
                  content: '今天跑了 3 公里',
                  checkinDate: '2026-10-30',
                  previewComments: [
                    CommentVO(
                      id: 4,
                      checkinId: 10,
                      userId: 14,
                      nickname: '小杨',
                      avatarUrl: '',
                      content: '江边跑步真的舒服，我明天也去',
                      isFeatured: true,
                    ),
                    CommentVO(
                      id: 7,
                      checkinId: 10,
                      userId: 2,
                      nickname: 'pig',
                      avatarUrl: '',
                      content: '可以一起来玩',
                    ),
                  ],
                ),
                nickname: 'pig',
              ),
            ],
          ),
        ),
      ));
      expect(find.text('江边跑步真的舒服，我明天也去'), findsOneWidget);
      expect(find.text('可以一起来玩'), findsOneWidget);
      expect(find.text('小杨'), findsOneWidget);
      // 作者指定的图钉态 + 普通留言态
      expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsWidgets);
    });

    testWidgets('无预览留言时不渲染留言块', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ListView(
            children: const [
              FeedCard(
                checkin: Checkin(
                  id: 11,
                  userId: 2,
                  category: 1,
                  content: '没有留言的打卡',
                  checkinDate: '2026-10-30',
                ),
                nickname: 'pig',
              ),
            ],
          ),
        ),
      ));
      expect(find.byIcon(Icons.push_pin_outlined), findsNothing);
    });
  });

  group('Checkin 时间标签', () {
    testWidgets('今天显示时刻，昨天带「昨天」，更早带日期', (tester) async {
      final now = DateTime.now();
      Future<void> pumpAt(DateTime t) async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ListView(
              children: [
                FeedCard(
                  checkin: Checkin(
                    id: 1,
                    userId: 2,
                    category: 1,
                    content: '内容',
                    checkinDate: '2026-10-30',
                    createdAt: t,
                  ),
                  nickname: 'pig',
                ),
              ],
            ),
          ),
        ));
      }

      final today = DateTime(now.year, now.month, now.day);
      await pumpAt(DateTime(today.year, today.month, today.day, 9, 5));
      expect(find.textContaining('09:05'), findsOneWidget);
      expect(find.textContaining('昨天'), findsNothing);

      final y = today.subtract(const Duration(days: 1));
      await pumpAt(DateTime(y.year, y.month, y.day, 21, 30));
      expect(find.textContaining('昨天 21:30'), findsOneWidget);

      final old = today.subtract(const Duration(days: 30));
      await pumpAt(DateTime(old.year, old.month, old.day, 8, 0));
      final mmdd =
          '${old.month.toString().padLeft(2, '0')}-${old.day.toString().padLeft(2, '0')}';
      expect(find.textContaining(mmdd), findsOneWidget);
    });
  });
}
