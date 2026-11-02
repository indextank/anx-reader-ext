import 'dart:io';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/utils/get_path/log_file.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// 日志级别胶囊的背景/前景配对（保证双亮度对比度 ≥ 4.5:1）。
({Color background, Color foreground}) logLevelColors(
  BuildContext context,
  Level level,
) {
  final colors = context.appTheme.colors;
  final scheme = Theme.of(context).colorScheme;
  if (level == Level.SEVERE) {
    return (background: colors.error, foreground: colors.onError);
  }
  if (level == Level.WARNING) {
    return (background: colors.warning, foreground: colors.onWarning);
  }
  return (
    background: scheme.surfaceContainerHighest,
    foreground: scheme.onSurfaceVariant,
  );
}

class LogPage extends StatefulWidget {
  const LogPage({super.key, this.loadLogFile, this.readLogLines});

  final Future<File> Function()? loadLogFile;
  final Future<List<String>> Function(File file)? readLogLines;

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  List<String> logs = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {
    if (_isLoading && logs.isNotEmpty) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final logFile = await (widget.loadLogFile?.call() ?? getLogFile());
      final loaded =
          await (widget.readLogLines?.call(logFile) ?? logFile.readAsLines());
      if (!mounted) return;
      setState(() => logs = loaded.reversed.toList());
    } catch (e) {
      AnxLog.info('LogPage: failed to read log file: $e');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsAdvancedLog),
        actions: [
          AppIconButton(
            icon: Icons.refresh,
            tooltip: l10n.commonRefresh,
            isLoading: _isLoading,
            onPressed: initData,
          ),
          PopupMenuButton<String>(
            enabled: !_isExporting,
            onSelected: (action) {
              if (action == 'clear') {
                clearLog();
              } else if (action == 'export') {
                exportLog();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    const Icon(Icons.delete),
                    SizedBox(width: AppSpacing.tokens.s12),
                    Text(l10n.settingsAdvancedLogClearLog),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    const Icon(Icons.file_upload_outlined),
                    SizedBox(width: AppSpacing.tokens.s12),
                    Text(l10n.settingsAdvancedLogExportLog),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: AppSafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && logs.isEmpty) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_loadFailed) {
      return AppErrorState(onRetry: initData);
    }
    if (logs.isEmpty) {
      return AppEmptyState(
        message: L10n.of(context).settingsAdvancedLog,
        actionLabel: L10n.of(context).commonRefresh,
        onAction: initData,
      );
    }
    return ListView(
      children: [for (final log in logs) logItem(log, context)],
    );
  }

  Future<void> clearLog() async {
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.settingsAdvancedLogClearLog,
      message: l10n.settingsAdvancedLogClearLog,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: l10n.settingsAdvancedLogClearLog,
      onConfirm: () async {
        AnxLog.clear();
        logs = [];
        await initData();
      },
    );
  }

  Future<void> exportLog() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final logFile = await (widget.loadLogFile?.call() ?? getLogFile());
      final fileName =
          'AnxReader-Log-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}.txt';
      final filePath = await saveFileToDownload(
        bytes: await logFile.readAsBytes(),
        fileName: fileName,
        mimeType: 'text/plain',
      );
      if (!mounted) return;
      if (filePath == null) {
        AppFeedback.showInfo(context, message: L10n.of(context).commonCanceled);
      } else {
        AppFeedback.showSuccess(
          context,
          message: L10n.of(context).exportTo(filePath),
        );
      }
    } catch (e) {
      AnxLog.info('LogPage: failed to export log file: $e');
      if (mounted) {
        AppFeedback.showError(context, onRetry: exportLog);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}

Widget logItem(String logStr, BuildContext context) {
  final log = AnxLog.parse(logStr);
  final levelColors = logLevelColors(context, log.level);
  return SelectionArea(
    child: Padding(
      padding: AppSpacing.all20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: AppSettingsBatchTokens.logLevelPadding,
            decoration: BoxDecoration(
              color: levelColors.background,
              borderRadius: AppRadius.pill,
            ),
            child: Text(
              log.level.name,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: levelColors.foreground,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Text(log.time.toString()),
          SizedBox(height: AppSpacing.tokens.s4),
          Text(log.message),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: L10n.of(context).commonCopy,
              variant: AppButtonVariant.text,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: logStr));
              },
            ),
          ),
          const Divider(),
        ],
      ),
    ),
  );
}
