import 'dart:io';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/theme/app_theme_extension.dart';
import 'package:anx_reader/utils/get_path/log_file.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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

/// 筛选分段控件中表示"ALL"的哨兵值（级别本身用 Level.name 字符串）。
const _kFilterAll = 'ALL';

class LogPage extends StatefulWidget {
  const LogPage({super.key, this.loadLogFile, this.readLogLines});

  final Future<File> Function()? loadLogFile;
  final Future<List<String>> Function(File file)? readLogLines;

  @override
  State<LogPage> createState() => _LogPageState();
}

/// 一条已解析的日志（保留原始行用于复制/导出）。
typedef LogEntryRecord = ({AnxLog log, String raw});

class _LogPageState extends State<LogPage> {
  List<LogEntryRecord> _entries = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isExporting = false;

  /// 当前级别筛选；null 表示 ALL（默认）。
  Level? _levelFilter;

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {
    if (_isLoading && _entries.isNotEmpty) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final logFile = await (widget.loadLogFile?.call() ?? getLogFile());
      final loaded =
          await (widget.readLogLines?.call(logFile) ?? logFile.readAsLines());
      if (!mounted) return;
      setState(() {
        _entries = [
          for (final line in loaded.reversed)
            (log: AnxLog.parse(line), raw: line),
        ];
        // 数据变化后当前筛选可能已无对应级别，回退到 ALL。
        if (_levelFilter != null &&
            !_entries.any((e) => e.log.level == _levelFilter)) {
          _levelFilter = null;
        }
      });
    } catch (e) {
      AnxLog.info('LogPage: failed to read log file: $e');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 按严重程度降序去重后的级别集合（用于筛选分段）。
  List<Level> get _availableLevels {
    final levels = <Level>{for (final e in _entries) e.log.level}.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return levels;
  }

  List<LogEntryRecord> get _filteredEntries => _levelFilter == null
      ? _entries
      : _entries.where((e) => e.log.level == _levelFilter).toList();

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
        bottom: _entries.isEmpty ? null : _buildFilterBar(context),
      ),
      body: AppSafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  /// 级别筛选栏：ALL（默认）+ 当前数据中出现的级别，横向可滚动。
  PreferredSizeWidget _buildFilterBar(BuildContext context) {
    final levels = _availableLevels;
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight * 0.7),
      child: SizedBox(
        height: kToolbarHeight * 0.7,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: AppSpacing.symmetric(
            horizontal: AppSpacing.tokens.s16,
            vertical: AppSpacing.tokens.s4,
          ),
          child: AnxSegmentedButton<String>(
            segments: [
              SegmentButtonItem(
                value: _kFilterAll,
                label: L10n.of(context).settingsAdvancedLogFilterAll,
              ),
              for (final level in levels)
                SegmentButtonItem(
                  value: level.name,
                  label: level.name,
                ),
            ],
            selected: {
              _levelFilter?.name ?? _kFilterAll,
            },
            onSelectionChanged: (selected) {
              final value = selected.first;
              setState(() {
                _levelFilter = value == _kFilterAll
                    ? null
                    : levels.firstWhere((l) => l.name == value);
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _entries.isEmpty) {
      return const Center(child: AppLoadingIndicator());
    }
    if (_loadFailed) {
      return AppErrorState(onRetry: initData);
    }
    if (_entries.isEmpty) {
      return AppEmptyState(
        message: L10n.of(context).settingsAdvancedLog,
        actionLabel: L10n.of(context).commonRefresh,
        onAction: initData,
      );
    }
    final entries = _filteredEntries;
    if (entries.isEmpty) {
      return AppEmptyState(
        message: L10n.of(context).settingsAdvancedLogNoMatch,
        actionLabel: L10n.of(context).settingsAdvancedLogFilterAll,
        onAction: () => setState(() => _levelFilter = null),
      );
    }
    return SelectionArea(
      child: ListView.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CompactLogTile(
              entry: entries[index],
              // 仅在首条或跨天时展示日期，进一步压缩纵向占用。
              showDate: index == 0 ||
                  entries[index - 1].log.time.day !=
                      entries[index].log.time.day,
            ),
            if (index < entries.length - 1)
              Divider(
                height: 1,
                indent: AppSpacing.tokens.s16,
                endIndent: AppSpacing.tokens.s16,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
          ],
        ),
      ),
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
        _entries = [];
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

/// 紧凑日志条目：一行头部（级别胶囊 + 时间 + 复制），下方消息正文。
class _CompactLogTile extends StatelessWidget {
  const _CompactLogTile({required this.entry, required this.showDate});

  final LogEntryRecord entry;
  final bool showDate;

  static final _timeFormat = DateFormat('HH:mm:ss');
  static final _dateTimeFormat = DateFormat('MM-dd HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final levelColors = logLevelColors(context, entry.log.level);
    return Padding(
      padding: AppSpacing.symmetric(
        horizontal: AppSpacing.tokens.s16,
        vertical: AppSpacing.tokens.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: AppSpacing.symmetric(
                  horizontal: AppSpacing.tokens.s8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: levelColors.background,
                  borderRadius: AppRadius.pill,
                ),
                child: Text(
                  entry.log.level.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: levelColors.foreground,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SizedBox(width: AppSpacing.tokens.s8),
              // 窄屏大字号下时间可收缩省略，避免头部行溢出。
              Expanded(
                child: Text(
                  (showDate ? _dateTimeFormat : _timeFormat)
                      .format(entry.log.time),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              AppIconButton(
                icon: Icons.copy,
                tooltip: l10n.commonCopy,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: entry.raw));
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            entry.log.message,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
