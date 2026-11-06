import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_dropdown_tokens.dart';
import 'package:anx_reader/theme/app_elevation.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/theme/app_typography.dart';
import 'package:anx_reader/theme/content_style_tokens.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static ThemeData build({
    required Brightness brightness,
    required Color seedColor,
    bool trueDarkMode = false,
    bool eInkMode = false,
  }) {
    final isDark = !eInkMode && brightness == Brightness.dark;
    final background = eInkMode
        ? AppColors.eInkSurface
        : isDark
            ? (trueDarkMode ? AppColors.trueBlack : AppColors.darkBackground)
            : AppColors.lightBackground;
    final surfaceContainer = eInkMode
        ? AppColors.eInkSurface
        : isDark
            ? AppColors.darkSurface
            : AppColors.lightSurface;
    final colorScheme = eInkMode
        ? const ColorScheme.light(
            primary: Colors.black,
            onPrimary: Colors.white,
            primaryContainer: Colors.grey,
            onPrimaryContainer: Colors.black,
            secondary: Colors.grey,
            onSecondary: Colors.white,
            secondaryContainer: Colors.black12,
            onSecondaryContainer: Colors.black,
            surface: Colors.white,
            onSurface: Colors.black,
          )
        : ColorScheme.fromSeed(
            seedColor: seedColor,
            brightness: isDark ? Brightness.dark : Brightness.light,
            surface: background,
            surfaceContainer: surfaceContainer,
          );

    final base = eInkMode
        ? FlexThemeData.light(
            useMaterial3: true,
            swapLegacyOnMaterial3: true,
            colorScheme: colorScheme,
          )
        : isDark
            ? FlexThemeData.dark(
                useMaterial3: true,
                swapLegacyOnMaterial3: true,
                darkIsTrueBlack: trueDarkMode,
                colorScheme: colorScheme,
              )
            : FlexThemeData.light(
                useMaterial3: true,
                swapLegacyOnMaterial3: true,
                colorScheme: colorScheme,
              );

    final buttonShape = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: AppRadius.border12),
    );
    const buttonMinimum = WidgetStatePropertyAll<Size>(Size(48, 48));
    const buttonPadding = WidgetStatePropertyAll<EdgeInsetsGeometry>(
      AppSpacing.horizontal20,
    );
    final appExtension = AppThemeExtension(
      colors: isDark
          ? const AppSemanticColors.dark()
          : const AppSemanticColors.light(),
      typography: AppTypeScale.tokens,
      spacing: AppSpacing.tokens,
      radius: AppRadius.tokens,
      elevation: AppElevation.tokens,
      motion: AppMotion.tokens,
      content: AppContentStyleTokens.tokens,
      isEInk: eInkMode,
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      textTheme: AppTypography.textTheme(colorScheme.onSurface),
      primaryTextTheme: AppTypography.textTheme(colorScheme.onPrimary),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonMinimum,
          padding: buttonPadding,
          shape: buttonShape,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonMinimum,
          padding: buttonPadding,
          shape: buttonShape,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonMinimum,
          padding: buttonPadding,
          shape: buttonShape,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: buttonMinimum,
          maximumSize: WidgetStatePropertyAll<Size>(Size(48, 48)),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainer,
        contentPadding: AppSpacing.symmetric(horizontal: 16, vertical: 12),
        errorMaxLines: 3,
        border: OutlineInputBorder(borderRadius: AppRadius.border12),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.border12,
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.border12,
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.border12,
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      // 全局下拉/菜单选项高度（Material 默认 48dp -> 40dp）。
      menuButtonTheme: const MenuButtonThemeData(
        style: AppDropdownTokens.menuItemStyle,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: AppSpacing.zero,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.border16),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: 48,
        contentPadding: AppSpacing.horizontal16,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.border12),
      ),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: background),
      drawerTheme: DrawerThemeData(backgroundColor: background),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainer,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.border16),
      ),
      splashFactory: eInkMode ? NoSplash.splashFactory : base.splashFactory,
      highlightColor: eInkMode ? Colors.transparent : base.highlightColor,
      pageTransitionsTheme: eInkMode
          ? const PageTransitionsTheme(
              builders: {
                TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.macOS: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.windows: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.linux: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.fuchsia: _NoAnimationPageTransitionsBuilder(),
              },
            )
          : base.pageTransitionsTheme,
      extensions: [appExtension],
    );
  }
}

class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
