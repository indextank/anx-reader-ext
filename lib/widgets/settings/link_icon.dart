import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Widget linkIcon({
  required Widget icon,
  required String url,
  required LaunchMode mode,
  double size = AppSettingsTokens.socialIconSize,
}) {
  return AppIconButton(
    tooltip: url,
    semanticLabel: url,
    onPressed: () => launchUrl(
      Uri.parse(url),
      mode: mode,
    ),
    child: SizedBox(
      width: size,
      height: size,
      child: icon,
    ),
  );
}
