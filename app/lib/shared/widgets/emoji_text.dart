import 'package:flutter/material.dart';

/// 动态文本（可能含用户输入的 emoji）专用：
/// 局部应用 Noto Color Emoji 字体兜底，不污染全局数字/拉丁渲染。
class EmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  const EmojiText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: (style ?? const TextStyle()).copyWith(
        fontFamilyFallback: ['Noto Color Emoji'],
      ),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
  }
}
