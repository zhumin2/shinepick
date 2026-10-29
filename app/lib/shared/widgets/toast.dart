import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 全局轻提示（对齐原型 toast：圆角深色胶囊，不遮挡操作）。
class Toast {
  Toast._();

  static void show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(fontSize: 14)),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.textMain,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
  }
}
