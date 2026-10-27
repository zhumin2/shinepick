import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:shinepick/shared/models/user.dart';
import 'package:shinepick/shared/storage/token_store.dart';

void main() {
  setUpAll(() async {
    await Hive.initFlutter();
  });

  test('TokenStore 保存与读取', () async {
    final store = TokenStore();
    await store.init();

    await store.saveTokens('access-1', 'refresh-1');
    expect(await store.readAccessToken(), 'access-1');
    expect(await store.readRefreshToken(), 'refresh-1');

    await store.saveTokens('access-2', 'refresh-2');
    expect(await store.readAccessToken(), 'access-2');

    await store.clear();
    expect(await store.readAccessToken(), isNull);
  });

  test('User.fromJson 解析', () {
    final u = User.fromJson({
      'id': 1,
      'nickname': '拾光用户_1',
      'avatar_url': '',
      'phone_masked': '138****0000',
    });
    expect(u.id, 1);
    expect(u.nickname, '拾光用户_1');
    expect(u.phoneMasked, '138****0000');
  });
}
