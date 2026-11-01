import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// 图片压缩工具：多级降级压缩，确保上传成功率。
///
/// 压缩策略（逐级降级直到达标）：
///   第 1 级：限宽 1920px + JPEG q85   （大多数图片在这一步就达标）
///   第 2 级：限宽 1280px + JPEG q75   （仍 > 2MB 时降级）
///   第 3 级：限宽 960px  + JPEG q70   （仍 > 1MB 时降级）
///   第 4 级：限宽 640px  + JPEG q60   （保底：极罕见的超大图）
///
/// 每一级压缩后如果结果比原始数据还小，就用压缩结果；否则继续下一级。
class ImageCompressor {
  ImageCompressor._();

  /// 目标最大文件大小（500KB，超过则尝试更激进的压缩级别）
  static const int _targetSize = 500 * 1024;

  /// 压缩级别表：每级 [maxWidth, quality]
  static const _levels = [
    (1920, 85),
    (1280, 75),
    (960, 70),
    (640, 60),
  ];

  /// 压缩图片到合理大小。
  /// 返回压缩后的字节（可能小于原始大小），以及是否实际执行了压缩。
  static Future<CompressionResult> compress(Uint8List bytes) async {
    // 探测原始尺寸
    int origW;
    try {
      final probe = await ui.instantiateImageCodec(bytes);
      final frame = await probe.getNextFrame();
      origW = frame.image.width;
      frame.image.dispose();
      probe.dispose();
    } catch (_) {
      // 无法解码（如 HEIC）：返回原始数据，调用方需处理
      return CompressionResult(bytes: bytes, compressed: false, width: 0, height: 0);
    }

    // 已经够小 → 不压缩
    if (bytes.length <= _targetSize && origW <= _levels[0].$1) {
      return CompressionResult(bytes: bytes, compressed: false, width: origW, height: 0);
    }

    // 逐级尝试
    Uint8List? best;
    int bestW = 0, bestH = 0;
    for (final (maxWidth, quality) in _levels) {
      try {
        final result = await _compressAtLevel(bytes, maxWidth: min(origW, maxWidth), quality: quality);
        if (result == null) continue;
        best = result.$1;
        bestW = result.$2;
        bestH = result.$3;
        // 达到目标大小 → 停止降级
        if (best.length <= _targetSize) break;
        // 比原始还大 → 继续下一级
        if (best.length >= bytes.length) continue;
      } catch (_) {
        continue;
      }
    }

    // 全部级别都失败 → 返回原始数据
    if (best == null || best.length >= bytes.length) {
      return CompressionResult(bytes: bytes, compressed: false, width: origW, height: 0);
    }
    return CompressionResult(bytes: best, compressed: true, width: bestW, height: bestH);
  }

  /// 在指定级别执行压缩，返回 (data, width, height)。
  static Future<(Uint8List, int, int)?> _compressAtLevel(
    Uint8List bytes, {
    required int maxWidth,
    required int quality,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final w = image.width;
    final h = image.height;

    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    if (data == null) return null;

    final raw = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: data.buffer,
      numChannels: 4,
    );
    final jpeg = Uint8List.fromList(img.encodeJpg(raw, quality: quality));
    return (jpeg, w, h);
  }
}

/// 压缩结果。
class CompressionResult {
  final Uint8List bytes;
  final bool compressed;
  final int width;
  final int height;

  const CompressionResult({
    required this.bytes,
    required this.compressed,
    required this.width,
    required this.height,
  });
}
