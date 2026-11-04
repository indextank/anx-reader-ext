import 'package:flutter/material.dart';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/widgets/reading_page/panel_width.dart';

/// 样式面板内容宽度计算：按“最宽选项行 = 标签宽度 + 控件固有宽度”
/// 解析地推导面板所需宽度（任务要求：先测量所有选项标签与控件在
/// 最宽状态下的固有宽度，取最大值加上统一内边距）。
///
/// 纯函数核心 [computeStylePanelContentWidth] 不依赖 BuildContext，
/// 可独立单元测试；[stylePanelRowSpecs] 从 l10n 收集当前语言的全部
/// 行规格（含横排/竖排两套标签，切换写作方向不影响宽度结论）。
class _RowSpec {
  const _RowSpec.label(this.label, {required this.controlWidth})
      : segments = null;

  const _RowSpec.segments(
    this.label, {
    required this.segments,
  }) : controlWidth = 0;

  /// 行首标签（滑杆名 / 单行 tile 标题 / 下拉字段名），可空串。
  final String? label;

  /// 分段按钮各段标签（与 [controlWidth] 互斥）。
  final List<String>? segments;

  /// 行尾控件固有宽度（滑杆最小轨道、开关、下拉框等）。
  final double controlWidth;
}

/// 控件固有宽度常量（Material 3 量级，集中定义便于调整与测试）。
class StylePanelControlMetrics {
  const StylePanelControlMetrics._();

  /// 单段分段的装饰宽度（左右内边距 + 24dp 图标 + 段间分隔）。
  static const double segmentChrome = 64;

  /// 滑杆最小可用轨道（含 Slider 自身水平内边距）。
  static const double sliderTrack = 132;

  /// 行尾开关宽度。
  static const double switchWidth = 52;

  /// 行尾下拉框（对齐方式）宽度令牌。
  static const double dropdown = StylePanelTokens.dropdownWidth;

  /// 下拉字段（字体/翻页方式）最小可用宽度。
  static const double dropdownField = 176;

  /// 主题色卡横向列表最小宽度。
  static const double themeRow = 260;

  /// 标签与行尾控件之间的间距。
  static const double labelGap = 12;

  /// 滑杆行图标占位（24dp 图标 + 间距）。
  static const double sliderLeading = 32;

  /// 单行 tile 前置图标占位。
  static const double tileLeading = 40;
}

/// 收集当前语言下面板所有行的宽度规格。
List<_RowSpec> stylePanelRowSpecs(L10n l10n) {
  return [
    // —— 样式（StyleWidget）——
    _RowSpec.label(
      l10n.readingPageFontSize,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.readingPageLineSpacing,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.readingPageParagraphSpacing,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.font,
      controlWidth: StylePanelControlMetrics.dropdownField,
    ),
    _RowSpec.label(
      l10n.readingPagePageTurningMethod,
      controlWidth: StylePanelControlMetrics.dropdownField,
    ),
    const _RowSpec.label('', controlWidth: StylePanelControlMetrics.themeRow),
    // —— 阅读（ReadingMoreSettings）——
    _RowSpec.segments(
      l10n.readingPageWritingDirection,
      segments: [
        l10n.readingPageWritingDirectionAuto,
        l10n.readingPageWritingDirectionVertical,
        l10n.readingPageWritingDirectionHorizontal,
      ],
    ),
    _RowSpec.segments(
      l10n.translationMode,
      segments: [
        l10n.readingPageOriginal,
        l10n.translationOnly,
        l10n.bilingual,
      ],
    ),
    _RowSpec.segments(
      l10n.readingPageColumnCount,
      segments: [
        l10n.readingPageAuto,
        l10n.readingPageSingle,
        l10n.readingPageDouble,
      ],
    ),
    _RowSpec.label(
      l10n.readingPageColumnThreshold,
      controlWidth: StylePanelControlMetrics.sliderTrack + 48,
    ),
    _RowSpec.segments(
      l10n.readingPageConvertChinese,
      segments: [
        l10n.readingPageOriginal,
        l10n.readingPageSimplified,
        l10n.readingPageTraditional,
      ],
    ),
    _RowSpec.segments(
      l10n.codeHighlightTheme,
      segments: [
        l10n.codeHighlightOff,
        l10n.codeHighlightLight,
        l10n.codeHighlightDark,
      ],
    ),
    // —— 样式（StyleSettings）——
    _RowSpec.label(
      l10n.useBookStyles,
      controlWidth: StylePanelControlMetrics.switchWidth,
    ),
    _RowSpec.label(
      l10n.readingPageIndent,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.readingPageVerticleMargin,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.readingPageSideMargin,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.readingPageLetterSpacing,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.readingPageFontWeight,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.headingFontSize,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.label(
      l10n.textAlignment,
      controlWidth: StylePanelControlMetrics.dropdown,
    ),
    // —— 其他（OtherSettings）——
    _RowSpec.label(
      l10n.readingPageScreenTimeout,
      controlWidth: StylePanelControlMetrics.sliderTrack,
    ),
    _RowSpec.segments(
      l10n.readingPagePageTurningMethod,
      segments: [
        l10n.pageTurnModeSimple,
        l10n.pageTurnModeCustom,
      ],
    ),
  ];
}

/// 纯函数核心：行规格 + 文本样式 + 缩放 → 内容宽度。
///
/// [labelStyle] 用于行首标签，[controlStyle] 用于分段/下拉文字；
/// [horizontalPaddingTotal] 为面板与分组的水平内边距合计。
double computeStylePanelContentWidth({
  required List<Object> rows,
  required TextStyle labelStyle,
  required TextStyle controlStyle,
  required TextScaler textScaler,
  required double horizontalPaddingTotal,
}) {
  var widest = 0.0;
  for (final row in rows) {
    if (row is! _RowSpec) continue;
    var width = 0.0;
    final label = row.label;
    if (label != null && label.isNotEmpty) {
      width += measureTextWidth(label, labelStyle, textScaler) +
          StylePanelControlMetrics.labelGap;
    }
    final segments = row.segments;
    if (segments != null) {
      for (final segment in segments) {
        width += measureTextWidth(segment, controlStyle, textScaler) +
            StylePanelControlMetrics.segmentChrome;
      }
    } else {
      width += row.controlWidth;
    }
    if (width > widest) widest = width;
  }
  // 滑杆行还有行首图标占位。
  return widest +
      StylePanelControlMetrics.sliderLeading +
      horizontalPaddingTotal;
}

/// 面板水平内边距合计（panelPadding + groupPadding 左右各两层）。
const double kStylePanelHorizontalPaddingTotal = 12.0 * 4;

/// 便捷入口：从 context 取当前语言、主题样式与缩放计算内容宽度。
double stylePanelContentWidth(BuildContext context) {
  final l10n = L10n.of(context);
  final theme = Theme.of(context);
  return computeStylePanelContentWidth(
    rows: stylePanelRowSpecs(l10n),
    labelStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
    controlStyle: theme.textTheme.labelLarge ?? const TextStyle(),
    textScaler: MediaQuery.textScalerOf(context),
    horizontalPaddingTotal: kStylePanelHorizontalPaddingTotal,
  );
}
