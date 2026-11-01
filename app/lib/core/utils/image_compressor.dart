import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// 图片压缩工具：上传前在客户端将大图缩小并转为 JPEG，
/// 手机拍照（3-8MB）压缩到 200-500KB，大幅减少上传失败率。
class ImageCompressor {
  ImageCompressor._();

  static const int _maxWidth = 1920;
  static const int _quality = 85;
  static const int _skipThreshold = 500 * 1024; // 500KB 以下不压缩

  /// 压缩图片：解码（支持 HEIC/JPEG/PNG/WebP）→ 限宽 → JPEG。
  /// 如果结果比原始数据还大（已是小 JPEG），返回原始数据。
  static Future<Uint8List> compress(Uint8List bytes, {int maxWidth = _maxWidth, int quality = _quality}) async {
    // 先探测原始尺寸
    final probe = await ui.instantiateImageCodec(bytes);
    final probeFrame = await probe.getNextFrame();
    final origW = probeFrame.image.width;
    probeFrame.image.dispose();
    probe.dispose();

    // 小图且非 HEIC：不压缩
    if (origW <= maxWidth && bytes.length < _skipThreshold) {
      return bytes;
    }

    // 解码并等比缩放到目标宽度（Flutter 自动保持宽高比）
    final targetW = min(origW, maxWidth);
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetW);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;

    // 取 RGBA 像素数据
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    if (data == null) return bytes;

    // 用 image 包编码为 JPEG（纯 Dart，全平台可用）
    final raw = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: data.buffer,
      numChannels: 4,
    );
    final jpeg = Uint8List.fromList(img.encodeJpg(raw, quality: quality));

    // 压缩后比原始还大（已是最优 JPEG）→ 返回原始
    return jpeg.length < bytes.length ? jpeg : bytes;
  }
}
