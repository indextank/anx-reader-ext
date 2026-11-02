import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:flutter/material.dart';

enum PageTurningType {
  none,
  next,
  prev,
  menu,
}

Widget getPageTurningDiagram(
  BuildContext context,
  List<PageTurningType> types,
  List<int> iconPosition,
  bool selected,
  Function() onTap,
) {
  Color cellColor(PageTurningType type) => switch (type) {
        PageTurningType.next => AppReadingTokens.nextPageArea(context),
        PageTurningType.prev => AppReadingTokens.previousPageArea(context),
        PageTurningType.menu => AppReadingTokens.menuArea(context),
        PageTurningType.none => AppReadingTokens.inactiveArea(context),
      };

  return AppCard(
    onTap: onTap,
    padding: AppReadingTokens.compactPadding,
    borderRadius: AppReadingTokens.pageTurnRadius,
    color: selected
        ? Theme.of(context).colorScheme.secondaryContainer
        : Theme.of(context).colorScheme.surfaceContainer,
    child: SizedBox(
      width: AppReadingTokens.pageTurnDiagramWidth,
      height: AppReadingTokens.pageTurnDiagramWidth,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
        ),
        itemBuilder: (context, index) {
          return ColoredBox(
            color: cellColor(types[index]),
            child: Center(
              child: iconPosition.contains(index)
                  ? Icon(
                      index == iconPosition[0]
                          ? Icons.arrow_forward
                          : index == iconPosition[1]
                              ? Icons.arrow_back
                              : index == iconPosition[2]
                                  ? Icons.menu
                                  : null,
                      size: 10,
                    )
                  : null,
            ),
          );
        },
        itemCount: 9,
      ),
    ),
  );
}
