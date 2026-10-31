import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shinepick/core/theme/app_theme.dart';

void main() {
  test('AppTheme 色板对齐原型 token', () {
    expect(AppTheme.primary, const Color(0xFFE89B3C));
    expect(AppTheme.primaryDark, const Color(0xFFC97F22));
    expect(AppTheme.bg, const Color(0xFFFAF8F3));
    expect(AppTheme.sand, const Color(0xFFF7E3C4));
    expect(AppTheme.textMain, const Color(0xFF3A3A3A));
    expect(AppTheme.divider, const Color(0xFFECE6D8));
  });

  test('AppTheme 可构建 ThemeData', () {
    final theme = AppTheme.light();
    expect(theme.scaffoldBackgroundColor, AppTheme.bg);
    expect(theme.colorScheme.primary, AppTheme.primary);
  });
}
