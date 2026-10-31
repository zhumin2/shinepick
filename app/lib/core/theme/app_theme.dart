import 'package:flutter/material.dart';

/// 拾光全局主题：温暖手账风
/// 设计 token 对齐产品原型（prototype/拾光-产品原型.html :root）
class AppTheme {
  static const Color bg = Color(0xFFFAF8F3);
  static const Color primary = Color(0xFFE89B3C);
  static const Color primaryDark = Color(0xFFC97F22);
  static const Color textMain = Color(0xFF3A3A3A);
  static const Color textSub = Color(0xFF8A8578);
  static const Color textFaint = Color(0xFFB8B2A4);
  static const Color card = Color(0xFFFFFFFF);
  static const Color divider = Color(0xFFECE6D8);

  /// 暖沙底：选中态、今日卡渐变（原型 --accent-soft）
  static const Color sand = Color(0xFFF7E3C4);

  /// 品类辅助色（原型 --leaf/--sky/--pink）
  static const Color leaf = Color(0xFFA8B89A);
  static const Color sky = Color(0xFFA8C5DA);
  static const Color pink = Color(0xFFE8B5B0);

  /// 卡片柔和阴影（原型 --shadow: 0 6px 24px rgba(58,58,58,.06)）
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF3A3A3A).withValues(alpha: 0.06),
          offset: const Offset(0, 6),
          blurRadius: 24,
        ),
      ];

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        surface: bg,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: textMain,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(color: textSub, fontSize: 15),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: divider),
        ),
      ),
    );
  }
}
