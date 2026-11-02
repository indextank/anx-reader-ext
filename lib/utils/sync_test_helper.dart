import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/service/sync/sync_connection_tester.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:flutter/material.dart';

class SyncTestHelper {
  /// Handle simple connection test (ping only)
  static Future<void> handleTestConnection(
    BuildContext context, {
    required SyncProtocol protocol,
    required Map<String, dynamic> config,
    VoidCallback? onTestStart,
    Function(bool success, String message)? onTestComplete,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(L10n.of(context).testingConnection),
          ],
        ),
      ),
    );

    onTestStart?.call();

    try {
      final result = await SyncConnectionTester.testConnection(
        protocol: protocol,
        config: config,
      );

      if (context.mounted) {
        Navigator.of(context).pop();
      }

      _showTestResult(navigatorKey.currentContext!, result);

      onTestComplete?.call(result.isSuccess, result.message);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      final result = SyncTestResult.failure(
          L10n.of(navigatorKey.currentContext!)
                  .unknownErrorWhenTestingConnection +
              e.toString());
      _showTestResult(navigatorKey.currentContext!, result);

      onTestComplete?.call(false, result.message);
    }
  }

  /// Handle full connection test (create, upload, download, delete)
  static Future<void> handleFullTestConnection(
    BuildContext context, {
    required SyncProtocol protocol,
    required Map<String, dynamic> config,
    VoidCallback? onTestStart,
    Function(bool success, String message)? onTestComplete,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text(L10n.of(context).testingConnection),
          ],
        ),
      ),
    );

    onTestStart?.call();

    try {
      final result = await SyncConnectionTester.testFullConnection(
        protocol: protocol,
        config: config,
      );

      if (context.mounted) {
        Navigator.of(context).pop();
      }

      _showTestResult(navigatorKey.currentContext!, result);

      onTestComplete?.call(result.isSuccess, result.message);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }

      final result = SyncTestResult.failure(
          L10n.of(navigatorKey.currentContext!)
                  .unknownErrorWhenTestingConnection +
              e.toString());
      _showTestResult(navigatorKey.currentContext!, result);

      onTestComplete?.call(false, result.message);
    }
  }

  static void _showTestResult(BuildContext context, SyncTestResult result) {
    if (result.isSuccess) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: context.appTheme.colors.success),
              SizedBox(width: AppSpacing.tokens.s8),
              Text(L10n.of(context).commonSuccess),
            ],
          ),
          content: Text(result.message),
          actions: [
            AppButton(
              label: L10n.of(context).commonOk,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error, color: context.appTheme.colors.error),
              SizedBox(width: AppSpacing.tokens.s8),
              Text(L10n.of(context).commonFailed),
            ],
          ),
          content: Text(result.message),
          actions: [
            AppButton(
              label: L10n.of(context).commonOk,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }
}
