import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:flutter/material.dart';

Widget widgetTitle(String title, ReadingSettings? settings) {
  return Builder(
    builder: (context) => Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontFamily: AppReadingTokens.titleFontFamily,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            if (settings != null)
              AppIconButton(
                icon: Icons.settings,
                tooltip: L10n.of(context).navBarSettings,
                onPressed: () => showMoreSettings(settings),
              )
            else
              const SizedBox(height: 48),
          ],
        ),
        const Divider(),
      ],
    ),
  );
}
