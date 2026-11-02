import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('${brightness.name} normal text pairs meet 4.5:1', () {
      final theme = AppTheme.build(
        brightness: brightness,
        seedColor: AppColors.defaultBrand,
      );
      final colors = theme.colorScheme;
      final semantic = theme.extension<AppThemeExtension>()!.colors;
      final pairs = <(Color, Color)>[
        (colors.onSurface, colors.surface),
        (colors.onSurface, theme.scaffoldBackgroundColor),
        (colors.onSurfaceVariant, colors.surface),
        (colors.onPrimary, colors.primary),
        (colors.onSecondary, colors.secondary),
        (semantic.onSuccess, semantic.success),
        (semantic.onWarning, semantic.warning),
        (semantic.onError, semantic.error),
        (semantic.onInfo, semantic.info),
      ];

      for (final (foreground, background) in pairs) {
        expect(
          contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: 'Insufficient contrast for $foreground on $background '
              'in ${brightness.name} theme',
        );
      }
    });
  }
}

double contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
