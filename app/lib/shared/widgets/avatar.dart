import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 头像组件：有图显图，无图用暖色渐变 + 昵称首字（对齐原型手账风）。
class Avatar extends StatelessWidget {
  final String? url;
  final String nickname;
  final double size;
  final VoidCallback? onTap;

  const Avatar({
    super.key,
    this.url,
    this.nickname = '',
    this.size = 48,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final head = _headChar();
    final child = url == null || url!.isEmpty
        ? CircleAvatar(
            radius: size / 2,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
            child: Text(
              head,
              style: TextStyle(
                fontSize: size * 0.38,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryDark,
              ),
            ),
          )
        : CircleAvatar(
            radius: size / 2,
            backgroundColor: AppTheme.divider,
            foregroundImage: NetworkImage(url!),
            onForegroundImageError: (_, __) {},
            child: Text(head, style: TextStyle(fontSize: size * 0.38)),
          );
    if (onTap == null) return child;
    return GestureDetector(onTap: onTap, child: child);
  }

  String _headChar() {
    final t = nickname.trim();
    return t.isEmpty ? '光' : t.characters.first;
  }
}
