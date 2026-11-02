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

  static const chineseFontFallback = <String>[
    'HarmonyOS Sans',
    'MiSans',
    '微软雅黑',
    'Noto Sans SC',
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

    return TextTheme(
      displaySmall: style(scale.display, 1.25, weight: FontWeight.w600),
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
