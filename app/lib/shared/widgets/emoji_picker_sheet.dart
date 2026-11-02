import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// App 内置 emoji 表情面板（打卡弹层用）。
/// 分组展示常用表情，点选插入输入框光标处——不依赖系统 emoji 键盘。
class EmojiPickerSheet extends StatelessWidget {
  final ValueChanged<String> onEmojiSelected;

  const EmojiPickerSheet({
    super.key,
    required this.onEmojiSelected,
  });

  /// 分组表情集（对齐产品调性：日常、温和、正向）
  static const _groups = [
    ('开心', ['😄', '😊', '🙂', '😆', '🤣', '😍', '🥰', '😎']),
    ('状态', ['💪', '🏃', '🎉', '✨', '🌟', '☀️', '🌙', '🌈']),
    ('温柔', ['😌', '🤗', '🫶', '💕', '💗', '🥹', '☺️', '😗']),
    ('生活', ['☕', '📚', '🐱', '🐶', '🌸', '🍀', '🍜', '🎸']),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 320,
        child: Column(
          children: [
            // 把手 + 标题 + 关闭
            Row(
              children: [
                const SizedBox(width: 20),
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 28),
              ],
            ),
            const Divider(height: 1, color: AppTheme.divider),
            // 分组表情
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                children: [
                  for (final (groupName, emojis) in _groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 8, bottom: 6),
                      child: Text(groupName,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSub)),
                    ),
                    GridView.count(
                      crossAxisCount: 8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1,
                      children: [
                        for (final e in emojis)
                          InkWell(
                            onTap: () => onEmojiSelected(e),
                            borderRadius: BorderRadius.circular(8),
                            child: Center(
                              child: Text(e,
                                  style: const TextStyle(fontSize: 26)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
