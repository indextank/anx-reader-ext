import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/md5_statistics.dart';
import 'package:anx_reader/page/changelog_screen.dart';
import 'package:anx_reader/page/onboarding_screen.dart';
import 'package:anx_reader/page/settings_page/search_engines.dart';
import 'package:anx_reader/page/settings_page/subpage/chapter_split_rules_page.dart';
import 'package:anx_reader/page/settings_page/subpage/log_page.dart';
import 'package:anx_reader/service/md5_service.dart';
import 'package:anx_reader/service/network/http_proxy_overrides.dart';
import 'package:anx_reader/service/sync/sync_client_factory.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AdvancedSetting extends StatefulWidget {
  const AdvancedSetting({
    super.key,
    this.loadMd5Statistics,
    this.testProxy,
  });

  final Future<MD5Statistics> Function()? loadMd5Statistics;
  final Future<bool> Function(String host, int port, String testUrl)? testProxy;

  @override
  State<AdvancedSetting> createState() => _AdvancedSettingState();
}

class _AdvancedSettingState extends State<AdvancedSetting> {
  MD5Statistics? _md5Stats;
  bool _md5Loading = true;
  bool _md5LoadFailed = false;
  bool _isCalculating = false;
  double _progress = 0.0;
  String _currentFile = '';

  @override
  void initState() {
    super.initState();
    _loadMd5Statistics();
  }

  Future<void> _loadMd5Statistics() async {
    setState(() {
      _md5Loading = true;
      _md5LoadFailed = false;
    });
    try {
      final stats = await (widget.loadMd5Statistics?.call() ??
          MD5Service.getMd5Statistics());
      if (!mounted) return;
      setState(() => _md5Stats = stats);
    } catch (_) {
      if (mounted) setState(() => _md5LoadFailed = true);
    } finally {
      if (mounted) setState(() => _md5Loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppSafeArea(
      top: false,
      child: settingsSections(
        sections: [
          SettingsSection(
            title: Text(l10n.eBookProcess),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.auto_stories_outlined),
                title: Text(l10n.chapterSplitting),
                onPressed: (_) {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => const ChapterSplitRulesPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.settingsAdvancedLog),
            tiles: [
              SettingsTile.switchTile(
                title: Text(l10n.settingsAdvancedClearLogWhenStart),
                leading: const Icon(Icons.delete_forever_outlined),
                initialValue: Prefs().clearLogWhenStart,
                onToggle: (value) {
                  Prefs().saveClearLogWhenStart(value);
                  setState(() {});
                },
              ),
              SettingsTile.navigation(
                leading: const Icon(Icons.bug_report),
                title: Text(l10n.settingsAdvancedLog),
                onPressed: onLogPressed,
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.md5Management),
            tiles: [
              if (_md5Loading && _md5Stats == null)
                const CustomSettingsTile(
                  child: Center(child: AppLoadingIndicator()),
                )
              else if (_md5LoadFailed && _md5Stats == null)
                CustomSettingsTile(
                  child: AppErrorState(onRetry: _loadMd5Statistics),
                )
              else if (_md5Stats != null)
                SettingsTile(title: _buildStatistics()),
              if (_isCalculating)
                SettingsTile(
                  leading: const Icon(Icons.calculate),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.md5Calculating),
                      SizedBox(height: AppSpacing.tokens.s8),
                      LinearProgressIndicator(value: _progress),
                      SizedBox(height: AppSpacing.tokens.s4),
                      Text(
                        '${(_progress * 100).toStringAsFixed(1)}% - $_currentFile',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                )
              else
                SettingsTile.navigation(
                  title: Text(l10n.md5CalculateMissing),
                  leading: const Icon(Icons.calculate),
                  onPressed: _calculateMd5,
                ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.settingsAdvancedJavascript),
            tiles: [
              SettingsTile.switchTile(
                title: Text(l10n.settingsAdvancedEnableJavascriptForEpub),
                leading: const Icon(Icons.code),
                initialValue: Prefs().enableJsForEpub,
                onToggle: (value) {
                  Prefs().enableJsForEpub = value;
                  setState(() {});
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.settingsAdvancedNetwork),
            tiles: [
              SettingsTile.switchTile(
                title: Text(l10n.settingsAdvancedHttpProxyEnabled),
                leading: const Icon(Icons.wifi_tethering),
                initialValue: Prefs().httpProxyEnabled,
                onToggle: (value) {
                  Prefs().httpProxyEnabled = value;
                  setState(() {});
                },
              ),
              SettingsTile.switchTile(
                title: Text(l10n.settingsAdvancedTrustUserCertificates),
                description:
                    Text(l10n.settingsAdvancedTrustUserCertificatesDesc),
                leading: const Icon(Icons.security),
                initialValue: Prefs().trustUserCertificates,
                onToggle: (value) {
                  Prefs().trustUserCertificates = value;
                  SyncClientFactory.initializeCurrentClient();
                  setState(() {});
                },
              ),
              SettingsTile.navigation(
                title: Text(l10n.settingsAdvancedHttpProxyConfig),
                leading: const Icon(Icons.http),
                value: Text(
                  Prefs().httpProxyHost.isEmpty
                      ? l10n.settingsAdvancedHttpProxyNotConfigured
                      : Prefs().httpProxyEnabled
                          ? '${Prefs().httpProxyHost}:${Prefs().httpProxyPort} (Test: ${Prefs().httpProxyTestUrl})'
                          : '${Prefs().httpProxyHost}:${Prefs().httpProxyPort}',
                ),
                onPressed: _showHttpProxyDialog,
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.searchManageEngines),
            tiles: [
              SettingsTile.navigation(
                leading: const Icon(Icons.search),
                title: Text(l10n.searchManageEngines),
                onPressed: (_) {
                  Navigator.of(context).push(
                    CupertinoPageRoute(
                      builder: (context) => const SearchEnginesSetting(),
                    ),
                  );
                },
              ),
            ],
          ),
          SettingsSection(
            title: Text(l10n.hints),
            tiles: [
              SettingsTile.navigation(
                title: Text(l10n.showAllHintsAgain),
                leading: const Icon(Icons.lightbulb_outline),
                onPressed: (_) {
                  Prefs().resetHints();
                  AppFeedback.showSuccess(
                    context,
                    message: l10n.allHintsWillBeShownAgain,
                  );
                },
              ),
              SettingsTile.navigation(
                title: Text(l10n.viewChangelog),
                leading: const Icon(Icons.update),
                onPressed: _showChangelog,
              ),
              SettingsTile.navigation(
                title: Text(l10n.viewOnboarding),
                leading: const Icon(Icons.menu_book_outlined),
                onPressed: _showOnboarding,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics() {
    final stats = _md5Stats!;
    final l10n = L10n.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.fingerprint),
        SizedBox(width: AppSpacing.tokens.s8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.md5Statistics),
              SizedBox(height: AppSpacing.tokens.s4),
              for (final text in [
                l10n.md5TotalBooks(stats.totalBooks),
                l10n.md5BooksWithMd5(stats.booksWithMd5),
                l10n.md5BooksWithoutMd5(stats.booksWithoutMd5),
                l10n.md5LocalFiles(stats.localFilesCount),
                l10n.md5LocalFilesWithoutMd5(stats.localFilesWithoutMd5),
              ])
                Text(text, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _calculateMd5(BuildContext context) async {
    if (_isCalculating) return;
    if (_md5Stats?.localFilesWithoutMd5 == 0) {
      AppFeedback.showInfo(
        context,
        message: L10n.of(context).md5NoCalculationNeeded,
      );
      return;
    }
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AppDialog(
        title: l10n.md5CalculateConfirmTitle,
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.md5CalculateConfirmContent),
              if (_md5Stats != null &&
                  _md5Stats!.localFilesWithoutMd5 <
                      _md5Stats!.booksWithoutMd5) ...[
                SizedBox(height: AppSpacing.tokens.s8),
                AppCard(
                  padding: AppSpacing.all8,
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                        size: AppSpacing.tokens.s16,
                      ),
                      SizedBox(width: AppSpacing.tokens.s8),
                      Expanded(
                        child: Text(
                          l10n.md5MissingFilesTip,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          AppButton(
            label: l10n.commonCancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppButton(
            label: l10n.commonConfirm,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _isCalculating = true;
      _progress = 0.0;
      _currentFile = '';
    });
    try {
      final booksToCalculate = await bookDao.getBooksWithoutMd5();
      final result = await MD5Service.batchCalculateMd5(
        booksToCalculate,
        onProgress: (current, total, currentFile) {
          if (!mounted) return;
          setState(() {
            _progress = total == 0 ? 0 : current / total;
            _currentFile = currentFile;
          });
        },
      );
      await _loadMd5Statistics();
      if (!mounted) return;
      await showDialog<void>(
        context: this.context,
        builder: (dialogContext) => AppDialog(
          title: l10n.md5CalculationComplete,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.md5CalculationResultCalculated(result.calculated)),
                Text(l10n.md5CalculationResultSkipped(result.skipped)),
                Text(l10n.md5CalculationResultFailed(result.failed)),
                if (result.missingFiles.isNotEmpty) ...[
                  SizedBox(height: AppSpacing.tokens.s8),
                  Text(
                    l10n.md5MissingFiles,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  ...result.missingFiles.take(5).map((file) => Text('• $file')),
                  if (result.missingFiles.length > 5)
                    Text(l10n.md5AndMore(result.missingFiles.length - 5)),
                ],
              ],
            ),
          ),
          actions: [
            AppButton(
              label: l10n.commonOk,
              variant: AppButtonVariant.text,
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(
          this.context,
          message: l10n.md5CalculationError(e.toString()),
          onRetry: () => _calculateMd5(this.context),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCalculating = false;
          _progress = 0.0;
          _currentFile = '';
        });
      }
    }
  }

  Future<void> _showHttpProxyDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _HttpProxyDialog(
        onSaved: () {
          if (mounted) setState(() {});
        },
        testProxy: widget.testProxy,
      ),
    );
  }
}

class _HttpProxyDialog extends StatefulWidget {
  const _HttpProxyDialog({required this.onSaved, this.testProxy});

  final VoidCallback onSaved;
  final Future<bool> Function(String host, int port, String testUrl)? testProxy;

  @override
  State<_HttpProxyDialog> createState() => _HttpProxyDialogState();
}

class _HttpProxyDialogState extends State<_HttpProxyDialog> {
  late final TextEditingController hostController;
  late final TextEditingController portController;
  late final TextEditingController testUrlController;

  @override
  void initState() {
    super.initState();
    hostController = TextEditingController(text: Prefs().httpProxyHost);
    portController =
        TextEditingController(text: Prefs().httpProxyPort.toString());
    testUrlController = TextEditingController(text: Prefs().httpProxyTestUrl);
  }

  @override
  void dispose() {
    hostController.dispose();
    portController.dispose();
    testUrlController.dispose();
    super.dispose();
  }

  String? _validatedHost() {
    var host = hostController.text.trim();
    final port = int.tryParse(portController.text.trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    final hostLower = host.toLowerCase();
    if (hostLower.startsWith('https://') ||
        hostLower.startsWith('socks5://') ||
        hostLower.startsWith('socks4://') ||
        hostLower.startsWith('socks://')) {
      return null;
    }
    if (hostLower.startsWith('http://')) host = host.substring(7);
    return host;
  }

  Future<void> _testConnection() async {
    final host = _validatedHost();
    final port = int.tryParse(portController.text.trim());
    final testUrl = testUrlController.text.trim();
    if (host == null || port == null || testUrl.isEmpty) {
      throw const FormatException('Invalid proxy configuration');
    }
    AppFeedback.showInfo(
      context,
      message: L10n.of(context).settingsAdvancedHttpProxyTesting,
    );
    final success = await (widget.testProxy?.call(host, port, testUrl) ??
        AnxHttpProxyOverrides.testProxy(host, port, testUrl));
    if (!success) throw StateError('Proxy test failed');
    if (mounted) {
      AppFeedback.showSuccess(
        context,
        message: L10n.of(context).settingsAdvancedHttpProxyTestSuccess,
      );
    }
  }

  Future<void> _save() async {
    final host = _validatedHost();
    final port = int.tryParse(portController.text.trim());
    if (host == null || port == null) {
      throw const FormatException('Invalid proxy configuration');
    }
    final testUrl = testUrlController.text.trim();
    Prefs().httpProxyHost = host;
    Prefs().httpProxyPort = port;
    Prefs().httpProxyTestUrl = testUrl.isEmpty ? 'https://google.com' : testUrl;
    widget.onSaved();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppDialog(
      title: l10n.settingsAdvancedHttpProxyConfig,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              controller: hostController,
              label: l10n.settingsAdvancedHttpProxyHost,
              hintText: l10n.settingsAdvancedHttpProxyHostHint,
            ),
            SizedBox(height: AppSpacing.tokens.s12),
            AppTextField(
              controller: portController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              label: l10n.settingsAdvancedHttpProxyPort,
              hintText: l10n.settingsAdvancedHttpProxyPortHint,
            ),
            SizedBox(height: AppSpacing.tokens.s12),
            AppTextField(
              controller: testUrlController,
              label: l10n.settingsAdvancedHttpProxyTestUrl,
            ),
          ],
        ),
      ),
      actions: [
        AppSubmitButton(
          label: l10n.settingsAdvancedHttpProxyTest,
          variant: AppButtonVariant.text,
          feedbackMode: AppSubmitFeedbackMode.inline,
          errorMessage: l10n.settingsAdvancedHttpProxyTestFailed,
          onSubmit: _testConnection,
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
          errorMessage: l10n.settingsAdvancedHttpProxyInvalidInput,
          onSubmit: _save,
        ),
      ],
    );
  }
}

Future<void> _showChangelog(BuildContext context) async {
  final currentVersion = await getAppVersion();
  if (!context.mounted) return;
  final lastVersion = Prefs().lastAppVersion ?? currentVersion;
  await showCupertinoSheet(
    context: navigatorKey.currentContext ?? context,
    scrollableBuilder: (sheetContext, scrollController) => ChangelogScreen(
      lastVersion: lastVersion,
      currentVersion: currentVersion,
      onComplete: () {
        Prefs().lastAppVersion = currentVersion;
        Navigator.pop(sheetContext);
      },
    ),
  );
}

Future<void> _showOnboarding(BuildContext context) async {
  final currentVersion = await getAppVersion();
  if (!context.mounted) return;
  await showCupertinoSheet(
    context: navigatorKey.currentContext ?? context,
    scrollableBuilder: (sheetContext, scrollController) => Scaffold(
      body: OnboardingScreen(
        onComplete: () {
          Prefs().lastAppVersion = currentVersion;
          Navigator.pop(sheetContext);
        },
      ),
    ),
  );
}

void onLogPressed(BuildContext context) {
  Navigator.push(
    context,
    CupertinoPageRoute(builder: (context) => const LogPage()),
  );
}
