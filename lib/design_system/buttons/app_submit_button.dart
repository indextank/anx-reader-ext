import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/design_system/feedback/app_feedback.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';

enum AppSubmitFeedbackMode { snackBar, inline }

class AppSubmitButton extends StatefulWidget {
  const AppSubmitButton({
    super.key,
    required this.label,
    required this.onSubmit,
    this.icon,
    this.disabled = false,
    this.isLoading = false,
    this.semanticLabel,
    this.errorMessage,
    this.feedbackMode = AppSubmitFeedbackMode.snackBar,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final Future<void> Function()? onSubmit;
  final IconData? icon;
  final bool disabled;
  final bool isLoading;
  final String? semanticLabel;
  final String? errorMessage;
  final AppSubmitFeedbackMode feedbackMode;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<AppSubmitButton> createState() => _AppSubmitButtonState();
}

class _AppSubmitButtonState extends State<AppSubmitButton> {
  bool _pending = false;
  bool _showInlineError = false;

  Future<void> _submit() async {
    final submit = widget.onSubmit;
    if (!mounted ||
        _pending ||
        widget.disabled ||
        widget.isLoading ||
        submit == null) {
      return;
    }

    _pending = true;
    setState(() => _showInlineError = false);
    try {
      await submit();
    } catch (_) {
      if (mounted) {
        if (widget.feedbackMode == AppSubmitFeedbackMode.inline) {
          setState(() => _showInlineError = true);
        } else {
          AppFeedback.showError(
            context,
            message: widget.errorMessage ?? L10n.of(context).commonActionFailed,
            onRetry: _submit,
          );
        }
      }
    } finally {
      _pending = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final button = AppButton(
      label: widget.label,
      icon: widget.icon,
      enabled: !widget.disabled && widget.onSubmit != null,
      isLoading: widget.isLoading || _pending,
      semanticLabel: widget.semanticLabel,
      variant: widget.variant,
      size: widget.size,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onPressed: _submit,
    );
    if (widget.feedbackMode != AppSubmitFeedbackMode.inline ||
        !_showInlineError) {
      return button;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        SizedBox(height: AppSpacing.tokens.s8),
        AppInlineFeedback(
          message: widget.errorMessage ?? L10n.of(context).commonActionFailed,
          onRetry: _submit,
        ),
      ],
    );
  }
}
