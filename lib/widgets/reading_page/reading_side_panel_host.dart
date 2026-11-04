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
  });

  final double width;
  final double minWidth;
  final double maxWidth;
  final ValueChanged<double> onResize;
  final VoidCallback onResizeEnd;
  final VoidCallback onSwitchPosition;
  final VoidCallback onClose;
  final Widget child;

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
              Expanded(
                child: Column(
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
