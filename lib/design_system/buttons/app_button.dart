import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

enum AppButtonVariant {
  primary,
  secondary,
  outlined,
  text,

  /// 次要/低强调操作：前景 `onSurfaceVariant`、背景透明，其余与 [text] 一致
  /// （对应 M3 默认 `IconButton` 的语义，避免普通图标按钮全部变成 primary 色）。
  neutral,
  danger,
}

enum AppButtonSize { small, medium, large }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.enabled = true,
    this.isLoading = false,
    this.semanticLabel,
    this.onPressed,
    this.onLongPress,
    this.onHover,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
  });

  final String label;
  final IconData? icon;
  final bool enabled;
  final bool isLoading;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHover;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final AppButtonVariant variant;
  final AppButtonSize size;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && !isLoading;
    final style = buildAppButtonStyle(
      context,
      variant,
      size: size,
      isLoading: isLoading,
    );
    final foreground = style.foregroundColor!.resolve(
      interactive ? <WidgetState>{} : <WidgetState>{WidgetState.disabled},
    );
    final content = Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isLoading)
            SizedBox.square(
              dimension: AppSpacing.tokens.s20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          else if (icon != null)
            Icon(icon, size: AppSpacing.tokens.s20),
          if (isLoading || icon != null) SizedBox(width: AppSpacing.tokens.s8),
          Flexible(child: Text(label)),
        ],
      ),
    );

    final button = switch (variant) {
      AppButtonVariant.primary ||
      AppButtonVariant.secondary ||
      AppButtonVariant.danger =>
        FilledButton(
          onPressed: interactive ? onPressed : null,
          onLongPress: interactive ? onLongPress : null,
          onHover: onHover,
          onFocusChange: onFocusChange,
          focusNode: focusNode,
          autofocus: autofocus,
          style: style,
          child: content,
        ),
      AppButtonVariant.outlined => OutlinedButton(
          onPressed: interactive ? onPressed : null,
          onLongPress: interactive ? onLongPress : null,
          onHover: onHover,
          onFocusChange: onFocusChange,
          focusNode: focusNode,
          autofocus: autofocus,
          style: style,
          child: content,
        ),
      AppButtonVariant.text || AppButtonVariant.neutral => TextButton(
          onPressed: interactive ? onPressed : null,
          onLongPress: interactive ? onLongPress : null,
          onHover: onHover,
          onFocusChange: onFocusChange,
          focusNode: focusNode,
          autofocus: autofocus,
          style: style,
          child: content,
        ),
    };

    return button;
  }
}

ButtonStyle buildAppButtonStyle(
  BuildContext context,
  AppButtonVariant variant, {
  AppButtonSize size = AppButtonSize.medium,
  bool isLoading = false,
  bool iconOnly = false,
}) {
  final colors = Theme.of(context).colorScheme;
  final transparent = colors.surface.withValues(alpha: 0);
  final background = switch (variant) {
    AppButtonVariant.primary => colors.primary,
    AppButtonVariant.secondary => colors.secondaryContainer,
    AppButtonVariant.outlined ||
    AppButtonVariant.text ||
    AppButtonVariant.neutral =>
      transparent,
    AppButtonVariant.danger => colors.error,
  };
  final foreground = switch (variant) {
    AppButtonVariant.primary => colors.onPrimary,
    AppButtonVariant.secondary => colors.onSecondaryContainer,
    AppButtonVariant.outlined || AppButtonVariant.text => colors.primary,
    AppButtonVariant.neutral => colors.onSurfaceVariant,
    AppButtonVariant.danger => colors.onError,
  };
  final disabledBackground = switch (variant) {
    AppButtonVariant.outlined ||
    AppButtonVariant.text ||
    AppButtonVariant.neutral =>
      transparent,
    _ => colors.onSurface.withValues(alpha: 0.12),
  };
  final minimumHeight = switch (size) {
    AppButtonSize.small => AppSpacing.tokens.s48,
    AppButtonSize.medium => AppSpacing.tokens.s48 + AppSpacing.tokens.s4,
    AppButtonSize.large => AppSpacing.tokens.s48 + AppSpacing.tokens.s8,
  };
  final padding = iconOnly
      ? AppSpacing.all8
      : switch (size) {
          AppButtonSize.small => AppSpacing.horizontal16,
          AppButtonSize.medium => AppSpacing.horizontal20,
          AppButtonSize.large => AppSpacing.horizontal24,
        };

  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll<Size>(
      Size(AppSpacing.tokens.s48, minimumHeight),
    ),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(padding),
    tapTargetSize: MaterialTapTargetSize.padded,
    shape: WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: iconOnly ? AppRadius.pill : AppRadius.border12,
      ),
    ),
    mouseCursor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
    ),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return isLoading ? background : disabledBackground;
      }
      if (states.contains(WidgetState.pressed)) {
        return background.withValues(alpha: 0.88);
      }
      return background;
    }),
    foregroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled) && !isLoading) {
        return colors.onSurface.withValues(alpha: 0.38);
      }
      return foreground;
    }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return transparent;
      if (states.contains(WidgetState.pressed)) {
        return foreground.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered)) {
        return foreground.withValues(alpha: 0.08);
      }
      if (states.contains(WidgetState.focused)) {
        return foreground.withValues(alpha: 0.10);
      }
      return transparent;
    }),
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused) &&
          !states.contains(WidgetState.disabled)) {
        return BorderSide(color: foreground, width: 2);
      }
      if (variant == AppButtonVariant.outlined) {
        return BorderSide(
          color: states.contains(WidgetState.disabled)
              ? colors.outlineVariant
              : colors.outline,
        );
      }
      return BorderSide.none;
    }),
  );
}
