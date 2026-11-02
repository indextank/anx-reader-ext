import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

void showDonateDialog(BuildContext context) {
  SmartDialog.show(
    builder: (context) => AppDialog(
      title: L10n.of(context).appDonate,
      content: Text(L10n.of(context).appDonateTips),
      actions: [
        AppButton(
          label: L10n.of(context).appDonate,
          onPressed: () {
            launchUrl(
              Uri.parse('https://anxcye.com/home/7'),
              mode: LaunchMode.externalApplication,
            );
          },
        ),
      ],
    ),
  );
}
