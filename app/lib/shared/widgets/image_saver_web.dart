import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web 平台实现：图片与站点同源（/static/...），直接用 <a download>
/// 触发浏览器下载，无需先取字节（bytes 参数仅为签名对齐，未使用）。
Future<String> saveImageBytes(Uint8List bytes, String fileName, String sourceUrl) async {
  final anchor = web.HTMLAnchorElement()
    ..href = sourceUrl
    ..download = fileName;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  return '已开始下载';
}
