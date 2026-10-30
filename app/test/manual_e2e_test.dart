import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:shinepick/features/auth/auth_controller.dart';
import 'package:shinepick/features/checkin/checkin_controller.dart';
import 'package:shinepick/shared/storage/token_store.dart';

/// 手动诊断用：用真实 ApiClient 代码路径请求本地服务端
/// （不初始化 widget binding，避免 flutter_test 把 HTTP 拦成 400）。
///
/// 运行：
///   flutter test test/manual_e2e_test.dart \
///     --dart-define=ACCESS_TOKEN=<token> \
///     --dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1
///
/// 未传 ACCESS_TOKEN 时自动跳过，不影响常规 `flutter test` 全量运行。
void main() {
  const token = String.fromEnvironment('ACCESS_TOKEN');

  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('shinepick_e2e_manual');
    Hive.init(tmp.path);
  });

  test('真实服务端：读留言 + 发留言', () async {
    final store = TokenStore();
    await store.init();
    await store.saveTokens(token, 'rt_placeholder');

    final auth = AuthController(store);
    final ctrl = CheckinController(auth);

    final comments = await ctrl.loadComments(11);
    // ignore: avoid_print
    print('loadComments ok, count=${comments.length}');

    final c = await ctrl.addComment(11, 'dart client e2e');
    // ignore: avoid_print
    print('addComment ok, id=${c.id} nickname=${c.nickname}');
  }, skip: token.isEmpty ? '需 --dart-define=ACCESS_TOKEN 才运行' : null);
}
