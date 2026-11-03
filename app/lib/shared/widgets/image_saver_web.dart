import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web 平台实现：字节转 Blob + <a download> 触发浏览器下载
/// （URL 与生成的分享卡图片都走同一条路，不再依赖同源地址）。
Future<String> saveImageBytes(Uint8List bytes, String fileName, String sourceUrl) async {
  final ext = fileName.split('.').last.toLowerCase();
  final mime = switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/png',
  };
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final objUrl = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = objUrl
    ..download = fileName;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(objUrl);
  return '已开始下载';
}
