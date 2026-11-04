import 'package:flutter/material.dart';

import 'package:anx_reader/theme/style_panel_tokens.dart';

/// 面板宽度解析纯函数：供右侧自适应面板与其它展现位置复用。
///
/// 规则：内容宽度落在 [minWidth, maxWidth] 区间内时按内容宽度取值
/// （保证最宽选项完整可见）；小于下限取下限；大于上限取上限
/// （由面板内部换行/纵向滚动降级，而非溢出）。
double resolvePanelWidth({
  required double intrinsicWidth,
  required double minWidth,
  required double maxWidth,
}) {
  assert(intrinsicWidth >= 0, 'intrinsicWidth must be non-negative');
  assert(minWidth <= maxWidth, 'minWidth must not exceed maxWidth');
  return intrinsicWidth.clamp(minWidth, maxWidth).toDouble();
}

/// 依据屏幕可用宽度推导右侧面板的宽度上限：
/// 屏幕比例因子与绝对上限取小，再扣除水平安全留白，且不低于下限。
double panelMaxWidthFor({
  required double availableWidth,
  double factor = StylePanelTokens.maxPanelWidthFactor,
  double cap = StylePanelTokens.maxPanelWidthCap,
  double minWidth = StylePanelTokens.minPanelWidth,
  double safeInset = StylePanelTokens.horizontalSafeInset,
}) {
  final byFactor = availableWidth * factor;
  final capped = byFactor < cap ? byFactor : cap;
  final withInset = capped - safeInset;
  return withInset < minWidth ? minWidth : withInset;
}

/// 用 TextPainter 测量单行文本在指定样式与缩放下的宽度（纯函数，
/// 供内容宽度计算与单元测试使用）。
double measureTextWidth(
  String text,
  TextStyle style,
  TextScaler textScaler,
) {
  if (text.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textScaler: textScaler,
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}
