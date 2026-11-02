import 'dart:io';
import 'dart:math';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/storege_info_model.dart';
import 'package:anx_reader/providers/storage_info.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/storage_migration.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StorageSettings extends ConsumerStatefulWidget {
  const StorageSettings({
    super.key,
    this.loadStoragePath,
    this.pickStorageDirectory,
    this.isStorageDirectoryEmpty,
    this.verifyStorageWritable,
    this.migrateStorage,
  });

  final Future<String> Function()? loadStoragePath;
  final Future<String?> Function()? pickStorageDirectory;
  final Future<bool> Function(String path)? isStorageDirectoryEmpty;
  final Future<void> Function(String path)? verifyStorageWritable;
  final Future<bool> Function({
    required String sourcePath,
    required String destinationPath,
    MigrationProgressCallback? onProgress,
  })? migrateStorage;

  @override
  ConsumerState<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends ConsumerState<StorageSettings>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _selectedNewPath;
  bool _isMigrating = false;
  bool _isSelectingPath = false;
  String _migrationCurrentItem = '';
  int _migrationProgress = 0;
  int _migrationTotal = 6;
  String? _currentStoragePath;
  bool _pathLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCurrentPath();
  }

  Future<void> _loadCurrentPath() async {
    setState(() => _pathLoadFailed = false);
    try {
      final path =
          await (widget.loadStoragePath?.call() ?? getAnxDocumentsPath());
      if (mounted) setState(() => _currentStoragePath = path);
    } catch (_) {
      if (mounted) setState(() => _pathLoadFailed = true);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectNewPath() async {
    if (_isSelectingPath) return;
    setState(() => _isSelectingPath = true);
    try {
      final result = await (widget.pickStorageDirectory?.call() ??
          FilePicker.platform.getDirectoryPath());
      if (result == null) return;
      final isEmpty = await (widget.isStorageDirectoryEmpty?.call(result) ??
          isDirectoryEmpty(result));
      if (!isEmpty) {
        if (mounted) {
          AppFeedback.showError(
            context,
            message: L10n.of(context).storagePathNotEmpty,
          );
        }
        return;
      }
      try {
        final verifyWritable = widget.verifyStorageWritable;
        if (verifyWritable != null) {
          await verifyWritable(result);
        } else {
          final testFile =
              File('$result${Platform.pathSeparator}.anx_permission_test');
          await testFile.writeAsString('test');
          await testFile.delete();
        }
      } catch (_) {
        if (mounted) {
          AppFeedback.showError(
            context,
            message: L10n.of(context).storagePathNoPermission,
          );
        }
        return;
      }
      if (mounted) setState(() => _selectedNewPath = result);
    } catch (_) {
      if (mounted) AppFeedback.showError(context, onRetry: _selectNewPath);
    } finally {
      if (mounted) setState(() => _isSelectingPath = false);
    }
  }

  Future<void> _startMigration() async {
    if (_isMigrating ||
        _selectedNewPath == null ||
        _currentStoragePath == null) {
      return;
    }
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.storageMigrateData,
      message: '$_currentStoragePath → $_selectedNewPath',
      confirmLabel: l10n.storageMigrateData,
      isDangerous: true,
      dangerDescription: l10n.storageMigrationFailed,
      onConfirm: () async {
        if (!mounted) return;
        setState(() {
          _isMigrating = true;
          _migrationProgress = 0;
          _migrationCurrentItem = '';
        });
        try {
          final success =
              await (widget.migrateStorage ?? performStorageMigration)(
            sourcePath: _currentStoragePath!,
            destinationPath: _selectedNewPath!,
            onProgress: (currentItem, progress, total) {
              if (!mounted) return;
              setState(() {
                _migrationCurrentItem = currentItem;
                _migrationProgress = progress;
                _migrationTotal = total;
              });
            },
          );
          if (!mounted) return;
          if (success) {
            Prefs().customStoragePath = _selectedNewPath;
            setState(() {
              _currentStoragePath = _selectedNewPath;
              _selectedNewPath = null;
            });
            AppFeedback.showSuccess(
              context,
              message: l10n.storageMigrationSuccess,
            );
          } else {
            throw StateError('Storage migration failed');
          }
        } finally {
          if (mounted) setState(() => _isMigrating = false);
        }
      },
    );
  }

  Future<void> _resetToDefaultPath() async {
    final defaultPath = await getDefaultStoragePath();
    if (_currentStoragePath == defaultPath || !mounted) return;
    setState(() => _selectedNewPath = defaultPath);
  }

  Future<void> _refreshStorage() async {
    ref.invalidate(storageInfoProvider);
    await ref.read(storageInfoProvider.future);
  }

  Future<void> _clearCache() async {
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.storageClearCache,
      message: l10n.storageCacheFile,
      confirmLabel: l10n.commonConfirm,
      isDangerous: true,
      dangerDescription: l10n.storageClearCache,
      onConfirm: () async {
        final success =
            await ref.read(storageInfoProvider.notifier).clearCache();
        if (!success) throw StateError('Cache clearing failed');
        ref.invalidate(storageInfoProvider);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final storageInfoAsync = ref.watch(storageInfoProvider);
    return AppSafeArea(
      top: false,
      child: settingsSections(
        sections: [
          SettingsSection(
            title: Text(l10n.storageInfo),
            tiles: [
              CustomSettingsTile(
                child: AppAsyncValue<StorageInfoModel>(
                  value: storageInfoAsync,
                  onRetry: _refreshStorage,
                  dataBuilder: (context, info) => Column(
                    children: [
                      AppListTile(
                        title: l10n.storageTotalSize,
                        trailing: Text(info.totalSizeStr),
                      ),
                      AppListTile(
                        title: l10n.storageDatabaseFile,
                        trailing: Text(info.databaseSizeStr),
                      ),
                      AppListTile(
                        title: l10n.storageLogFile,
                        trailing: Text(info.logSizeStr),
                      ),
                      AppListTile(
                        title: l10n.storageCacheFile,
                        trailing: AppButton(
                          label:
                              '${l10n.storageClearCache} ${info.cacheSizeStr}',
                          onPressed: _clearCache,
                        ),
                      ),
                      AppListTile(
                        title: l10n.storageDataFile,
                        trailing: Text(info.dataFilesSizeStr),
                      ),
                      Padding(
                        padding: AppSpacing.only(
                          left: AppSettingsBatchTokens.storageDataIndent,
                        ),
                        child: Column(
                          children: [
                            AppListTile(
                              title: l10n.storageBookFile,
                              trailing: Text(info.booksSizeStr),
                            ),
                            AppListTile(
                              title: l10n.storageCoverFile,
                              trailing: Text(info.coverSizeStr),
                            ),
                            AppListTile(
                              title: l10n.storageFontFile,
                              trailing: Text(info.fontSizeStr),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (AnxPlatform.isWindows) _buildLocationSection(),
          SettingsSection(
            title: Text(l10n.storageDataFileDetails),
            tiles: [
              CustomSettingsTile(
                child: Padding(
                  padding: AppSpacing.all16,
                  child: Column(
                    children: [
                      TabBar(
                        controller: _tabController,
                        tabs: [
                          Tab(
                              text: l10n.storageBookFile,
                              icon: const Icon(Icons.book)),
                          Tab(
                              text: l10n.storageCoverFile,
                              icon: const Icon(Icons.image)),
                          Tab(
                            text: l10n.storageFontFile,
                            icon: const Icon(Icons.font_download),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).size.height -
                            MediaQuery.of(context).padding.top -
                            MediaQuery.of(context).padding.bottom -
                            kToolbarHeight -
                            AppSettingsBatchTokens.storageDetailsHeightOffset,
                        child: AppAsyncValue<StorageInfoModel>(
                          value: storageInfoAsync,
                          onRetry: _refreshStorage,
                          dataBuilder: (context, info) => TabBarView(
                            controller: _tabController,
                            children: [
                              DataFilesDetailTab(
                                title: l10n.storageBookFile,
                                icon: Icons.book,
                                listFiles: ref
                                    .read(storageInfoProvider.notifier)
                                    .listBookFiles(),
                                onRetry: () => ref
                                    .read(storageInfoProvider.notifier)
                                    .listBookFiles(),
                                ref: ref,
                              ),
                              DataFilesDetailTab(
                                title: l10n.storageCoverFile,
                                icon: Icons.image,
                                listFiles: ref
                                    .read(storageInfoProvider.notifier)
                                    .listCoverFiles(),
                                onRetry: () => ref
                                    .read(storageInfoProvider.notifier)
                                    .listCoverFiles(),
                                ref: ref,
                              ),
                              DataFilesDetailTab(
                                title: l10n.storageFontFile,
                                icon: Icons.font_download,
                                listFiles: ref
                                    .read(storageInfoProvider.notifier)
                                    .listFontFiles(),
                                onRetry: () => ref
                                    .read(storageInfoProvider.notifier)
                                    .listFontFiles(),
                                showDelete: true,
                                ref: ref,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  SettingsSection _buildLocationSection() {
    final l10n = L10n.of(context);
    return SettingsSection(
      title: Text(l10n.storageCustomLocation),
      tiles: [
        CustomSettingsTile(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_pathLoadFailed)
                AppErrorState(onRetry: _loadCurrentPath)
              else ...[
                AppListTile(
                  title: l10n.storageCurrentPath,
                  subtitle: _currentStoragePath ?? l10n.commonLoading,
                ),
                if (_selectedNewPath != null)
                  AppListTile(
                    title: l10n.storageNewPath,
                    subtitle: _selectedNewPath,
                    trailing: AppIconButton(
                      icon: Icons.close,
                      tooltip: l10n.commonCancel,
                      onPressed: () => setState(() => _selectedNewPath = null),
                    ),
                  ),
                Padding(
                  padding: AppSpacing.all16,
                  child: Wrap(
                    spacing: AppSpacing.tokens.s8,
                    runSpacing: AppSpacing.tokens.s8,
                    children: [
                      if (_selectedNewPath == null)
                        AppButton(
                          label: l10n.storageSelectPath,
                          isLoading: _isSelectingPath,
                          onPressed: _selectNewPath,
                        )
                      else
                        AppButton(
                          label: l10n.storageMigrateData,
                          isLoading: _isMigrating,
                          onPressed: _startMigration,
                        ),
                      if (Prefs().customStoragePath != null &&
                          _selectedNewPath == null)
                        AppButton(
                          label: l10n.storageResetPath,
                          variant: AppButtonVariant.outlined,
                          enabled: !_isMigrating,
                          onPressed: _resetToDefaultPath,
                        ),
                    ],
                  ),
                ),
                if (_isMigrating)
                  Padding(
                    padding: AppSpacing.horizontal16,
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          value: _migrationTotal > 0
                              ? _migrationProgress / _migrationTotal
                              : null,
                        ),
                        SizedBox(height: AppSpacing.tokens.s8),
                        Text(
                          _migrationCurrentItem.isNotEmpty
                              ? '${l10n.migrationCurrentItem}: $_migrationCurrentItem'
                              : l10n.migrationPreparing,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          '$_migrationProgress / $_migrationTotal',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        SizedBox(height: AppSpacing.tokens.s16),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class DataFilesDetailTab extends StatefulWidget {
  const DataFilesDetailTab({
    super.key,
    required this.title,
    required this.icon,
    required this.listFiles,
    this.onRetry,
    this.showDelete = false,
    required this.ref,
    this.deleteFile,
  });

  final String title;
  final IconData icon;
  final Future<List<File>> listFiles;
  final Future<List<File>> Function()? onRetry;
  final bool showDelete;
  final WidgetRef ref;
  final Future<void> Function(File file)? deleteFile;

  @override
  State<DataFilesDetailTab> createState() => _DataFilesDetailTabState();
}

class _DataFilesDetailTabState extends State<DataFilesDetailTab> {
  late Future<List<File>> _listFiles = widget.listFiles;

  @override
  void didUpdateWidget(DataFilesDetailTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.listFiles, widget.listFiles)) {
      _listFiles = widget.listFiles;
    }
  }

  Future<void> _retry() async {
    setState(() {
      _listFiles = widget.onRetry?.call() ?? widget.listFiles;
    });
    await _listFiles;
  }

  Future<void> _delete(File file) async {
    final l10n = L10n.of(context);
    await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: file.path.split(Platform.pathSeparator).last,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: file.path,
      onConfirm: () async {
        await (widget.deleteFile?.call(file) ??
            widget.ref.read(storageInfoProvider.notifier).deleteFile(file));
        final remaining = (await _listFiles)
            .where((item) => item.path != file.path)
            .toList(growable: false);
        if (!mounted) return;
        setState(() {
          _listFiles = widget.onRetry?.call() ?? Future.value(remaining);
        });
        widget.ref.invalidate(storageInfoProvider);
        await _listFiles;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<File>>(
      future: _listFiles,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(onRetry: _retry);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: AppLoadingIndicator());
        }
        final files = [...(snapshot.data ?? <File>[])]
          ..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
        if (files.isEmpty) {
          return AppEmptyState(
            message: widget.title,
            actionLabel: L10n.of(context).commonRefresh,
            onAction: _retry,
          );
        }
        return ListView.builder(
          itemCount: files.length,
          itemBuilder: (context, index) {
            final file = files[index];
            final canDelete = widget.showDelete &&
                !file.path.endsWith('SourceHanSerifSC-Regular.otf');
            return AppListTile(
              title: file.path.split(Platform.pathSeparator).last,
              trailing: canDelete
                  ? AppIconButton(
                      icon: Icons.delete_outline,
                      tooltip: L10n.of(context).commonDelete,
                      onPressed: () => _delete(file),
                    )
                  : _FileSizeText(file: file),
            );
          },
        );
      },
    );
  }
}

class _FileSizeText extends StatefulWidget {
  const _FileSizeText({required this.file});

  final File file;

  @override
  State<_FileSizeText> createState() => _FileSizeTextState();
}

class _FileSizeTextState extends State<_FileSizeText> {
  late Future<int> _length = widget.file.length();

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  Future<void> _retry() async {
    setState(() => _length = widget.file.length());
    await _length;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _length,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppIconButton(
            icon: Icons.refresh,
            tooltip: L10n.of(context).commonRetry,
            onPressed: _retry,
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingIndicator(
            size: AppLoadingIndicatorSize.button,
          );
        }
        return Text(_formatSize(snapshot.data!));
      },
    );
  }
}
