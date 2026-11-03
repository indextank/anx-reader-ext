import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';

class ReadingToolbar extends StatelessWidget {
  const ReadingToolbar({
    super.key,
    required this.title,
    required this.onBack,
    required this.onToc,
    required this.actions,
  });

  static const double _singleRowMinWidth = 760;

  final String title;
  final VoidCallback onBack;
  final VoidCallback onToc;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    final backTooltip = MaterialLocalizations.of(context).backButtonTooltip;
    final navigation = [
      AppIconButton(
        icon: Icons.toc,
        tooltip: L10n.of(context).readingContents,
        onPressed: onToc,
      ),
      AppIconButton(
        icon: Icons.arrow_back,
        tooltip: backTooltip,
        semanticLabel: backTooltip,
        onPressed: onBack,
      ),
    ];
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _singleRowMinWidth) {
          return AppBar(
            automaticallyImplyLeading: false,
            leadingWidth: kMinInteractiveDimension * 2,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: navigation,
            ),
            title: titleText,
            actions: actions,
          );
        }

        return Material(
          color: appBarTheme.backgroundColor ?? theme.colorScheme.surface,
          child: AppSafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: kToolbarHeight,
                  child: Row(
                    children: [
                      ...navigation,
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: titleText,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: kToolbarHeight,
                  child: SingleChildScrollView(
                    key: const ValueKey('reading-toolbar-actions-scroll'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
