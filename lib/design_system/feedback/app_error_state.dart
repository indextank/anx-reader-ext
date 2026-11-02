import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/buttons/app_icon_button.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class AppErrorState extends StatefulWidget {
  const AppErrorState({
    super.key,
    this.title,
    this.message,
    this.icon = Icons.error_outline,
    this.onRetry,
    this.retryLabel,
    this.compact = false,
  });

  final String? title;
  final String? message;
  final IconData icon;
  final Future<void> Function()? onRetry;
  final String? retryLabel;
  final bool compact;

  @override
  State<AppErrorState> createState() => _AppErrorStateState();
}

class _AppErrorStateState extends State<AppErrorState> {
  bool _pending = false;
  bool _retryFailed = false;

  Future<void> _retry() async {
    final retry = widget.onRetry;
    if (!mounted || _pending || retry == null) return;
    _pending = true;
    setState(() => _retryFailed = false);
    try {
      await retry();
    } catch (_) {
      if (mounted) setState(() => _retryFailed = true);
    } finally {
      _pending = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    if (widget.compact) {
      return Center(
        child: AppIconButton(
          icon: widget.onRetry == null ? widget.icon : Icons.refresh,
          tooltip: widget.retryLabel ??
              (widget.onRetry == null
                  ? l10n.commonLoadFailed
                  : l10n.commonRetry),
          semanticLabel: '${l10n.commonLoadFailed} ${l10n.commonRetry}',
          isLoading: _pending,
          onPressed: widget.onRetry == null ? null : _retry,
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: AppSpacing.all24,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.icon,
              size: AppSpacing.tokens.s48,
              color: context.appTheme.colors.error,
            ),
            SizedBox(height: AppSpacing.tokens.s16),
            Text(
              widget.title ?? l10n.commonFailed,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.tokens.s8),
            Text(
              _retryFailed
                  ? l10n.commonActionFailed
                  : widget.message ?? l10n.commonLoadFailed,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (widget.onRetry != null) ...[
              SizedBox(height: AppSpacing.tokens.s24),
              AppButton(
                label: widget.retryLabel ?? l10n.commonRetry,
                variant: AppButtonVariant.outlined,
                isLoading: _pending,
                onPressed: _retry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
