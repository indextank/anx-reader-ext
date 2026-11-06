import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/widgets/reading_page/panel_width.dart';

/// 样式面板内容宽度计算：按“最宽选项行 = 行首图标/标签 + 控件固有宽度”
/// 解析地推导面板所需宽度（任务要求：先测量所有选项标签与控件在
/// 最宽状态下的固有宽度，取最大值加上统一内边距）。
///
/// 纯函数核心 [computeStylePanelContentWidth] 不依赖 BuildContext，
/// 可独立单元测试；[stylePanelRowSpecs] 从 l10n 收集当前语言的全部
/// 行规格（含横排/竖排两套标签，切换写作方向不影响宽度结论）。
enum StylePanelLeading { none, sliderIcon, tileIcon }

class StylePanelRowSpec {
  const StylePanelRowSpec.label(
    this.label, {
    required this.controlWidth,
    this.leading = StylePanelLeading.none,
    this.extraLabels = const <String>[],
  }) : segments = null;

  const StylePanelRowSpec.segments(
    this.label, {
    required this.segments,
    this.leading = StylePanelLeading.none,
  })  : controlWidth = 0,
        extraLabels = const <String>[];

  /// 行首标签（滑杆名 / 单行 tile 标题 / 下拉字段名），可空串。
  final String? label;

  /// 分段按钮各段标签（与 [controlWidth] 互斥）。
  final List<String>? segments;

  /// 行尾控件固有宽度（滑杆最小轨道、开关、下拉框等）。
  final double controlWidth;

  /// 行首图标类型（滑杆行图标 / tile 前置图标），宽度由当前密度决定。
  final StylePanelLeading leading;

  /// 同一行内额外标签（如上下边距双滑杆行的第二个标签）。
  final List<String> extraLabels;
}

/// 控件固有宽度常量（Material 3 量级，集中定义便于调整与测试）。
class StylePanelControlMetrics {
  const StylePanelControlMetrics._();

  /// 滑杆最小可用轨道（含 Slider 自身水平内边距）。
  static const double sliderTrack = 132;

  /// 带数值标签的滑杆行最小宽度。
  static const double sliderTrackWithValue = sliderTrack + 48;

  /// 屏幕常亮滑杆行最小控件宽度。
  static const double timeoutSlider = 160;

  /// 行尾开关宽度。
  static const double switchWidth = 52;

  /// 行尾下拉框（对齐方式）宽度令牌。
  static const double dropdown = StylePanelTokens.dropdownWidth;

  /// 下拉字段（字体/翻页方式）最小可用宽度。
  static const double dropdownField = 176;

  /// 主题色卡横向列表最小宽度。
  static const double themeRow = 260;

  /// 简繁转换/翻页模式等两段按钮的标签占位（控件宽度已在 segments 内计算）。
  static const double compactControl = 72;

  /// 阅读信息中并列 3 个下拉框的整行最小宽度。
  static const double infoDropdownRow = compactControl * 3;
}

/// 收集当前语言下面板所有行的宽度规格。
List<StylePanelRowSpec> stylePanelRowSpecs(L10n l10n) {
  return [
    // —— 样式（StyleWidget）——
    StylePanelRowSpec.label(
      l10n.readingPageFontSize,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageLineSpacing,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageParagraphSpacing,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.font,
      controlWidth: StylePanelControlMetrics.dropdownField,
    ),
    StylePanelRowSpec.label(
      l10n.readingPagePageTurningMethod,
      controlWidth: StylePanelControlMetrics.dropdownField,
    ),
    const StylePanelRowSpec.label('',
        controlWidth: StylePanelControlMetrics.themeRow),
    // —— 阅读（ReadingMoreSettings）——
    StylePanelRowSpec.label(
      l10n.downloadFonts,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    StylePanelRowSpec.segments(
      l10n.readingPageWritingDirection,
      segments: [
        l10n.readingPageWritingDirectionAuto,
        l10n.readingPageWritingDirectionVertical,
        l10n.readingPageWritingDirectionHorizontal,
      ],
    ),
    StylePanelRowSpec.segments(
      l10n.translationMode,
      segments: [
        l10n.readingPageOriginal,
        l10n.translationOnly,
        l10n.bilingual,
      ],
    ),
    StylePanelRowSpec.segments(
      l10n.readingPageColumnCount,
      segments: [
        l10n.readingPageAuto,
        l10n.readingPageSingle,
        l10n.readingPageDouble,
      ],
    ),
    StylePanelRowSpec.label(
      l10n.readingPageColumnThreshold,
      controlWidth: StylePanelControlMetrics.sliderTrackWithValue,
    ),
    StylePanelRowSpec.segments(
      l10n.readingPageConvertChinese,
      segments: [
        l10n.readingPageOriginal,
        l10n.readingPageSimplified,
        l10n.readingPageTraditional,
      ],
    ),
    StylePanelRowSpec.segments(
      l10n.codeHighlightTheme,
      segments: [
        l10n.codeHighlightOff,
        l10n.codeHighlightLight,
        l10n.codeHighlightDark,
      ],
    ),
    StylePanelRowSpec.label(
      l10n.codeHighlightLightThemes,
      controlWidth: StylePanelControlMetrics.themeRow,
    ),
    StylePanelRowSpec.segments(
      l10n.readingNotesPanelPosition,
      segments: [
        l10n.readingPanelPositionPopup,
        l10n.readingPanelPositionRight,
      ],
    ),
    StylePanelRowSpec.segments(
      l10n.readingStylePanelPosition,
      segments: [
        l10n.readingPanelPositionPopup,
        l10n.readingPanelPositionRight,
      ],
    ),
    // 阅读信息 / 页眉页脚：3 个下拉框一行 + 4 个滑杆行。
    const StylePanelRowSpec.label('',
        controlWidth: StylePanelControlMetrics.infoDropdownRow),
    StylePanelRowSpec.label(
      l10n.readingSettingsMargin,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageLeftMargin,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageRightMargin,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageFontSize,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    // —— 样式（StyleSettings）——
    StylePanelRowSpec.label(
      l10n.useBookStyles,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageIndent,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageVerticleMargin,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageSideMargin,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageTopMargin,
      controlWidth: StylePanelControlMetrics.sliderTrack * 2,
      leading: StylePanelLeading.sliderIcon,
      extraLabels: <String>[l10n.readingPageBottomMargin],
    ),
    StylePanelRowSpec.label(
      l10n.readingPageLetterSpacing,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageFontWeight,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.headingFontSize,
      controlWidth: StylePanelControlMetrics.sliderTrack,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.label(
      l10n.textAlignment,
      controlWidth: StylePanelControlMetrics.dropdown,
      leading: StylePanelLeading.tileIcon,
    ),
    StylePanelRowSpec.label(
      l10n.customCssEnabled,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    // —— 其他（OtherSettings）——
    StylePanelRowSpec.label(
      l10n.readingPageFullScreen,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageSwapPageTurnArea,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageShowMenuOnHover,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageAutoAdjustReadingTheme,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageAutoTranslateSelection,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageAutoMarkSelection,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    StylePanelRowSpec.label(
      l10n.readingPageScreenTimeout,
      controlWidth: StylePanelControlMetrics.timeoutSlider,
      leading: StylePanelLeading.sliderIcon,
    ),
    StylePanelRowSpec.segments(
      l10n.readingPagePageTurningMethod,
      segments: [
        l10n.pageTurnModeSimple,
        l10n.pageTurnModeCustom,
      ],
    ),
  ];
}

/// 测量单行设置项的固有宽度（标签 + 行首图标 + 控件/分段）。
///
/// 公开为纯函数，便于测试与“逻辑-布局解耦”：面板只消费解析出的宽度。
double measureStylePanelRowWidth({
  required StylePanelRowSpec row,
  required TextStyle labelStyle,
  required TextStyle controlStyle,
  required TextScaler textScaler,
  required StylePanelMetrics metrics,
}) {
  var width = switch (row.leading) {
    StylePanelLeading.none => 0.0,
    StylePanelLeading.sliderIcon => metrics.sliderLeading,
    StylePanelLeading.tileIcon => metrics.tileLeading,
  };
  final label = row.label;
  if (label != null && label.isNotEmpty) {
    width += measureTextWidth(label, labelStyle, textScaler) + metrics.labelGap;
  }
  for (final extra in row.extraLabels) {
    width += measureTextWidth(extra, labelStyle, textScaler) +
        metrics.sliderLeading +
        metrics.labelGap;
  }
  final segments = row.segments;
  if (segments != null && segments.isNotEmpty) {
    for (final segment in segments) {
      width += measureTextWidth(segment, controlStyle, textScaler) +
          metrics.segmentChrome;
    }
  } else {
    width += row.controlWidth;
  }
  return width;
}

/// 纯函数核心：行规格 + 文本样式 + 缩放 + 密度 → 内容宽度。
///
/// [labelStyle] 用于行首标签，[controlStyle] 用于分段/下拉文字；
/// [metrics] 提供行间/行内边距、图标占位与分段装饰宽度。
double computeStylePanelContentWidth({
  required List<StylePanelRowSpec> rows,
  required TextStyle labelStyle,
  required TextStyle controlStyle,
  required TextScaler textScaler,
  required StylePanelMetrics metrics,
}) {
  var widest = 0.0;
  for (final row in rows) {
    final width = measureStylePanelRowWidth(
      row: row,
      labelStyle: labelStyle,
      controlStyle: controlStyle,
      textScaler: textScaler,
      metrics: metrics,
    );
    if (width > widest) widest = width;
  }
  // 所有行都至少有一层子缩进；用最大值保守计入，保证按内容解析出的宽度
  // 一定不小于实际单行渲染宽度。
  return widest +
      metrics.horizontalPaddingTotal +
      metrics.childIndent.horizontal;
}

/// 兼容旧调用：使用常规密度测量内容宽度。
double stylePanelContentWidth(BuildContext context) =>
    stylePanelContentWidthFor(context, StylePanelMetrics.regular);

/// 按指定密度测量内容宽度。
double stylePanelContentWidthFor(
  BuildContext context,
  StylePanelMetrics metrics,
) {
  final l10n = L10n.of(context);
  final theme = Theme.of(context);
  return computeStylePanelContentWidth(
    rows: stylePanelRowSpecs(l10n),
    labelStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
    controlStyle: theme.textTheme.labelLarge ?? const TextStyle(),
    textScaler: MediaQuery.textScalerOf(context),
    metrics: metrics,
  );
}

/// 样式面板布局方案：宽度/密度/是否退化为横向滚动。
@immutable
class StylePanelLayoutPlan {
  const StylePanelLayoutPlan({
    required this.width,
    required this.contentWidth,
    required this.metrics,
    required this.horizontallyScrollable,
  });

  final double width;
  final double contentWidth;
  final StylePanelMetrics metrics;

  /// true 表示常规与紧凑密度都放不下（极窄屏），此时保持单行并用横向滚动
  /// 兜底，而不是换行/截断。
  final bool horizontallyScrollable;

  @override
  String toString() => 'StylePanelLayoutPlan(width: $width, '
      'contentWidth: $contentWidth, compact: ${metrics.isCompact}, '
      'horizontalScroll: $horizontallyScrollable)';
}

/// 依据可用宽度解析样式面板宽度：
/// 1. 常规密度能容纳最长设置项时，宽度由内容驱动（受 maxWidth 约束）；
/// 2. 否则使用紧凑密度，仍以可用最大宽度为上限；
/// 3. 紧凑密度仍放不下时，保持可用宽度并退化为横向滚动（不换行）。
StylePanelLayoutPlan resolveStylePanelLayout(
  BuildContext context, {
  required double availableWidth,
  required double maxWidth,
  double minWidth = StylePanelTokens.minPanelWidth,
}) {
  final safeAvailable = math.max(0.0, availableWidth);
  final safeMax = math.max(0.0, math.min(maxWidth, safeAvailable));
  final safeMin = math.min(minWidth, safeMax);

  final regular = stylePanelContentWidthFor(context, StylePanelMetrics.regular);
  if (regular <= safeMax) {
    final width = resolvePanelWidth(
      intrinsicWidth: regular,
      minWidth: safeMin,
      maxWidth: safeMax,
    );
    return StylePanelLayoutPlan(
      width: width,
      contentWidth: regular,
      metrics: StylePanelMetrics.regular,
      horizontallyScrollable: false,
    );
  }

  final compact = stylePanelContentWidthFor(context, StylePanelMetrics.compact);
  final width = math.min(
    safeMax,
    math.max(safeMin, math.min(compact, safeMax)),
  );
  return StylePanelLayoutPlan(
    width: width,
    contentWidth: compact,
    metrics: StylePanelMetrics.compact,
    horizontallyScrollable: compact > width,
  );
}
