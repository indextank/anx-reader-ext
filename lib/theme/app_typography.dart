import 'package:flutter/material.dart';

class AppTypeScale {
  const AppTypeScale();

  static const tokens = AppTypeScale();

  double get display => 32;
  double get headline => 24;
  double get title => 20;
  double get titleSmall => 18;
  double get body => 16;
  double get bodySmall => 14;
  double get label => 12;
}

class AppTypography {
  AppTypography._();

  /// 跨端中文字体回退链：优先各平台原生中文字体，最后回退到系统 sans-serif，
  /// 避免 Windows/Linux/Android 打包后因缺少 PingFang 而回退到不一致的默认字体。
  static const chineseFontFallback = <String>[
    // HarmonyOS / Android
    'HarmonyOS Sans SC',
    'HarmonyOS Sans',
    'MiSans',
    // iOS / macOS
    'PingFang SC',
    // Windows
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    '微软雅黑',
    // Linux / Web / 通用 CJK
    'Noto Sans CJK SC',
    'Noto Sans SC',
    'Noto Sans',
    // 西文/系统 UI 兜底
    'Segoe UI',
    'Roboto',
    'sans-serif',
  ];

  static TextTheme textTheme(Color color) {
    const scale = AppTypeScale.tokens;
    TextStyle style(double fontSize, double height, {FontWeight? weight}) {
      return TextStyle(
        color: color,
        fontFamily: 'PingFang SC',
        fontFamilyFallback: chineseFontFallback,
        fontSize: fontSize,
        height: height,
        fontWeight: weight,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
    }

    // 完整定义 Material 的全部 15 个文字角色，避免部分组件读到 null 后
    // 回退到 Material 默认字号/字体，导致项目内文字样式不统一。
    return TextTheme(
      displayLarge: style(scale.display, 1.2, weight: FontWeight.w600),
      displayMedium: style(scale.display, 1.25, weight: FontWeight.w600),
      displaySmall: style(scale.display, 1.25, weight: FontWeight.w600),
      headlineLarge: style(scale.headline, 4 / 3, weight: FontWeight.w600),
      headlineMedium: style(scale.headline, 4 / 3, weight: FontWeight.w600),
      headlineSmall: style(scale.headline, 4 / 3, weight: FontWeight.w600),
      titleLarge: style(scale.title, 1.4, weight: FontWeight.w600),
      titleMedium: style(scale.titleSmall, 4 / 3, weight: FontWeight.w500),
      titleSmall: style(scale.body, 1.5, weight: FontWeight.w500),
      bodyLarge: style(scale.body, 1.5),
      bodyMedium: style(scale.body, 1.5),
      bodySmall: style(scale.bodySmall, 10 / 7),
      labelLarge: style(scale.bodySmall, 10 / 7, weight: FontWeight.w500),
      labelMedium: style(scale.label, 4 / 3, weight: FontWeight.w500),
      labelSmall: style(scale.label, 4 / 3),
    );
  }
}
