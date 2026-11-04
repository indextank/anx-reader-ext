import 'package:flutter/material.dart';

import 'app_spacing.dart';

/// 阅读页「样式」面板专用的紧凑排版与文字样式令牌。
///
/// 该面板允许独立于软件设置页风格（需求约定），因此在此集中定义：
/// 间距/内边距常量 + 由当前 ThemeData 派生的统一文字样式，
/// 面板内任何 widget 不得再散落字号/字重/颜色字面量。
class StylePanelTokens {
  StylePanelTokens._();

  // ---- 间距（紧凑档） ----

  /// 分组内容的水平内边距。
  static const EdgeInsets groupPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 2);

  /// 面板最外层水平内边距（垂直方向交给分组间 [sectionGap]）。
  static const EdgeInsets panelPadding =
      EdgeInsets.symmetric(horizontal: 12, vertical: 4);

  /// 相邻设置行之间的垂直间距。
  static const double rowGap = 4;

  /// 分组之间的垂直间距（替代旧的 Divider + 大留白）。
  static const double sectionGap = 8;

  /// 分组标题上方/下方的留白。
  static const EdgeInsets sectionHeaderPadding =
      EdgeInsets.only(top: 6, bottom: 2);

  /// 滑杆行内图标+标签列的统一高度。
  static const double sliderLabelHeight = 40;

  /// 面板内下拉框的统一宽度（行尾控件位）。
  static const double dropdownWidth = 184;

  /// 主题色卡行高度（原 56）。
  static const double themeRowHeight = 48;

  // ---- 右侧面板宽度约束 ----

  /// 自适应宽度下限：保证最窄屏幕上控件仍可用。
  static const double minPanelWidth = 300;

  /// 自适应宽度上限占屏幕可用宽度的比例。
  static const double maxPanelWidthFactor = 0.72;

  /// 自适应宽度绝对上限（桌面宽屏保护）。
  static const double maxPanelWidthCap = 640;

  // ---- 文字样式（由 Theme 派生，集中管理） ----

  /// 分组标题：小号、半粗、次级色。
  static TextStyle sectionTitle(BuildContext context) {
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

  /// 供 [StylePanelTokens.maxPanelWidthCap] 等宽度计算引用的默认水平
  /// 安全留白（与 [AppSpacing.horizontal16] 对齐）。
  static const double horizontalSafeInset = 16;
}
