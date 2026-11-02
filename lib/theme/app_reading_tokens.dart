import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class AppReadingTokens {
  AppReadingTokens._();

  static const panelPadding = AppSpacing.horizontal16;
  static const panelVerticalPadding = AppSpacing.vertical12;
  static const contentPadding = AppSpacing.all16;
  static const compactPadding = AppSpacing.all8;
  static const compactMargin = AppSpacing.all8;
  static const listItemGap = EdgeInsets.only(bottom: 8);
  static const smallPadding = AppSpacing.all4;
  static const tinyPadding =
      EdgeInsets.only(left: 2, top: 2, right: 2, bottom: 2);
  static const menuPadding = AppSpacing.all8;
  static const menuGap = AppSpacing.all12;
  static const aiPopupPadding = EdgeInsets.only(top: 8);
  static const ttsFabSafePadding = EdgeInsets.only(right: 16, bottom: 24);
  static const historyPadding = EdgeInsets.only(bottom: 40);
  static const historyButtonPadding = AppSpacing.horizontal16;
  static const historyRadius = AppRadius.border32;
  static const backgroundItemPadding = EdgeInsets.only(
    left: 8,
    right: 8,
    bottom: 8,
  );
  static const backgroundFitPadding = EdgeInsets.only(
    left: 16,
    right: 16,
    bottom: 12,
  );
  static const backgroundEffectPadding = EdgeInsets.only(
    left: 16,
    right: 16,
    bottom: 8,
  );
  static const backgroundLabelPadding = EdgeInsets.symmetric(
    horizontal: 8,
    vertical: 4,
  );
  static const backgroundDayLabelMargin = EdgeInsets.only(left: 8, bottom: 8);
  static const backgroundNightLabelMargin =
      EdgeInsets.only(right: 8, bottom: 8);
  static const backgroundRadius = AppRadius.border20;
  static const backgroundLabelRadius = AppRadius.border8;
  static const contextMenuRadius = AppRadius.border12;
  static const pageTurnRadius = AppRadius.border12;
  static const dropdownRadius = AppRadius.border8;
  static const pillRadius = AppRadius.pill;
  static const settingsPadding = AppSpacing.all20;
  static const settingsCompactPadding = AppSpacing.all8;
  static const settingsItemPadding = AppSpacing.all8;
  static const settingsRowGap = EdgeInsets.only(bottom: 8);
  static const settingsIndent = EdgeInsets.only(left: 16);
  static const dropdownGap = EdgeInsets.only(right: 4);
  static const dropdownGapReverse = EdgeInsets.only(left: 4);
  static const sliderPadding = AppSpacing.horizontal8;
  static const titleFontFamily = 'SourceHanSerif';
  static const codeFontFamily = 'Courier New';
  static const imageBackground = AppColors.black;
  static const imageForeground = AppColors.white;
  static const transparent = AppColors.transparent;

  static const backgroundItemHeight = 120.0;
  static const backgroundDiagonalOffset = 32.0;
  static const backgroundSwapButtonSize = 36.0;
  static const backgroundControlLabelWidth = 64.0;
  static const backgroundControlValueWidth = 36.0;
  static const searchFieldHeight = 48.0;
  static const tocItemMinHeight = 48.0;
  static const tocItemProgressMinHeight = 64.0;
  static const tocIndent = 24.0;
  static const pageTurnDiagramWidth = 100.0;
  static const noteMenuMaxHeight = 200.0;
  static const noteMenuVerticalWidth = 100.0;
  static const searchMenuHeight = 350.0;
  static const searchMenuVerticalWidth = 300.0;
  static const translationMenuHeight = 150.0;
  static const translationMenuVerticalWidth = 100.0;
  static const cssEditorHeight = 200.0;

  static Color scrim(BuildContext context) =>
      Theme.of(context).colorScheme.scrim.withValues(alpha: 0.12);

  static Color muted(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  static Color subtleBorder(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  static Color divider(BuildContext context) =>
      Theme.of(context).colorScheme.outlineVariant;

  static Color error(BuildContext context) => context.appTheme.colors.error;

  static Color nextPageArea(BuildContext context) =>
      context.appTheme.colors.error.withValues(alpha: 0.4);

  static Color previousPageArea(BuildContext context) =>
      context.appTheme.colors.info.withValues(alpha: 0.4);

  static Color menuArea(BuildContext context) =>
      context.appTheme.colors.success.withValues(alpha: 0.4);

  static Color inactiveArea(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.25);
}
