import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/utils/app_version.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/utils/log/common.dart';
import 'package:anx_reader/utils/toast/common.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> checkUpdate(bool manualCheck) async {
  if (!EnvVar.enableCheckUpdate) {
    return;
  }
  // if is today
  if (!manualCheck &&
      DateTime.now().difference(Prefs().lastShowUpdate) <
          const Duration(days: 1)) {
    return;
  }
  Prefs().lastShowUpdate = DateTime.now();

  BuildContext context = navigatorKey.currentContext!;
  // 在 await 之前取好依赖，避免跨异步间隙使用 BuildContext。
  final l10n = L10n.of(context);
  final navigator = Navigator.of(context);
  Response response;
  try {
    response = await Dio().get('https://api.anx.anxcye.com/api/info/latest');
  } catch (e) {
    if (manualCheck) {
      AnxToast.show(l10n.commonFailed);
    }
    AnxLog.severe('Update: Failed to check for updates $e');
    return;
  }
  String newVersion = response.data['version'].toString().substring(1);
  String currentVersion = (await getAppVersion()).split('+').first;
  AnxLog.info('Update: new version $newVersion');

  List<String> newVersionList = newVersion.split('.');
  List<String> currentVersionList = currentVersion.split('.');
  AnxLog.info(
      'Current version: $currentVersionList, New version: $newVersionList');
  bool needUpdate = false;
  for (int i = 0; i < newVersionList.length; i++) {
    int newVer = int.parse(newVersionList[i]);
    int curVer = int.parse(currentVersionList[i]);
    if (newVer > curVer) {
      needUpdate = true;
      break;
    } else if (newVer < curVer) {
      needUpdate = false;
      break;
    }
  }

  if (needUpdate) {
    if (manualCheck) {
      navigator.pop();
    }
    SmartDialog.show(
      builder: (BuildContext context) {
        final body =
            response.data['body'].toString().split('\n').skip(1).join('\n');
        return AlertDialog(
          title: Text(L10n.of(context).commonNewVersion,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              )),
          content: SingleChildScrollView(
            child: StyledMarkdown(
                data: '''### ${L10n.of(context).updateNewVersion} $newVersion\n
${L10n.of(context).updateCurrentVersion} $currentVersion\n
$body'''),
          ),
          actions: <Widget>[
            AppButton(
              label: L10n.of(context).commonCancel,
              variant: AppButtonVariant.text,
              onPressed: () {
                SmartDialog.dismiss();
              },
            ),
            AppButton(
              label: L10n.of(context).updateViaGithub,
              variant: AppButtonVariant.text,
              onPressed: () {
                launchUrl(
                    Uri.parse(
                        'https://github.com/Anxcye/anx-reader/releases/latest'),
                    mode: LaunchMode.externalApplication);
              },
            ),
            AppButton(
              label: L10n.of(context).updateViaOfficialWebsite,
              variant: AppButtonVariant.text,
              onPressed: () {
                launchUrl(Uri.parse('https://anx.anxcye.com/download'),
                    mode: LaunchMode.externalApplication);
              },
            ),
          ],
        );
      },
    );
  } else {
    if (manualCheck) {
      AnxToast.show(l10n.commonNoNewVersion);
    }
  }
}
