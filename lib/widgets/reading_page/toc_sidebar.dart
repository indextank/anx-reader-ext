import 'dart:math' as math;

import 'package:anx_reader/design_system/design_system.dart';
import 'package:flutter/material.dart';

/// 固定目录侧栏的稳定 Key。
const tocPinnedSidebarKey = ValueKey('toc-pinned-sidebar');

/// 宽屏下固定侧栏的固定宽度。
const double tocSidebarFixedWidth = 320;

/// 侧栏宽度占可用宽度的上限：始终给右侧正文留出 >= 55% 的空间。
const double tocSidebarMaxScreenFraction = 0.45;

/// 窄屏按比例取宽时的系数。
const double tocSidebarNarrowFraction = 0.32;

/// 窄屏侧栏的最小宽度（受占比上限约束时可更窄）。
const double tocSidebarMinWidth = 200;

/// 达到该可用宽度即视为宽屏，使用固定宽度。
const double tocSidebarWideBreakpoint = 840;

/// 计算固定目录侧栏宽度（纯函数，便于单测）。
///
/// - 可用宽度 >= [tocSidebarWideBreakpoint]：固定宽度
///   [tocSidebarFixedWidth]；
/// - 窄屏：按 [tocSidebarNarrowFraction] 取值，限制在
///   [tocSidebarMinWidth] ~ [tocSidebarFixedWidth] 之间；
/// - 最后统一用 [tocSidebarMaxScreenFraction] 封顶，保证正文区域始终
///   存在（Row 内不会因侧栏过宽产生 RenderFlex 溢出）。
double resolveTocSidebarWidth(double availableWidth) {
  if (!availableWidth.isFinite || availableWidth <= 0) {
    return 0;
  }
  final maxByFraction = availableWidth * tocSidebarMaxScreenFraction;
  if (availableWidth >= tocSidebarWideBreakpoint) {
    return math.min(tocSidebarFixedWidth, maxByFraction);
  }
  final preferred = math.max(
    tocSidebarMinWidth,
    availableWidth * tocSidebarNarrowFraction,
  );
  return math.max(0, math.min(preferred, maxByFraction));
}

/// 固定在阅读页左侧的目录侧栏。
///
/// 只负责固定形态的外框（响应式宽度、阅读页表面色、安全区与右侧
/// 分隔线）；目录内容与固定开关由 [child] 自带，因此悬浮弹框与固定
/// 侧栏可以复用同一份目录 widget。
class TocSidebar extends StatelessWidget {
  const TocSidebar({
    super.key,
    required this.width,
    required this.child,
  });

  /// 已由 [resolveTocSidebarWidth] 解析、并夹在可用宽度内的侧栏宽度。
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background =
        theme.drawerTheme.backgroundColor ?? theme.canvasColor;
    return SizedBox(
      key: tocPinnedSidebarKey,
      width: width,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Material(
              color: background,
              child: AppSafeArea(child: child),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
        ],
      ),
    );
  }
}
