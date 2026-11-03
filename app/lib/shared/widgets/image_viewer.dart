import 'package:flutter/material.dart';

import 'image_saver.dart';

/// 全屏图片查看器：支持多图滑动、双指缩放、点击关闭、长按/按钮保存。
class ImageViewerPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const ImageViewerPage({
    super.key,
    required this.urls,
    this.initialIndex = 0,
  });

  /// 静态方法：从任意位置打开查看器
  static void open(BuildContext context, List<String> urls, {int initialIndex = 0}) {
    if (urls.isEmpty) return;
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) => ImageViewerPage(
          urls: urls,
          initialIndex: initialIndex,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 图片 PageView
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.urls.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) => _ZoomableImage(url: widget.urls[i]),
            ),
          ),
          // 顶部关闭按钮 + 计数
          SafeArea(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    if (widget.urls.length > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_currentIndex + 1} / ${widget.urls.length}',
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.download_outlined,
                          color: Colors.white, size: 24),
                      tooltip: '保存图片',
                      onPressed: () =>
                          saveImage(context, widget.urls[_currentIndex]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 单张可缩放图片。
class _ZoomableImage extends StatelessWidget {
  final String url;
  const _ZoomableImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 4.0,
      child: Center(
        child: GestureDetector(
          onLongPress: () => saveImage(context, url),
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, color: Colors.white38, size: 48),
                  SizedBox(height: 8),
                  Text('图片加载失败', style: TextStyle(color: Colors.white38)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
