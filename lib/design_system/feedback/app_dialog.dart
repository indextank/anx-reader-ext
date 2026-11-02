import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/feedback/app_feedback.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.content,
    this.actions,
  });

  final String title;
  final Widget content;
  final List<Widget>? actions;

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
    bool isDangerous = false,
    String? dangerDescription,
    Future<void> Function()? onConfirm,
  }) {
    if (isDangerous &&
        (dangerDescription == null || dangerDescription.trim().isEmpty)) {
      throw ArgumentError.value(
        dangerDescription,
        'dangerDescription',
        'A dangerous confirmation must explain its consequences.',
      );
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _AppConfirmationDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        isDangerous: isDangerous,
        dangerDescription: dangerDescription,
        onConfirm: onConfirm,
      ),
    ).then((result) => result ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(title),
      titleTextStyle: textTheme.titleLarge,
      content: content,
      contentTextStyle: textTheme.bodyMedium,
      contentPadding: AppSpacing.all24,
      actions: actions,
      actionsPadding: AppSpacing.symmetric(horizontal: 16, vertical: 8),
      actionsOverflowDirection: VerticalDirection.down,
    );
  }
}

class _AppConfirmationDialog extends StatefulWidget {
  const _AppConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.isDangerous,
    required this.dangerDescription,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool isDangerous;
  final String? dangerDescription;
  final Future<void> Function()? onConfirm;

  @override
  State<_AppConfirmationDialog> createState() => _AppConfirmationDialogState();
}

class _AppConfirmationDialogState extends State<_AppConfirmationDialog> {
  bool _pending = false;
  bool _showError = false;

  Future<void> _confirm() async {
    if (!mounted || _pending) return;
    _pending = true;
    setState(() => _showError = false);
    try {
      await widget.onConfirm?.call();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _showError = true);
    } finally {
      _pending = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final errorColor = context.appTheme.colors.error;
    return PopScope(
      canPop: !_pending,
      child: AppDialog(
        title: widget.title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            if (widget.isDangerous) ...[
              SizedBox(height: AppSpacing.tokens.s12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_outlined,
                    size: AppSpacing.tokens.s24,
                    color: errorColor,
                  ),
                  SizedBox(width: AppSpacing.tokens.s8),
                  Expanded(
                    child: Text(
                      widget.dangerDescription!,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: errorColor),
                    ),
                  ),
                ],
              ),
            ],
            if (_showError) ...[
              SizedBox(height: AppSpacing.tokens.s12),
              AppInlineFeedback(
                message: l10n.commonActionFailed,
                onRetry: _confirm,
              ),
            ],
          ],
        ),
        actions: [
          AppButton(
            label: widget.cancelLabel ?? l10n.commonCancel,
            variant: AppButtonVariant.text,
            enabled: !_pending,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            label: widget.confirmLabel ?? l10n.commonConfirm,
            variant: widget.isDangerous
                ? AppButtonVariant.danger
                : AppButtonVariant.primary,
            isLoading: _pending,
            onPressed: _confirm,
          ),
        ],
      ),
    );
  }
}
