import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    this.icon,
    this.child,
    this.tooltip,
    this.semanticLabel,
    this.enabled = true,
    this.isLoading = false,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.variant = AppButtonVariant.text,
  }) : assert(icon != null || child != null);

  final IconData? icon;
  final Widget? child;
  final String? tooltip;
  final String? semanticLabel;
  final bool enabled;
  final bool isLoading;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final AppButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && !isLoading;
    final style = buildAppButtonStyle(
      context,
      variant,
      size: AppButtonSize.small,
      isLoading: isLoading,
      iconOnly: true,
    );
    final foreground = style.foregroundColor!.resolve(
      interactive ? <WidgetState>{} : <WidgetState>{WidgetState.disabled},
    );

    return Focus(
      onFocusChange: onFocusChange,
      skipTraversal: true,
      includeSemantics: false,
      child: IconButton(
        onPressed: interactive ? onPressed : null,
        onLongPress: interactive ? onLongPress : null,
        onHover: onHover,
        focusNode: focusNode,
        autofocus: autofocus,
        tooltip: tooltip,
        iconSize: AppSpacing.tokens.s24,
        style: style,
        icon: Semantics(
          label: semanticLabel,
          excludeSemantics: semanticLabel != null,
          child: isLoading
              ? SizedBox.square(
                  dimension: AppSpacing.tokens.s20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : child ?? Icon(icon),
        ),
      ),
    );
  }
}
