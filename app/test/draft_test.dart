import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:shinepick/features/auth/auth_controller.dart';
import 'package:shinepick/features/checkin/checkin_controller.dart';
import 'package:shinepick/shared/storage/token_store.dart';

/// S4-06：打卡草稿保存/恢复/清除（真实 IO，普通 test 环境）。
void main() {
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('shinepick_draft');
    Hive.init(tmp.path);
  });

  test('草稿保存后可读出，清除后为空', () async {
    final store = TokenStore();
    await store.init();
    final c = CheckinController(AuthController(store));

    expect(await c.readDraft(), '');

    await c.saveDraft('今天跑了 3 公里，还没选可见范围');
    expect(await c.readDraft(), '今天跑了 3 公里，还没选可见范围');

    await c.saveDraft('改一下：今天读了 20 页');
    expect(await c.readDraft(), '改一下：今天读了 20 页', reason: '重复保存覆盖旧草稿');

    await c.clearDraft();
    expect(await c.readDraft(), '');
  });
}
