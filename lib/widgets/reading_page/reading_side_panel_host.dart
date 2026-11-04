import 'dart:math' as math;

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

class ReadingSidePanelHost extends StatelessWidget {
  const ReadingSidePanelHost({
    super.key,
    required this.width,
    required this.minWidth,
    required this.maxWidth,
    required this.onResize,
    required this.onResizeEnd,
    required this.onSwitchPosition,
    required this.onClose,
    required this.child,
    this.adaptiveWidth = false,
    this.adaptiveResolvedWidth = 0,
  });

  final double width;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onSwitchPosition;
  final VoidCallback onClose;
  final Widget child;

  /// true 时宽度按 [adaptiveResolvedWidth]（由内容宽度解析而来，见
  /// style_panel_content_width.dart + resolvePanelWidth）取值，忽略
  /// [width] 并隐藏手动拖拽条；供样式面板按内容自适应。
  final bool adaptiveWidth;

  /// 解析后的自适应宽度（已夹在上下限内）。
  final double adaptiveResolvedWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final effectiveMaxWidth = math.max(
          0.0,
          math.min(maxWidth, availableWidth),
        );

        final body = Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIconButton(
                    onPressed: onSwitchPosition,
                    tooltip: L10n.of(context).aiShowAtBottom,
                    child: const Icon(Icons.arrow_downward),
                  ),
                  AppIconButton(
                    onPressed: onClose,
                    tooltip: L10n.of(context).close,
                    child: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(child: child),
          ],
        );

        if (adaptiveWidth) {
          // 内容自适应：宽度已由协调器按内容解析，这里再夹到
          // 当前可用宽度内（窄屏保护）。
          final effectiveAdaptive =
              adaptiveResolvedWidth.clamp(0.0, effectiveMaxWidth).toDouble();
          return SizedBox(
            key: const ValueKey('reading-side-panel-adaptive'),
            width: effectiveAdaptive,
            child: body,
          );
        }

        final effectiveMinWidth = math.min(minWidth, effectiveMaxWidth);
        final effectiveWidth =
            width.clamp(effectiveMinWidth, effectiveMaxWidth).toDouble();

        return SizedBox(
          width: effectiveWidth,
          child: Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) => onResize(details.delta.dx),
                onHorizontalDragEnd: (_) => onResizeEnd(),
                onHorizontalDragCancel: onResizeEnd,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: VerticalDivider(width: 2, thickness: 1),
                ),
              ),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
