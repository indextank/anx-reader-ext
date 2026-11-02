import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/page/settings_page/developer/developer_options_page.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/check_update.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/widgets/settings/link_icon.dart';
import 'package:anx_reader/widgets/settings/show_donate_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsx_plus/iconsx_plus.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:url_launcher/url_launcher.dart';

class About extends StatelessWidget {
  const About({
    super.key,
    this.leadingColor = false,
  });

  final bool leadingColor;

  @override
  Widget build(BuildContext context) {
    return AppListTile(
      title: L10n.of(context).appAbout,
      leading: Icon(
        Icons.info_outline,
        color: leadingColor ? Theme.of(context).colorScheme.primary : null,
      ),
      onTap: openAboutDialog,
    );
  }
}

const int _developerUnlockTapThreshold = 7;
int _developerUnlockTapCount = 0;
Timer? _developerUnlockResetTimer;

void _handleDeveloperUnlockTap(BuildContext context) {
  _developerUnlockTapCount++;
  _developerUnlockResetTimer?.cancel();
  _developerUnlockResetTimer =
      Timer(const Duration(seconds: 2), () => _developerUnlockTapCount = 0);

  final alreadyEnabled = Prefs().developerOptionsEnabled;
  if (_developerUnlockTapCount < _developerUnlockTapThreshold) {
    return;
  }

  _developerUnlockTapCount = 0;
  if (!alreadyEnabled) {
    Prefs().developerOptionsEnabled = true;
    AppFeedback.showSuccess(
      context,
      message: L10n.of(context).developerOptionsEnabled,
    );
  }

  final navigator = Navigator.of(context, rootNavigator: true);
  if (navigator.canPop()) {
    navigator.pop();
  }
  Future.microtask(_openDeveloperOptionsPage);
}

void _openDeveloperOptionsPage() {
  final BuildContext? navContext = navigatorKey.currentContext;
  if (navContext == null) return;
  Navigator.of(navContext).push(
    CupertinoPageRoute(
      fullscreenDialog: false,
      builder: (context) => const DeveloperOptionsPage(),
    ),
  );
}

Future<void> openAboutDialog() async {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  await showDialog<void>(
    context: context,
    builder: (context) => const _AboutDialog(),
  );
}

class _AboutDialog extends StatefulWidget {
  const _AboutDialog();

  @override
  State<_AboutDialog> createState() => _AboutDialogState();
}

class _AboutDialogState extends State<_AboutDialog> {
  String _version = '';
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    try {
      final pubspecContent = await rootBundle.loadString('pubspec.yaml');
      final version = Pubspec.parse(pubspecContent).version.toString();
      if (mounted) setState(() => _version = version);
    } catch (error) {
      AnxLog.warning('Failed to load app version: $error');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AppDialog(
      title: 'Anx',
      content: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AppSettingsTokens.aboutMaxWidth,
        ),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width *
              AppSettingsTokens.aboutWidthFactor,
          child: _isLoading
              ? const Padding(
                  padding: AppSpacing.all24,
                  child: Center(child: AppLoadingIndicator()),
                )
              : _loadFailed
                  ? AppErrorState(
                      message: l10n.commonLoadFailed,
                      onRetry: _loadVersion,
                    )
                  : _buildAboutContent(context),
        ),
      ),
    );
  }

  Widget _buildAboutContent(BuildContext context) {
    final l10n = L10n.of(context);
    final version = _version + (kDebugMode ? ' (debug)' : '');
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppListTile(
            title: l10n.appVersion,
            subtitle: version,
            onTap: () {
              Clipboard.setData(ClipboardData(text: _version));
              AppFeedback.showSuccess(
                context,
                message: l10n.notesPageCopied,
              );
              _handleDeveloperUnlockTap(context);
            },
          ),
          if (EnvVar.enableCheckUpdate)
            AppListTile(
              title: l10n.aboutCheckForUpdates,
              onTap: () => checkUpdate(true),
            ),
          if (EnvVar.enableDonation)
            AppListTile(
              title: l10n.appDonate,
              onTap: () => showDonateDialog(context),
            ),
          AppListTile(
            title: l10n.appLicense,
            onTap: () {
              showLicensePage(
                context: context,
                applicationName: 'Anx',
                applicationVersion: _version,
              );
            },
          ),
          AppListTile(
            title: l10n.appAuthor,
            onTap: () {
              launchUrl(
                Uri.parse(
                  'https://github.com/Anxcye/anx-reader/graphs/contributors',
                ),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          AppListTile(
            title: l10n.aboutPrivacyPolicy,
            onTap: () {
              launchUrl(
                Uri.parse('https://anx.anxcye.com/privacy'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          AppListTile(
            title: l10n.aboutTermsOfUse,
            onTap: () {
              launchUrl(
                Uri.parse('https://anx.anxcye.com/terms'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          AppListTile(
            title: l10n.aboutHelp,
            onTap: () {
              launchUrl(
                Uri.parse('https://anx.anxcye.com/docs'),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
          const Divider(),
          if (EnvVar.showBeian) ...[
            AppButton(
              label: '闽ICP备2025091402号-1A',
              variant: AppButtonVariant.text,
              onPressed: () {
                launchUrl(
                  Uri.parse('https://beian.miit.gov.cn/'),
                  mode: LaunchMode.externalApplication,
                );
              },
            ),
            const Divider(),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                linkIcon(
                  icon: Icon(
                    IonIcons.earth,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  url: 'https://anx.anxcye.com',
                  mode: LaunchMode.externalApplication,
                ),
                linkIcon(
                  icon: Icon(
                    IonIcons.logo_github,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  url: 'https://github.com/Anxcye/anx-reader',
                  mode: LaunchMode.externalApplication,
                ),
                if (EnvVar.showTelegramLink)
                  linkIcon(
                    icon: Icon(
                      Icons.telegram,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    url: 'https://t.me/AnxReader',
                    mode: LaunchMode.externalApplication,
                  ),
                linkIcon(
                  icon: Image.asset(
                    'assets/images/xiaohongshu.png',
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  url:
                      'https://www.xiaohongshu.com/user/profile/5d403f3e00000000100151ff',
                  mode: LaunchMode.externalApplication,
                ),
                linkIcon(
                  icon: Padding(
                    padding: AppSpacing.all4,
                    child: Image.asset(
                      'assets/images/qq.png',
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  url:
                      'http://qm.qq.com/cgi-bin/qm/qr?_wv=1027&k=8BYItJOMz4RCQJoHAAei7FV-nGB0iT8O&authKey=MD6a7gI%2FENiMr32rQRTLx2BpzTaa1wO9Qfmhx9ETcaLS%2FdcOFeptvVH9FWfvUpL2&noverify=0&group_code=1042905699',
                  mode: LaunchMode.externalApplication,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
