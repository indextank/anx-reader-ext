import 'dart:async';

import 'package:anx_reader/design_system/buttons/app_button.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class AppFeedback {
  AppFeedback._();

  static OverlayEntry? _toastEntry;
  static Timer? _toastTimer;
  static const _toastDuration = Duration(seconds: 2);

  static void showError(
    BuildContext context, {
    String? message,
    VoidCallback? onRetry,
    String? retryLabel,
  }) {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message ?? l10n.commonActionFailed),
        action: onRetry == null
            ? null
            : SnackBarAction(
                label: retryLabel ?? l10n.commonRetry,
                onPressed: onRetry,
              ),
      ),
    );
  }

  static void showSuccess(BuildContext context, {String? message}) {
    _showToast(
      context,
      message: message ?? L10n.of(context).commonSuccess,
      isSuccess: true,
    );
  }

  static void showInfo(BuildContext context, {required String message}) {
    _showToast(context, message: message, isSuccess: false);
  }

  static void _showToast(
    BuildContext context, {
    required String message,
    required bool isSuccess,
  }) {
    if (!context.mounted) return;
    final colors = context.appTheme.colors;
    final background = isSuccess ? colors.success : colors.info;
    final foreground = isSuccess ? colors.onSuccess : colors.onInfo;
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: foreground);
    final icon = isSuccess ? Icons.check_circle_outline : Icons.info_outline;
    _removeToast();

    final entry = OverlayEntry(
      builder: (overlayContext) {
        final keyboardInset = MediaQuery.viewInsetsOf(overlayContext).bottom;
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: AppSpacing.only(
                left: AppSpacing.tokens.s24,
                right: AppSpacing.tokens.s24,
                bottom: AppSpacing.tokens.s24 + keyboardInset,
              ),
              child: IgnorePointer(
                child: Material(
                  color: background,
                  borderRadius: AppRadius.border12,
                  child: Semantics(
                    liveRegion: true,
                    child: Padding(
                      padding: AppSpacing.symmetric(
                        horizontal: AppSpacing.tokens.s16,
                        vertical: AppSpacing.tokens.s12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: foreground),
                          SizedBox(width: AppSpacing.tokens.s12),
                          Flexible(
                            child: Text(message, style: textStyle),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    try {
      final overlay = Overlay.of(context, rootOverlay: true);
      _toastEntry = entry;
      overlay.insert(entry);
      _toastTimer = Timer(_toastDuration, _removeToast);
    } catch (error, stackTrace) {
      _removeToast();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'AppFeedback',
          context: ErrorDescription('while inserting an Overlay toast'),
        ),
      );
    }
  }

  static void _removeToast() {
    _toastTimer?.cancel();
    _toastTimer = null;
    final entry = _toastEntry;
    _toastEntry = null;
    if (entry == null || !entry.mounted) return;
    try {
      entry.remove();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'AppFeedback',
          context: ErrorDescription('while removing an Overlay toast'),
        ),
      );
    }
  }
}

class AppInlineFeedback extends StatefulWidget {
  const AppInlineFeedback({
    super.key,
    this.message,
    this.onRetry,
    this.retryLabel,
  });

  final String? message;
  final FutureOr<void> Function()? onRetry;
  final String? retryLabel;

  @override
  State<AppInlineFeedback> createState() => _AppInlineFeedbackState();
}

class _AppInlineFeedbackState extends State<AppInlineFeedback> {
  bool _pending = false;

  Future<void> _retry() async {
    final retry = widget.onRetry;
    if (!mounted || _pending || retry == null) return;
    _pending = true;
    setState(() {});
    try {
      await retry();
    } catch (_) {
    } finally {
      _pending = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: AppRadius.border12,
      child: Semantics(
        liveRegion: true,
        child: Padding(
          padding: AppSpacing.all12,
          child: Row(
            children: [
              Icon(Icons.error_outline, color: colors.onErrorContainer),
              SizedBox(width: AppSpacing.tokens.s8),
              Expanded(
                child: Text(
                  widget.message ?? l10n.commonActionFailed,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: colors.onErrorContainer),
                ),
              ),
              if (widget.onRetry != null)
                AppButton(
                  label: widget.retryLabel ?? l10n.commonRetry,
                  variant: AppButtonVariant.text,
                  isLoading: _pending,
                  onPressed: _retry,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
