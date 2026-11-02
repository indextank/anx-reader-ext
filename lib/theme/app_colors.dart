import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const defaultBrand = Color(0xFF2196F3);
  static const lightBackground = Color(0xFFF2F2F7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const darkBackground = Color(0xFF1C1C1E);
  static const darkSurface = Color(0xFF2C2C2E);
  static const trueBlack = Color(0xFF000000);
  static const eInkSurface = Color(0xFFFFFFFF);
  static const transparent = Color(0x00000000);

  /// SmartDialog / 模态遮罩（原 Colors.black.withAlpha(35)）。
  static const scrim = Color(0x23000000);
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);

  static const themeChoices = <Color>[
    Color(0xFF9C27B0),
    Color(0xFF3F51B5),
    Color(0xFF2196F3),
    Color(0xFF00BCD4),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFCDDC39),
    Color(0xFFFFC107),
    Color(0xFFFF9800),
    Color(0xFFFF5722),
    Color(0xFFE91E63),
    Color(0xFFF44336),
  ];

  static const lightSuccess = Color(0xFF217A35);
  static const lightOnSuccess = Color(0xFFFFFFFF);
  static const lightWarning = Color(0xFF7A4500);
  static const lightOnWarning = Color(0xFFFFFFFF);
  static const lightError = Color(0xFFBA1A1A);
  static const lightOnError = Color(0xFFFFFFFF);
  static const lightInfo = Color(0xFF005A9C);
  static const lightOnInfo = Color(0xFFFFFFFF);

  static const darkSuccess = Color(0xFF9ADBA6);
  static const darkOnSuccess = Color(0xFF102C16);
  static const darkWarning = Color(0xFFFFCC80);
  static const darkOnWarning = Color(0xFF3B2500);
  static const darkError = Color(0xFFFFB4AB);
  static const darkOnError = Color(0xFF690005);
  static const darkInfo = Color(0xFFA8C8FF);
  static const darkOnInfo = Color(0xFF0B305F);

  static const bookCoverPalette = <Color>[
    Color(0xFF90CAF9),
    Color(0xFFA5D6A7),
    Color(0xFFFFCC80),
    Color(0xFFCE93D8),
    Color(0xFF80CBC4),
    Color(0xFFFFAB91),
    Color(0xFF9FA8DA),
    Color(0xFFE6EE9C),
    Color(0xFF80DEEA),
    Color(0xFFF48FB1),
    Color(0xFFBCAAA4),
    Color(0xFFB0BEC5),
  ];
}

class AppSemanticColors {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.error,
    required this.onError,
    required this.info,
    required this.onInfo,
  });

  const AppSemanticColors.light()
      : this(
          success: AppColors.lightSuccess,
          onSuccess: AppColors.lightOnSuccess,
          warning: AppColors.lightWarning,
          onWarning: AppColors.lightOnWarning,
          error: AppColors.lightError,
          onError: AppColors.lightOnError,
          info: AppColors.lightInfo,
          onInfo: AppColors.lightOnInfo,
        );

  const AppSemanticColors.dark()
      : this(
          success: AppColors.darkSuccess,
          onSuccess: AppColors.darkOnSuccess,
          warning: AppColors.darkWarning,
          onWarning: AppColors.darkOnWarning,
          error: AppColors.darkError,
          onError: AppColors.darkOnError,
          info: AppColors.darkInfo,
          onInfo: AppColors.darkOnInfo,
        );

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color error;
  final Color onError;
  final Color info;
  final Color onInfo;

  AppSemanticColors lerp(AppSemanticColors other, double t) {
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
    );
  }
}
