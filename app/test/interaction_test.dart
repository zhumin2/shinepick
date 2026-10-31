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
      // 新规则：今天 → HH:mm（不再用相对时间）
      final t = DateTime.now().subtract(const Duration(minutes: 5));
      final hm =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      expect(c.timeLabel, hm);
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

  group('留言时间标签（friendlyTime）', () {
    test('今天带时刻，昨天带「昨天」，更早带日期', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      CommentVO at(DateTime t) => CommentVO.fromJson({
            'id': 1,
            'checkin_id': 1,
            'user_id': 2,
            'nickname': 'pig',
            'avatar_url': '',
            'content': 'x',
            'created_at': t.toIso8601String(),
          });

      // 今天 09:05 → 09:05
      final c1 = at(DateTime(today.year, today.month, today.day, 9, 5));
      expect(c1.timeLabel, '09:05');

      // 昨天 21:30 → 昨天 21:30
      final y = today.subtract(const Duration(days: 1));
      final c2 = at(DateTime(y.year, y.month, y.day, 21, 30));
      expect(c2.timeLabel, '昨天 21:30');

      // 30 天前 → MM-DD HH:mm
      final old = today.subtract(const Duration(days: 30));
      final c3 = at(DateTime(old.year, old.month, old.day, 8, 0));
      final mmdd =
          '${old.month.toString().padLeft(2, '0')}-${old.day.toString().padLeft(2, '0')}';
      expect(c3.timeLabel, '$mmdd 08:00');
    });

    test('createdAt 缺失时空串（列表回退不显示时间）', () {
      final c = CommentVO.fromJson({
        'id': 2, 'checkin_id': 1, 'user_id': 2,
        'nickname': 'pig', 'avatar_url': '', 'content': 'x',
      });
      expect(c.timeLabel, '');
    });
  });

  group('S7 拾光树模型', () {
    test('TreeVO 解析 + 年进度 clamp', () {
      final t = TreeVO.fromJson({
        'level': 3,
        'points': 8,
        'season': 3,
        'year_count': 8,
        'year_target': 300,
        'streak_days': 1,
        'total': 8,
        'light_points': [
          {'date': '2026-10-31', 'category': 1},
          {'date': '2026-10-30', 'category': 2},
        ],
      });
      expect(t.level, 3);
      expect(t.season, 3);
      expect(t.lightPoints.length, 2);
      expect(t.lightPoints[0].category, 1);
      expect(t.yearProgress, closeTo(8 / 300, 0.0001));
      // 目标为 0 时不除零
      final z = TreeVO.fromJson({
        'level': 1, 'points': 0, 'season': 1,
        'year_count': 0, 'year_target': 0,
        'streak_days': 0, 'total': 0, 'light_points': [],
      });
      expect(z.yearProgress, 0);
    });

    test('BadgeVO 已得/未得解析', () {
      final owned = BadgeVO.fromJson({
        'code': 'first_light', 'name': '第一颗光点', 'icon': 'wb_sunny',
        'description': '完成第一次打卡', 'owned': true,
        'earned_at': '2026-10-31T10:00:00',
      });
      expect(owned.owned, isTrue);
      expect(owned.earnedAt, isNotNull);
      final locked = BadgeVO.fromJson({
        'code': 'streak_7', 'name': '七日不辍', 'icon': 'eco',
        'description': '连续打卡 7 天', 'owned': false,
      });
      expect(locked.owned, isFalse);
      expect(locked.earnedAt, isNull);
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
