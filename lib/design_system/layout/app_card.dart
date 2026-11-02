import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.all16,
    this.margin = AppSpacing.zero,
    this.borderRadius = AppRadius.border16,
    this.color,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final BorderRadius borderRadius;
  final Color? color;
  final bool enabled;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled &&
        (onTap != null || onLongPress != null || onSecondaryTap != null);
    return Card(
      color: color,
      margin: margin,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: context.appTheme.isEInk
            ? BorderSide(color: Theme.of(context).colorScheme.outline)
            : BorderSide.none,
      ),
      child: ConstrainedBox(
        constraints: interactive
            ? BoxConstraints(
                minWidth: AppSpacing.tokens.s48,
                minHeight: AppSpacing.tokens.s48,
              )
            : const BoxConstraints(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          onSecondaryTap: enabled ? onSecondaryTap : null,
          borderRadius: borderRadius,
          child: Semantics(
            label: semanticLabel,
            excludeSemantics: semanticLabel != null,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
