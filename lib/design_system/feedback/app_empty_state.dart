import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/buttons/app_icon_button.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String? title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = L10n.of(context);
    if (compact) {
      return Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: AppSpacing.tokens.s24, color: colors.onSurfaceVariant),
            SizedBox(width: AppSpacing.tokens.s8),
            Flexible(
              child: Text(
                title ?? l10n.commonEmpty,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            if (onAction != null)
              AppIconButton(
                icon: Icons.refresh,
                tooltip: actionLabel ?? l10n.commonRefresh,
                onPressed: onAction,
              ),
          ],
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.all24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: AppSpacing.tokens.s48, color: colors.onSurfaceVariant),
            SizedBox(height: AppSpacing.tokens.s16),
            Text(
              title ?? l10n.commonEmpty,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              SizedBox(height: AppSpacing.tokens.s8),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: AppSpacing.tokens.s24),
              AppButton(
                label: actionLabel!,
                variant: AppButtonVariant.outlined,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
