import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';

/// IO 平台实现：移动端存入相册「拾光」相簿，桌面端弹保存对话框。
/// 返回保存结果文案（直接展示给用户）。
Future<String> saveImageBytes(Uint8List bytes, String fileName, String sourceUrl) async {
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await Gal.putImageBytes(bytes, name: fileName, album: '拾光');
    } on GalException catch (e) {
      // 首次保存被拒时引导授权后重试一次
      if (e.type != GalExceptionType.accessDenied) rethrow;
      await Gal.requestAccess();
      await Gal.putImageBytes(bytes, name: fileName, album: '拾光');
    }
    return '已保存到相册';
  }
  // 桌面端：系统另存为对话框（插件直接把 bytes 写入选定路径）
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: _mime(fileName),
  );
  if (uri == null) return '已取消保存';
  return '已保存';
}

String _mime(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return switch (ext) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    _ => 'image/jpeg',
  };
}
