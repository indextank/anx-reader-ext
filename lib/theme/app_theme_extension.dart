import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_elevation.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_typography.dart';
import 'package:anx_reader/theme/content_style_tokens.dart';
import 'package:flutter/material.dart';

@immutable
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  const AppThemeExtension({
    required this.colors,
    required this.typography,
    required this.spacing,
    required this.radius,
    required this.elevation,
    required this.motion,
    required this.content,
    required this.isEInk,
  });

  final AppSemanticColors colors;
  final AppTypeScale typography;
  final AppSpacing spacing;
  final AppRadius radius;
  final AppElevation elevation;
  final AppMotion motion;
  final AppContentStyleTokens content;
  final bool isEInk;

  @override
  AppThemeExtension copyWith({
    AppSemanticColors? colors,
    AppTypeScale? typography,
    AppSpacing? spacing,
    AppRadius? radius,
    AppElevation? elevation,
    AppMotion? motion,
    AppContentStyleTokens? content,
    bool? isEInk,
  }) {
    return AppThemeExtension(
      colors: colors ?? this.colors,
      typography: typography ?? this.typography,
      spacing: spacing ?? this.spacing,
      radius: radius ?? this.radius,
      elevation: elevation ?? this.elevation,
      motion: motion ?? this.motion,
      content: content ?? this.content,
      isEInk: isEInk ?? this.isEInk,
    );
  }

  @override
  AppThemeExtension lerp(ThemeExtension<AppThemeExtension>? other, double t) {
    if (other is! AppThemeExtension) return this;
    return AppThemeExtension(
      colors: colors.lerp(other.colors, t),
      typography: t < 0.5 ? typography : other.typography,
      spacing: t < 0.5 ? spacing : other.spacing,
      radius: t < 0.5 ? radius : other.radius,
      elevation: t < 0.5 ? elevation : other.elevation,
      motion: t < 0.5 ? motion : other.motion,
      content: t < 0.5 ? content : other.content,
      isEInk: t < 0.5 ? isEInk : other.isEInk,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppThemeExtension get appTheme =>
      Theme.of(this).extension<AppThemeExtension>()!;
}
