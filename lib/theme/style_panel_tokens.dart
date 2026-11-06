import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// 阅读页「样式」面板专用的排版与文字样式令牌。
///
/// 该面板允许独立于软件设置页风格（需求约定），因此在此集中定义：
/// 间距/内边距常量 + 由当前 ThemeData 派生的统一文字样式，
/// 面板内任何 widget 不得再散落字号/字重/颜色字面量。
///
/// 常规形态遵循 8pt 栅格；[StylePanelMetrics.compact] 是窄屏/侧栏被压缩时的
/// 最小安全降级方案（压缩留白与图标间距，而不是换行/省略）。
class StylePanelTokens {
  StylePanelTokens._();

  // ---- 8pt 栅格间距（常规形态） ----

  /// 面板最外层内边距。
  static const EdgeInsets panelPadding =
      EdgeInsets.symmetric(horizontal: 16, vertical: 8);

  /// 分组容器仅保留垂直留白；水平对齐交给行内边距与 [childIndent]。
  static const EdgeInsets groupVerticalPadding =
      EdgeInsets.symmetric(vertical: 8);

  /// 主分组标题之下的子设置统一左缩进（16）。
  static const EdgeInsets childIndent = EdgeInsets.only(left: 16);

  /// 子分组标题（页眉设置/页脚设置/阅读信息等）的内边距。
  static const EdgeInsets subsectionHeaderPadding =
      EdgeInsets.only(left: 16, top: 8, bottom: 8);

  /// 子设置内容（滑杆行、下拉行等）的左缩进。
  static const EdgeInsets subsectionContentPadding = EdgeInsets.only(left: 16);

  /// 相邻设置行之间的垂直间距。
  static const double rowGap = 8;

  /// 分组之间的垂直间距。
  static const double sectionGap = 16;

  /// 相邻子设置组/子设置内容之间的垂直间距。
  static const double subsectionGap = 8;

  /// 分组标题上方/下方的留白。
  static const EdgeInsets sectionHeaderPadding =
      EdgeInsets.only(top: 8, bottom: 8);

  // ---- 固定尺寸 ----

  /// 滑杆行内图标+标签列的统一高度。
  static const double sliderLabelHeight = 40;

  /// 阅读信息等无图标滑杆行的标签列最小宽度。
  static const double sliderLabelMinWidth = 96;

  /// 单行安全兜底的最小可用宽度：低于该宽度时合并内容允许横向安全滚动。
  static const double minSingleLineFallbackWidth = 600;

  /// 面板内下拉框的统一宽度（行尾控件位）。
  static const double dropdownWidth = 184;

  /// 主题色卡行高度。
  static const double themeRowHeight = 48;

  // ---- 右侧面板宽度约束 ----

  /// 自适应宽度下限：保证最窄屏幕上控件仍可用。
  static const double minPanelWidth = 300;

  /// 自适应宽度上限占屏幕可用宽度的比例。
  static const double maxPanelWidthFactor = 0.72;

  /// 自适应宽度绝对上限（桌面宽屏保护）。
  static const double maxPanelWidthCap = 640;

  /// 供 [StylePanelTokens.maxPanelWidthCap] 等宽度计算引用的默认水平
  /// 安全留白（与 [AppSpacing.horizontal16] 对齐）。
  static const double horizontalSafeInset = 16;

  // ---- 文字样式（由 Theme 派生，集中管理） ----

  /// 一级分组标题：比正文更大、半粗、主色，形成明确的主标题层级。
  static TextStyle sectionTitle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.titleMedium ?? const TextStyle())
        .copyWith(fontWeight: FontWeight.w600)
        .apply(color: theme.colorScheme.onSurface);
  }

  /// 二级分组标题（页眉设置/页脚设置/阅读信息/代码高亮等）：
  /// 字号小于一级标题、半粗、次级色，形成子标题层级。
  static TextStyle subsectionTitle(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.titleSmall ?? const TextStyle())
        .copyWith(fontWeight: FontWeight.w600)
        .apply(color: theme.colorScheme.onSurfaceVariant);
  }

  /// 选项标签（滑杆行标签、下拉标签等正文级文字）。
  static TextStyle optionLabel(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodyMedium ?? const TextStyle())
        .apply(color: theme.colorScheme.onSurface);
  }

  /// 辅助说明（提示、空态文案等）。
  static TextStyle helper(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodySmall ?? const TextStyle())
        .apply(color: theme.colorScheme.onSurfaceVariant);
  }

  /// 数值与单位（如 "720px"、"12.0"）：小号半粗 + 等宽数字对齐。
  static TextStyle value(BuildContext context) {
    final theme = Theme.of(context);
    return (theme.textTheme.bodySmall ?? const TextStyle())
        .copyWith(fontWeight: FontWeight.w600)
        .apply(color: theme.colorScheme.onSurface)
        .merge(const TextStyle(fontFeatures: [FontFeature.tabularFigures()]));
  }
}

/// 样式面板的间距/密度度量。
///
/// 常规形态遵循 8pt 栅格；窄屏或右侧栏被压缩到无法容纳最长设置项时，
/// 使用 [compact] 压缩水平留白与图标/文字间距，保证设置项仍为单行。
@immutable
class StylePanelMetrics {
  const StylePanelMetrics({
    required this.panelPadding,
    required this.groupVerticalPadding,
    required this.childIndent,
    required this.subsectionHeaderPadding,
    required this.subsectionContentPadding,
    required this.sectionHeaderPadding,
    required this.tileContentPadding,
    required this.rowGap,
    required this.sectionGap,
    required this.subsectionGap,
    required this.labelGap,
    required this.sliderLeading,
    required this.segmentChrome,
    required this.tileLeading,
  });

  final EdgeInsets panelPadding;
  final EdgeInsets groupVerticalPadding;
  final EdgeInsets childIndent;
  final EdgeInsets subsectionHeaderPadding;
  final EdgeInsets subsectionContentPadding;
  final EdgeInsets sectionHeaderPadding;

  /// 单行设置项（SingleRowSettingTile / AppListTile）的默认水平内边距。
  final EdgeInsets tileContentPadding;

  final double rowGap;
  final double sectionGap;
  final double subsectionGap;

  /// 设置标签与行尾控件之间的间距（用于内容宽度测量）。
  final double labelGap;

  /// 滑杆行图标占位（图标 + 间距，用于内容宽度测量）。
  final double sliderLeading;

  /// 分段按钮单段的装饰宽度（内边距 + 图标 + 分隔，用于宽度测量）。
  final double segmentChrome;

  /// 单行 tile 前置图标占位（用于宽度测量）。
  final double tileLeading;

  /// 面板与行内边距合计（宽度测量用）。
  double get horizontalPaddingTotal =>
      panelPadding.horizontal + tileContentPadding.horizontal;

  static const StylePanelMetrics regular = StylePanelMetrics(
    panelPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    groupVerticalPadding: EdgeInsets.symmetric(vertical: 8),
    childIndent: EdgeInsets.only(left: 16),
    subsectionHeaderPadding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
    subsectionContentPadding: EdgeInsets.only(left: 16),
    sectionHeaderPadding: EdgeInsets.only(top: 8, bottom: 8),
    tileContentPadding: EdgeInsets.symmetric(horizontal: 16),
    rowGap: 8,
    sectionGap: 16,
    subsectionGap: 8,
    labelGap: 8,
    sliderLeading: 32,
    segmentChrome: 64,
    tileLeading: 40,
  );

  static const StylePanelMetrics compact = StylePanelMetrics(
    panelPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    groupVerticalPadding: EdgeInsets.symmetric(vertical: 8),
    childIndent: EdgeInsets.only(left: 8),
    subsectionHeaderPadding: EdgeInsets.only(left: 8, top: 8, bottom: 8),
    subsectionContentPadding: EdgeInsets.only(left: 8),
    sectionHeaderPadding: EdgeInsets.only(top: 8, bottom: 8),
    tileContentPadding: EdgeInsets.symmetric(horizontal: 8),
    rowGap: 8,
    sectionGap: 8,
    subsectionGap: 8,
    labelGap: 4,
    sliderLeading: 28,
    segmentChrome: 48,
    tileLeading: 32,
  );

  bool get isCompact => identical(this, compact);
}

/// 在样式面板子树内提供当前密度（常规/紧凑）。
class StylePanelDensity extends InheritedWidget {
  const StylePanelDensity({
    super.key,
    required this.metrics,
    required super.child,
  });

  final StylePanelMetrics metrics;

  static StylePanelMetrics of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<StylePanelDensity>()
          ?.metrics ??
      StylePanelMetrics.regular;

  @override
  bool updateShouldNotify(StylePanelDensity oldWidget) =>
      oldWidget.metrics != metrics;
}
