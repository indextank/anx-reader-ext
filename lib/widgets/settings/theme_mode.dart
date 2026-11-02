import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/ui_settings.dart';
import 'package:anx_reader/utils/theme_mode_to_string.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ChangeThemeMode extends ConsumerWidget {
  const ChangeThemeMode({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      uiSettingsProvider.select((settings) => settings.themeMode),
    );
    return AnxSegmentedButton<String>(
      segments: <SegmentButtonItem<String>>[
        SegmentButtonItem(
          value: 'auto',
          label: L10n.of(context).settingsSystemMode,
          icon: const Icon(Icons.brightness_auto),
        ),
        SegmentButtonItem(
          value: 'dark',
          label: L10n.of(context).settingsDarkMode,
          icon: const Icon(Icons.brightness_2),
        ),
        SegmentButtonItem(
          value: 'light',
          label: L10n.of(context).settingsLightMode,
          icon: const Icon(Icons.brightness_5),
        ),
      ],
      selected: {themeModeToString(themeMode)},
      onSelectionChanged: (selection) {
        final mode = switch (selection.first) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        };
        ref.read(uiSettingsProvider.notifier).setThemeMode(mode);
      },
    );
  }
}
