import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shinepick/core/theme/app_theme.dart';

void main() {
  test('AppTheme 色板符合手账风规范', () {
    expect(AppTheme.primary, const Color(0xFFE89B3C));
    expect(AppTheme.bg, const Color(0xFFFAF8F3));
    expect(AppTheme.textMain, const Color(0xFF3D3A36));
  });

  test('AppTheme 可构建 ThemeData', () {
    final theme = AppTheme.light();
    expect(theme.scaffoldBackgroundColor, AppTheme.bg);
    expect(theme.colorScheme.primary, AppTheme.primary);
  });
}
