import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:shinepick/core/error/app_error.dart';
import 'package:shinepick/core/network/api_client.dart';

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('shinepick_test');
    Hive.init(dir.path);
  });

  test('业务错误码映射为 AppError', () {
    expect(AppError.smsInvalid().code, 3001);
    expect(AppError.tooFrequent().message, '操作过于频繁，请稍后再试');
    expect(AppError.unauthorized().code, 2001);
  });

  test('ApiResponse 解包成功', () {
    final resp = ApiResponse<int>.fromJson(
      {'code': 0, 'message': 'ok', 'data': 42},
      (d) => (d as num).toInt(),
    );
    expect(resp.ok, isTrue);
    expect(resp.data, 42);
  });

  test('ApiResponse 解包业务失败', () {
    final resp = ApiResponse<int>.fromJson(
      {'code': 4001, 'message': '操作过于频繁，请稍后再试', 'data': null},
      null,
    );
    expect(resp.ok, isFalse);
    expect(resp.code, 4001);
  });
}
