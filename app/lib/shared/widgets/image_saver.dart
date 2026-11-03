import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'image_saver_io.dart'
    if (dart.library.js_interop) 'image_saver_web.dart' as impl;
import 'toast.dart';

/// 保存网络图片：
/// - Android/iOS 存入系统相册「拾光」相簿（gal，Android 10+ 走 MediaStore 免权限）
/// - Web 触发浏览器下载（同源资源 <a download>）
/// - 桌面端（Windows 等）弹出系统保存对话框
///
/// 统一在这里拉取字节与给出 Toast 反馈，平台差异收敛在 impl。
Future<void> saveImage(BuildContext context, String url) async {
  if (url.isEmpty) return;
  Toast.show(context, '正在保存…');
  try {
    final bytes = await _fetchBytes(url);
    final message = await impl.saveImageBytes(bytes, _fileName(url), url);
    if (context.mounted) Toast.show(context, message);
  } catch (_) {
    if (context.mounted) Toast.show(context, '保存失败，请稍后重试');
  }
}

Future<Uint8List> _fetchBytes(String url) async {
  final dio = Dio(BaseOptions(
    responseType: ResponseType.bytes,
    receiveTimeout: const Duration(seconds: 60),
  ));
  final resp = await dio.get<List<int>>(url);
  return Uint8List.fromList(resp.data ?? const []);
}

/// 从 URL 提取文件名（去 query；无扩展名时兜底 .jpg）。
String _fileName(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  var name = path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? '';
  if (!name.contains('.')) name = '$name.jpg';
  return name;
}
