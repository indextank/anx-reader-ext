import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/theme/app_typography.dart';
import 'package:anx_reader/theme/content_style_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('design tokens', () {
    test('uses a 4dp spacing grid and unified radii', () {
      const spacing = AppSpacing.tokens;
      expect(spacing.s4, 4);
      expect(spacing.s8, 8);
      expect(spacing.s12, 12);
      expect(spacing.s16, 16);
      expect(spacing.s20, 20);
      expect(spacing.s24, 24);
      expect(spacing.s32, 32);
      expect(spacing.s40, 40);
      expect(spacing.s48, 48);

      const radius = AppRadius.tokens;
      expect(radius.r8, 8);
      expect(radius.r12, 12);
      expect(radius.r16, 16);
      expect(radius.rounded12, BorderRadius.circular(12));
    });

    test('motion tokens use shared durations', () {
      expect(AppMotion.tokens.fast, const Duration(milliseconds: 150));
      expect(AppMotion.tokens.normal, const Duration(milliseconds: 200));
      expect(AppMotion.tokens.emphasis, const Duration(milliseconds: 300));
    });
  });

  group('AppTheme', () {
    test('maps typography and semantic colors into ThemeData', () {
      final theme = AppTheme.build(
        brightness: Brightness.light,
        seedColor: AppColors.defaultBrand,
      );
      final extension = theme.extension<AppThemeExtension>()!;

      expect(theme.useMaterial3, isTrue);
      expect(theme.textTheme.bodyMedium?.fontSize, 16);
      expect(theme.textTheme.bodyMedium?.height, 1.5);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'PingFang SC');
      expect(
        theme.textTheme.bodyMedium?.fontFamilyFallback,
        AppTypography.chineseFontFallback,
      );
      expect(
        theme.textTheme.bodyMedium?.fontFeatures
            ?.any((feature) => feature.feature == 'tnum'),
        isTrue,
      );
      expect(extension.colors.success, AppColors.lightSuccess);
      expect(extension.colors.onSuccess, AppColors.lightOnSuccess);
      expect(extension.spacing, AppSpacing.tokens);
      expect(extension.motion, AppMotion.tokens);
      expect(extension.isEInk, isFalse);
    });

    test('supports OLED dark and e-ink behaviors', () {
      final dark = AppTheme.build(
        brightness: Brightness.dark,
        seedColor: AppColors.defaultBrand,
        trueDarkMode: true,
      );
      final eInk = AppTheme.build(
        brightness: Brightness.dark,
        seedColor: AppColors.defaultBrand,
        eInkMode: true,
      );

      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, AppColors.trueBlack);
      expect(eInk.brightness, Brightness.light);
      expect(eInk.scaffoldBackgroundColor, AppColors.eInkSurface);
      expect(eInk.splashFactory, NoSplash.splashFactory);
      expect(eInk.extension<AppThemeExtension>()?.isEInk, isTrue);
    });

    test('theme extension lerps semantic colors and keeps type', () {
      final light = AppTheme.build(
        brightness: Brightness.light,
        seedColor: AppColors.defaultBrand,
      ).extension<AppThemeExtension>()!;
      final dark = AppTheme.build(
        brightness: Brightness.dark,
        seedColor: AppColors.defaultBrand,
      ).extension<AppThemeExtension>()!;

      final midway = light.lerp(dark, 0.5);
      expect(midway, isA<AppThemeExtension>());
      expect(midway.colors.success,
          Color.lerp(light.colors.success, dark.colors.success, 0.5));
      expect(midway.spacing.s16, 16);
    });
  });

  group('content style tokens', () {
    test('AppColors.scrim matches legacy SmartDialog mask', () {
      expect(AppColors.scrim, const Color(0x23000000)); // black.withAlpha(35)
    });

    test('share tokens keep legacy share-card metrics', () {
      const s = ShareStyleTokens();
      expect(s.outputWidth, 500);
      expect(s.cornerRadius, 8);
      expect(s.bodyFontSize, 18);
      expect(s.accentFontSize, 38);
      expect(s.captionFontSize, 16);
      expect(s.cardPadding, 24);
      expect(s.listSpacing, 8);
      expect(s.imageOverlay, const Color(0xFFFFFFFF));
      expect(s.imageScrim, const Color(0x73000000)); // black45
      expect(s.pillRadius, 8);
    });

    test('share palettes equal the six legacy presets', () {
      final p = ShareStyleTokens.palettes;
      expect(p.length, 6);
      expect(p[0].text, const Color(0xFF000000));
      expect(p[0].background, const Color(0xFFFFFFFF));
      expect(p[1].text, const Color(0xFFF6D995));
      expect(p[1].background, const Color(0xFF302C1C));
      expect(p[2].text, const Color(0xFF000000));
      expect(p[2].background, const Color(0xFFFFECB3)); // amber.shade100
      expect(p[3].text, const Color(0xFFFFFFFF));
      expect(p[3].background, const Color(0xFF37474F)); // blueGrey.shade800
      expect(p[4].text, const Color(0xFF000000));
      expect(p[4].background, const Color(0xFFFCE4EC)); // pink.shade50
      expect(p[5].text, const Color(0xFFFFFFFF));
      expect(p[5].background, const Color(0xFF1A237E)); // indigo.shade900
    });

    test('reader chrome tokens match legacy foliate values', () {
      const r = ReaderStyleTokens();
      expect(r.chromeRadiusXs, 2);
      expect(r.chromeRadiusSm, 4);
      expect(r.codeBlockRadius, 6);
      expect(r.inlineCodeRadius, 3);
      expect(r.overlayFontSize, 24);
      expect(r.searchOutlineColor, '#39c5bbaa');
      expect(r.searchHighlightColor, '#39c5bc83');
    });
  });
}
