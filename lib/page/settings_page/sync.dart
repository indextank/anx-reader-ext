import 'dart:convert';
import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/database.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/sync_direction.dart';
import 'package:anx_reader/enums/sync_protocol.dart';
import 'package:anx_reader/enums/sync_trigger.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/sync.dart';
import 'package:anx_reader/service/sync/settings_sync_catalog.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/get_path/databases_path.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/utils/get_path/get_temp_dir.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/utils/save_file_to_download.dart';
import 'package:anx_reader/utils/sync_test_helper.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/widgets/settings/webdav_switch.dart';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';

const String _prefsBackupFileName = 'anx_shared_prefs.json';

class SyncSetting extends ConsumerStatefulWidget {
  const SyncSetting({
    super.key,
    this.pickBackupFile,
    this.importBackup,
    this.backupFileExists,
    this.showGlobalLoading,
    this.dismissGlobalLoading,
  })  : assert(showGlobalLoading == null || dismissGlobalLoading != null),
        assert(dismissGlobalLoading == null || showGlobalLoading != null);

  final Future<FilePickerResult?> Function()? pickBackupFile;
  final Future<void> Function(String filePath)? importBackup;
  final Future<bool> Function(File file)? backupFileExists;
  final void Function(String title)? showGlobalLoading;
  final void Function()? dismissGlobalLoading;

  @override
  ConsumerState<SyncSetting> createState() => _SyncSettingState();
}

class _SyncSettingState extends ConsumerState<SyncSetting> {
  bool _isExporting = false;
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppSafeArea(
      top: false,
      child: settingsSections(
        sections: [
          SettingsSection(
            title: Text(l10n.settingsSyncWebdav),
            tiles: [
              webdavSwitch(context, setState, ref),
              SettingsTile.navigation(
                title: Text(l10n.settingsSyncWebdav),
                leading: const Icon(Icons.cloud),
                value: Text(
                  Prefs().getSyncInfo(SyncProtocol.webdav)['url'] ?? 'Not set',
                ),
                onPressed: (context) {
                  showWebdavDialog(context, onSaved: () => setState(() {}));
                },
              ),
              CustomSettingsTile(
                child: Padding(
                  padding: AppSettingsBatchTokens.syncHelpPadding,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppButton(
                      label: l10n.settingsNarrateClickForHelp,
                      variant: AppButtonVariant.text,
                      onPressed: () async {
                        final launched = await launchUrl(
                          Uri.parse('https://anx.anxcye.com/docs/sync/webdav'),
                          mode: LaunchMode.externalApplication,
                        );
                        if (!launched && context.mounted) {
                          AppFeedback.showError(
                            context,
                            message: l10n.commonFailed,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
              SettingsTile.navigation(
                title: Text(l10n.settingsSyncWebdavSyncNow),
                leading: const Icon(Icons.sync_alt),
                enabled: Prefs().webdavStatus,
                onPressed: (context) => _chooseDirection(),
              ),
              SettingsTile.switchTile(
                title: Text(l10n.webdavOnlyWifi),
                leading: const Icon(Icons.wifi),
                initialValue: Prefs().onlySyncWhenWifi,
                onToggle: (value) {
                  setState(() => Prefs().onlySyncWhenWifi = value);
                },
              ),
              SettingsTile.switchTile(
                title: Text(l10n.settingsSyncCompletedToast),
                leading: const Icon(Icons.notifications),
                initialValue: Prefs().syncCompletedToast,
                onToggle: (value) {
                  setState(() => Prefs().syncCompletedToast = value);
                },
              ),
              SettingsTile.switchTile(
                title: Text(l10n.settingsSyncAutoSync),
                leading: const Icon(Icons.sync),
                initialValue: Prefs().autoSync,
                enabled: Prefs().webdavStatus,
                onToggle: (value) {
                  setState(() => Prefs().autoSync = value);
                },
              ),
              SettingsTile.navigation(
                title: Text(l10n.restoreBackup),
                leading: const Icon(Icons.restore),
                onPressed: (context) {
                  ref.read(syncProvider.notifier).showBackupManagementDialog();
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.settingsSyncAppSettingsTitle),
            tiles: [
              SettingsTile.switchTile(
                title: Text(l10n.settingsSyncAppSettingsTitle),
                description: Text(l10n.settingsSyncAppSettingsHint),
                leading: const Icon(Icons.settings_suggest_outlined),
                initialValue: Prefs().settingsSyncEnabled,
                enabled: Prefs().webdavStatus,
                onToggle: (value) {
                  setState(() => Prefs().settingsSyncEnabled = value);
                },
              ),
              ...SettingsSyncCategory.values.map((category) {
                final excluded = Prefs().settingsSyncExcludedCategories;
                return SettingsTile.switchTile(
                  title: Text(_settingsSyncCategoryLabel(context, category)),
                  leading: Icon(_settingsSyncCategoryIcon(category)),
                  initialValue: !excluded.contains(category.name),
                  enabled: Prefs().webdavStatus && Prefs().settingsSyncEnabled,
                  onToggle: (value) {
                    setState(() {
                      final list = [...Prefs().settingsSyncExcludedCategories];
                      if (value) {
                        list.remove(category.name);
                      } else {
                        list.add(category.name);
                      }
                      Prefs().settingsSyncExcludedCategories = list;
                    });
                  },
                );
              }),
            ],
          ),
          SettingsSection(
            title: Text(l10n.exportAndImport),
            tiles: [
              SettingsTile.navigation(
                title: Text(l10n.exportAndImportExport),
                leading: const Icon(Icons.cloud_upload),
                enabled: !_isExporting && !_isImporting,
                onPressed: (context) => exportData(),
              ),
              SettingsTile.navigation(
                title: Text(l10n.exportAndImportImport),
                leading: const Icon(Icons.cloud_download),
                enabled: !_isExporting && !_isImporting,
                onPressed: (context) => importData(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _chooseDirection() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _SyncDirectionDialog(ref: ref),
    );
  }

  void _showDataDialog(String title) {
    final showLoading = widget.showGlobalLoading;
    if (showLoading != null) {
      showLoading(title);
      return;
    }
    SmartDialog.show(
      builder: (context) => AppDialog(
        title: title,
        content: const Center(child: AppLoadingIndicator()),
      ),
    );
  }

  void _dismissDataDialog() {
    final dismissLoading = widget.dismissGlobalLoading;
    if (dismissLoading != null) {
      dismissLoading();
    } else {
      SmartDialog.dismiss();
    }
  }

  Future<void> exportData() async {
    AnxLog.info('exportData: start');
    if (_isExporting || _isImporting || !mounted) return;
    setState(() => _isExporting = true);
    _showDataDialog(L10n.of(context).exporting);
    try {
      final prefsBackupFile = await _createPrefsBackupFile();
      final token = RootIsolateToken.instance!;
      final zipPath = await compute(createZipFile, {
        'token': token,
        'prefsBackupFilePath': prefsBackupFile.path,
      });
      final file = File(zipPath);
      if (await file.exists()) {
        final now = DateTime.now();
        final fileName =
            'AnxReader-Backup-${now.year}-${now.month}-${now.day}-v3.zip';
        final filePath = await saveFileToDownload(
          sourceFilePath: file.path,
          fileName: fileName,
          mimeType: 'application/zip',
        );
        await file.delete();
        if (!mounted) return;
        if (filePath != null) {
          AnxLog.info('exportData: Saved to: $filePath');
          AppFeedback.showSuccess(
            context,
            message: L10n.of(context).exportTo(filePath),
          );
        } else {
          AnxLog.info('exportData: Cancelled');
          AppFeedback.showInfo(
            context,
            message: L10n.of(context).commonCanceled,
          );
        }
      }
    } catch (e) {
      AnxLog.info('exportData: failed: $e');
      if (mounted) {
        AppFeedback.showError(
          context,
          onRetry: () => exportData(),
        );
      }
    } finally {
      _dismissDataDialog();
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> importData() async {
    AnxLog.info('importData: start');
    if (_isExporting || _isImporting || !mounted) return;
    setState(() => _isImporting = true);
    var loadingShown = false;
    try {
      final result = await (widget.pickBackupFile?.call() ??
          FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['zip'],
          ));
      if (result == null || !mounted) return;
      final filePath = result.files.single.path;
      if (filePath == null) {
        AppFeedback.showError(
          context,
          message: L10n.of(context).importCannotGetFilePath,
        );
        return;
      }
      final zipFile = File(filePath);
      final fileExists =
          await (widget.backupFileExists?.call(zipFile) ?? zipFile.exists());
      if (!fileExists) {
        if (!mounted) return;
        AppFeedback.showError(
          context,
          message: L10n.of(context).importCannotGetFilePath,
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await AppDialog.confirm(
        context,
        title: L10n.of(context).exportAndImportImport,
        message: filePath,
        isDangerous: true,
        dangerDescription: L10n.of(context).importSuccessRestartApp,
      );
      if (!confirmed || !mounted) return;
      _showDataDialog(L10n.of(context).importing);
      loadingShown = true;
      final importBackup = widget.importBackup;
      final pathSeparator = Platform.pathSeparator;
      final extractPath = importBackup == null
          ? '${(await getAnxTempDir()).path}${pathSeparator}anx_reader_import'
          : '';
      try {
        if (importBackup != null) {
          await importBackup(filePath);
        } else {
          await Directory(extractPath).create(recursive: true);
          await compute(extractZipFile, {
            'zipFilePath': zipFile.path,
            'destinationPath': extractPath,
          });
          final docPath = await getAnxDocumentsPath();
          _copyDirectorySync(
            Directory('$extractPath${pathSeparator}file'),
            getFileDir(path: docPath),
          );
          _copyDirectorySync(
            Directory('$extractPath${pathSeparator}cover'),
            getCoverDir(path: docPath),
          );
          _copyDirectorySync(
            Directory('$extractPath${pathSeparator}font'),
            getFontDir(path: docPath),
          );
          _copyDirectorySync(
            Directory('$extractPath${pathSeparator}bgimg'),
            getBgimgDir(path: docPath),
          );
          DBHelper.close();
          _copyDirectorySync(
            Directory('$extractPath${pathSeparator}databases'),
            await getAnxDataBasesDir(),
          );
          DBHelper().initDB();
          await _restorePrefsFromBackup(extractPath);
        }
        AnxLog.info('importData: import success');
        if (mounted) {
          AppFeedback.showSuccess(
            context,
            message: L10n.of(context).importSuccessRestartApp,
          );
        }
      } catch (e) {
        AnxLog.info('importData: error while unzipping or copying files: $e');
        if (mounted) {
          AppFeedback.showError(
            context,
            message: L10n.of(context).importFailed(e.toString()),
            onRetry: importData,
          );
        }
      } finally {
        if (extractPath.isNotEmpty && await Directory(extractPath).exists()) {
          await Directory(extractPath).delete(recursive: true);
        }
      }
    } catch (e) {
      AnxLog.info('importData: failed: $e');
      if (mounted) AppFeedback.showError(context, onRetry: importData);
    } finally {
      if (loadingShown) _dismissDataDialog();
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _copyDirectorySync(Directory source, Directory destination) {
    if (!source.existsSync()) return;
    if (destination.existsSync()) destination.deleteSync(recursive: true);
    destination.createSync(recursive: true);
    for (final entity in source.listSync(recursive: false)) {
      final newPath = destination.path +
          Platform.pathSeparator +
          path.basename(entity.path);
      if (entity is File) {
        entity.copySync(newPath);
      } else if (entity is Directory) {
        _copyDirectorySync(entity, Directory(newPath));
      }
    }
  }
}

class _SyncDirectionDialog extends StatefulWidget {
  const _SyncDirectionDialog({required this.ref});

  final WidgetRef ref;

  @override
  State<_SyncDirectionDialog> createState() => _SyncDirectionDialogState();
}

class _SyncDirectionDialogState extends State<_SyncDirectionDialog> {
  bool _pending = false;
  SyncDirection? _failedDirection;

  Future<void> _sync(SyncDirection direction) async {
    if (_pending) return;
    setState(() {
      _pending = true;
      _failedDirection = null;
    });
    try {
      await Sync().syncData(
        direction,
        widget.ref,
        trigger: SyncTrigger.manual,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _failedDirection = direction);
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return PopScope(
      canPop: !_pending,
      child: AppDialog(
        title: l10n.webdavChoose_Sources,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_failedDirection != null)
              AppInlineFeedback(
                message: l10n.commonActionFailed,
                onRetry: () => _sync(_failedDirection!),
              ),
          ],
        ),
        actions: [
          AppButton(
            label: l10n.webdavUpload,
            enabled: !_pending,
            isLoading: _pending,
            onPressed: () => _sync(SyncDirection.upload),
          ),
          AppButton(
            label: l10n.webdavDownload,
            enabled: !_pending,
            isLoading: _pending,
            onPressed: () => _sync(SyncDirection.download),
          ),
        ],
      ),
    );
  }
}

Future<String> createZipFile(Map<String, dynamic> params) async {
  final token = params['token'] as RootIsolateToken;
  final prefsBackupFile = File(params['prefsBackupFilePath'] as String);
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final date =
      '${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
  final zipPath = '${(await getAnxTempDir()).path}/AnxReader-Backup-$date.zip';
  final docPath = await getAnxDocumentsPath();
  final directoryList = [
    getFileDir(path: docPath),
    getCoverDir(path: docPath),
    getFontDir(path: docPath),
    getBgimgDir(path: docPath),
    if (!AnxPlatform.isOhos) await getAnxDataBasesDir(),
    prefsBackupFile,
  ];
  AnxLog.info('exportData: directoryList: $directoryList');
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);
  if (AnxPlatform.isOhos) {
    final dbDir = await getAnxDataBasesDir();
    final dbFile = File('${dbDir.path}/app_database.db');
    if (await dbFile.exists()) {
      await encoder.addFile(dbFile, 'databases/app_database.db');
    }
  } else {
    final dbDir = await getAnxDataBasesDir();
    await encoder.addDirectory(dbDir);
  }
  for (final dir in directoryList) {
    if (dir is Directory) {
      await encoder.addDirectory(dir);
    } else if (dir is File) {
      await encoder.addFile(dir);
    }
  }
  encoder.close();
  if (await prefsBackupFile.exists()) await prefsBackupFile.delete();
  return zipPath;
}

Future<void> extractZipFile(Map<String, String> params) async {
  final zipFilePath = params['zipFilePath']!;
  final destinationPath = params['destinationPath']!;
  final input = InputFileStream(zipFilePath);
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    extractArchiveToDiskSync(archive, destinationPath);
    archive.clearSync();
  } finally {
    await input.close();
  }
}

Future<File> _createPrefsBackupFile() async {
  final tempDir = await getAnxTempDir();
  final backupFile = File('${tempDir.path}/$_prefsBackupFileName');
  final prefsMap = await Prefs().buildPrefsBackupMap();
  await backupFile.writeAsString(jsonEncode(prefsMap));
  return backupFile;
}

Future<bool> _restorePrefsFromBackup(String extractPath) async {
  final backupFile = File('$extractPath/$_prefsBackupFileName');
  if (!await backupFile.exists()) return false;
  try {
    final dynamic decoded = jsonDecode(await backupFile.readAsString());
    if (decoded is Map<String, dynamic>) {
      await Prefs().applyPrefsBackupMap(decoded);
      return true;
    }
    AnxLog.info('importData: prefs backup has unexpected format');
  } catch (e) {
    AnxLog.info('importData: failed to restore prefs backup: $e');
  }
  return false;
}

void showWebdavDialog(BuildContext context, {VoidCallback? onSaved}) {
  showDialog<void>(
    context: context,
    builder: (context) => _WebdavConfigDialog(onSaved: onSaved),
  );
}

class _WebdavConfigDialog extends StatefulWidget {
  const _WebdavConfigDialog({this.onSaved});

  final VoidCallback? onSaved;

  @override
  State<_WebdavConfigDialog> createState() => _WebdavConfigDialogState();
}

class _WebdavConfigDialogState extends State<_WebdavConfigDialog> {
  late final Map<String, dynamic> _webdavInfo;
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _webdavInfo = Prefs().getSyncInfo(SyncProtocol.webdav);
    _urlController = TextEditingController(text: _webdavInfo['url']);
    _usernameController = TextEditingController(text: _webdavInfo['username']);
    _passwordController = TextEditingController(text: _webdavInfo['password']);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    await SyncTestHelper.handleFullTestConnection(
      context,
      protocol: SyncProtocol.webdav,
      config: {
        'url': _urlController.text.trim(),
        'username': _usernameController.text,
        'password': _passwordController.text,
      },
    );
  }

  Future<void> _save() async {
    _webdavInfo['url'] = _urlController.text.trim();
    _webdavInfo['username'] = _usernameController.text;
    _webdavInfo['password'] = _passwordController.text;
    Prefs().setSyncInfo(SyncProtocol.webdav, _webdavInfo);
    SyncClientFactory.initializeCurrentClient();
    widget.onSaved?.call();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppDialog(
      title: l10n.settingsSyncWebdav,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
                controller: _urlController, label: l10n.settingsSyncWebdavUrl),
            Padding(
              padding: AppSpacing.only(top: 8, bottom: 12),
              child: Text(
                l10n.settingsSyncWebdavUrlHint,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            AppTextField(
              controller: _usernameController,
              label: l10n.settingsSyncWebdavUsername,
            ),
            SizedBox(height: AppSpacing.tokens.s12),
            AppTextField(
              controller: _passwordController,
              label: l10n.settingsSyncWebdavPassword,
              obscureText: true,
            ),
          ],
        ),
      ),
      actions: [
        AppSubmitButton(
          label: l10n.settingsSyncWebdavTestConnection,
          icon: Icons.wifi_find,
          variant: AppButtonVariant.text,
          feedbackMode: AppSubmitFeedbackMode.inline,
          onSubmit: _test,
        ),
        AppButton(
          label: l10n.commonCancel,
          variant: AppButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        AppSubmitButton(
          label: l10n.commonSave,
          variant: AppButtonVariant.text,
          feedbackMode: AppSubmitFeedbackMode.inline,
          onSubmit: _save,
        ),
      ],
    );
  }
}

String _settingsSyncCategoryLabel(
  BuildContext context,
  SettingsSyncCategory category,
) {
  final l10n = L10n.of(context);
  return switch (category) {
    SettingsSyncCategory.appearance => l10n.settingsSyncCategoryAppearance,
    SettingsSyncCategory.reading => l10n.settingsSyncCategoryReading,
    SettingsSyncCategory.tts => l10n.settingsSyncCategoryTts,
    SettingsSyncCategory.translate => l10n.settingsSyncCategoryTranslate,
    SettingsSyncCategory.ai => l10n.settingsSyncCategoryAi,
    SettingsSyncCategory.advanced => l10n.settingsSyncCategoryAdvanced,
  };
}

IconData _settingsSyncCategoryIcon(SettingsSyncCategory category) {
  return switch (category) {
    SettingsSyncCategory.appearance => Icons.palette_outlined,
    SettingsSyncCategory.reading => Icons.menu_book_outlined,
    SettingsSyncCategory.tts => Icons.record_voice_over_outlined,
    SettingsSyncCategory.translate => Icons.translate_outlined,
    SettingsSyncCategory.ai => Icons.auto_awesome_outlined,
    SettingsSyncCategory.advanced => Icons.tune_outlined,
  };
}
