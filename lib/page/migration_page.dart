import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/utils/get_path/macos_migration.dart';
import 'package:flutter/material.dart';

typedef MigrationCheckCallback = Future<MigrationCheckResult> Function();
typedef MigrationPerformCallback = Future<bool> Function({
  required String oldPath,
  required String newPath,
  required MigrationProgressCallback onProgress,
});

class MigrationPage extends StatefulWidget {
  final VoidCallback onMigrationComplete;
  final MigrationCheckCallback checkNeeded;
  final MigrationPerformCallback migrate;

  const MigrationPage({
    super.key,
    required this.onMigrationComplete,
    this.checkNeeded = checkMigrationNeeded,
    this.migrate = performMigration,
  });

  @override
  State<MigrationPage> createState() => _MigrationPageState();
}

class _MigrationPageState extends State<MigrationPage> {
  String _currentItem = '';
  int _progress = 0;
  int _total = 5;
  bool _isComplete = false;
  bool _hasFailed = false;
  bool _completionCalled = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startMigration();
  }

  void _complete() {
    if (!mounted || _completionCalled) return;
    _completionCalled = true;
    widget.onMigrationComplete();
  }

  Future<void> _startMigration() async {
    try {
      final checkResult = await widget.checkNeeded();
      if (!mounted) return;

      if (!checkResult.needsMigration) {
        _complete();
        return;
      }

      final success = await widget.migrate(
        oldPath: checkResult.oldPath!,
        newPath: checkResult.newPath!,
        onProgress: (currentItem, progress, total) {
          if (mounted) {
            setState(() {
              _currentItem = currentItem;
              _progress = progress;
              _total = total;
            });
          }
        },
      );
      if (!mounted) return;

      if (success) {
        setState(() {
          _isComplete = true;
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        _complete();
      } else {
        setState(() {
          _hasFailed = true;
          _errorMessage = 'Migration failed. Using original data location.';
        });
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        _complete();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasFailed = true;
        _errorMessage = e.toString();
      });
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      _complete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final statusColor = _isComplete
        ? context.appTheme.colors.success
        : _hasFailed
            ? context.appTheme.colors.error
            : theme.colorScheme.primary;

    return Scaffold(
      body: AppSafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: AppSpacing.all32,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isComplete
                      ? Icons.check_circle_outline
                      : _hasFailed
                          ? Icons.error_outline
                          : Icons.folder_copy_outlined,
                  size: AppMigrationTokens.statusIconSize,
                  color: statusColor,
                  semanticLabel: _isComplete
                      ? l10n.migrationComplete
                      : _hasFailed
                          ? l10n.migrationFailed
                          : l10n.migrationInProgress,
                ),
                SizedBox(height: AppSpacing.tokens.s24),
                Text(
                  _isComplete
                      ? l10n.migrationComplete
                      : _hasFailed
                          ? l10n.migrationFailed
                          : l10n.migrationInProgress,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: AppSpacing.tokens.s16),
                if (!_isComplete && !_hasFailed) ...[
                  Text(
                    l10n.migrationDoNotClose,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: AppSpacing.tokens.s32),
                  LinearProgressIndicator(
                    value: _total > 0 ? _progress / _total : null,
                    semanticsLabel: l10n.commonLoading,
                    semanticsValue: _total > 0
                        ? '${((_progress / _total) * 100).round()}%'
                        : null,
                  ),
                  SizedBox(height: AppSpacing.tokens.s16),
                  Text(
                    _currentItem.isNotEmpty
                        ? '${l10n.migrationCurrentItem}: $_currentItem'
                        : l10n.migrationPreparing,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: AppSpacing.tokens.s8),
                  Text(
                    '$_progress / $_total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_hasFailed && _errorMessage != null) ...[
                  SizedBox(height: AppSpacing.tokens.s16),
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: context.appTheme.colors.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
