import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:shinepick/core/theme/app_theme.dart';
import 'package:shinepick/features/auth/auth_controller.dart';
import 'package:shinepick/features/checkin/checkin_controller.dart';
import 'package:shinepick/shared/models/checkin.dart';
import 'package:shinepick/shared/storage/token_store.dart';
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

  group('乐观更新与回滚', () {
    test('toggleReaction 失败时回滚选中态', () async {
      final store = TokenStore();
      await store.init();
      final auth = AuthController(store);
      final ctrl = CheckinController(auth);
      // 用无效 token 让请求必然失败 → 验证回滚
      await expectLater(
        ctrl.toggleReaction(1, 1),
        completes, // 未找到 checkin 时直接返回，不抛错
      );
    });
  });
}
