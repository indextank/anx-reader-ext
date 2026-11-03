import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/bookshelf_folder_style.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/ui_settings.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/utils/env_var.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/settings/settings_section.dart';
import 'package:anx_reader/widgets/settings/settings_tile.dart';
import 'package:anx_reader/widgets/settings/settings_title.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:anx_reader/widgets/settings/simple_dialog.dart';
import 'package:anx_reader/widgets/settings/theme_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const List<Map<String, String>> languageOptions = [
  {'system': 'System'},
  {'English': 'en'},
  {'简体中文': 'zh-CN'},
  {'繁體中文': 'zh-TW'},
  {'文言文': 'zh-LZH'},
  {'Türkçe': 'tr'},
  {'Deutsch': 'de'},
  {'العربية': 'ar'},
  {'Русский': 'ru'},
  {'Français': 'fr'},
  {'Español': 'es'},
  {'Italiano': 'it'},
  {'Português': 'pt'},
  {'日本語': 'ja'},
  {'한국어': 'ko'},
  {'Română': 'ro'},
];

class AppearanceSetting extends ConsumerStatefulWidget {
  const AppearanceSetting({super.key});

  @override
  ConsumerState<AppearanceSetting> createState() => _AppearanceSettingState();
}

class _AppearanceSettingState extends ConsumerState<AppearanceSetting> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(uiSettingsProvider);
    final locale = settings.locale;
    final languageSubtitle = locale == null
        ? languageOptions[0].values.first
        : languageOptions
            .firstWhere(
                (element) =>
                    element.values.first ==
                    locale.languageCode +
                        (locale.countryCode != null
                            ? "-${locale.countryCode}"
                            : ""),
                orElse: () => languageOptions[0])
            .keys
            .first;

    return settingsSections(
      sections: [
        SettingsSection(
          title: Text(L10n.of(context).settingsAppearanceTheme),
          tiles: [
            const CustomSettingsTile(
              child: Padding(
                padding: AppSettingsTokens.themeModePadding,
                child: ChangeThemeMode(),
              ),
            ),
            SettingsTile.navigation(
              title: Text(L10n.of(context).settingsAppearanceThemeColor),
              leading: const Icon(Icons.color_lens),
              onPressed: (context) async {
                await showColorPickerDialog(context, ref);
              },
            ),
            SettingsTile.switchTile(
              title: const Text("OLED Dark Mode"),
              leading: const Icon(Icons.brightness_2),
              initialValue: settings.trueDarkMode,
              onToggle: (bool value) {
                ref.read(uiSettingsProvider.notifier).setTrueDarkMode(value);
              },
            ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).eInkMode),
              leading: const Icon(Icons.contrast),
              initialValue: settings.eInkMode,
              onToggle: (bool value) {
                ref.read(uiSettingsProvider.notifier).setEInkMode(value);
              },
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).settingsAppearanceDisplay),
          tiles: [
            SettingsTile.navigation(
              title: Text(L10n.of(context).settingsAppearanceLanguage),
              value: Text(languageSubtitle),
              leading: const Icon(Icons.language),
              onPressed: (context) {
                showLanguagePickerDialog(context, ref);
              },
            ),
            CustomSettingsTile(
              child: SingleRowSettingTile(
                title: L10n.of(context).settingsAppearanceTextScale,
                valueLabel: '${(settings.textScale * 100).round()}%',
                pinnedTrailing: true,
                trailing: Slider(
                  value: settings.textScale,
                  min: 0.8,
                  max: 1.5,
                  divisions: 7,
                  onChanged: (value) {
                    ref.read(uiSettingsProvider.notifier).setTextScale(value);
                  },
                ),
              ),
            ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).settingsAppearanceOpenBookAnimation),
              leading: const Icon(Icons.animation),
              initialValue: Prefs().openBookAnimation,
              onToggle: (bool value) {
                setState(() {
                  Prefs().openBookAnimation = value;
                });
              },
            ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).settingsAdvancedAutoHideBottomBar),
              leading: const Icon(Icons.vertical_align_bottom),
              initialValue: Prefs().autoHideBottomBar,
              onToggle: (value) {
                Prefs().autoHideBottomBar = value;
                setState(() {});
              },
            ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).reduceVibrationFeedback),
              leading: const Icon(Icons.vibration),
              initialValue: Prefs().reduceVibrationFeedback,
              onToggle: (bool value) {
                setState(() {
                  Prefs().reduceVibrationFeedback = value;
                });
              },
            ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).readingPageShowActionLabels),
              leading: const Icon(Icons.subtitles_outlined),
              initialValue: Prefs().showActionLabels,
              onToggle: (bool value) {
                setState(() {
                  Prefs().showActionLabels = value;
                });
              },
              description:
                  Text(L10n.of(context).readingPageShowActionLabelsTips),
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).settingsBookshelfCover),
          tiles: [
            CustomSettingsTile(
              child: SingleRowSettingTile(
                title: L10n.of(context).settingsBookshelfCoverWidth,
                valueLabel: Prefs().bookCoverWidth.toStringAsFixed(0),
                pinnedTrailing: true,
                trailing: Slider(
                  value: Prefs().bookCoverWidth,
                  onChanged: (value) {
                    setState(() {
                      Prefs().bookCoverWidth = value;
                    });
                  },
                  max: 260,
                  min: 80,
                  divisions: 18,
                ),
              ),
            ),
            CustomSettingsTile(
              child: SingleRowSettingTile(
                title: L10n.of(context).settingsBookshelfFolderStyle,
                trailing: AnxSegmentedButton<BookshelfFolderStyle>(
                  segments: [
                    SegmentButtonItem(
                      label:
                          L10n.of(context).settingsBookshelfFolderStyleOverlap,
                      value: BookshelfFolderStyle.stacked,
                      icon: const Icon(Icons.layers),
                    ),
                    SegmentButtonItem(
                      label: L10n.of(context).settingsBookshelfFolderStyleGrid,
                      value: BookshelfFolderStyle.grid2x2,
                      icon: const Icon(Icons.grid_view),
                    ),
                  ],
                  selected: {settings.bookshelfFolderStyle},
                  onSelectionChanged: (value) {
                    ref
                        .read(uiSettingsProvider.notifier)
                        .setBookshelfFolderStyle(value.first);
                  },
                ),
              ),
            ),
            SettingsTile.switchTile(
              title:
                  Text(L10n.of(context).settingsBookshelfDefaultCoverShowTitle),
              leading: const Icon(Icons.title),
              initialValue: Prefs().showBookTitleOnDefaultCover,
              onToggle: (bool value) {
                setState(() {
                  Prefs().showBookTitleOnDefaultCover = value;
                });
              },
            ),
            SettingsTile.switchTile(
              title: Text(
                  L10n.of(context).settingsBookshelfDefaultCoverShowAuthor),
              leading: const Icon(Icons.person),
              initialValue: Prefs().showAuthorOnDefaultCover,
              onToggle: (bool value) {
                setState(() {
                  Prefs().showAuthorOnDefaultCover = value;
                });
              },
            ),
          ],
        ),
        SettingsSection(
          title: Text(L10n.of(context).settingsAppearanceBottomNavigatorShow),
          tiles: [
            if (EnvVar.enableAIFeature)
              SettingsTile.switchTile(
                title: Text(L10n.of(context).navBarAI),
                initialValue: Prefs().bottomNavigatorShowAI,
                onToggle: (bool value) {
                  setState(() {
                    Prefs().bottomNavigatorShowAI = value;
                  });
                },
              ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).navBarStatistics),
              initialValue: Prefs().bottomNavigatorShowStatistics,
              onToggle: (bool value) {
                setState(() {
                  Prefs().bottomNavigatorShowStatistics = value;
                });
              },
            ),
            SettingsTile.switchTile(
              title: Text(L10n.of(context).navBarNotes),
              initialValue: Prefs().bottomNavigatorShowNote,
              onToggle: (bool value) {
                setState(() {
                  Prefs().bottomNavigatorShowNote = value;
                });
              },
            ),
          ],
        ),
      ],
    );
  }
}

void showLanguagePickerDialog(BuildContext context, WidgetRef ref) {
  final title = L10n.of(context).settingsAppearanceLanguage;
  Future<void> saveToPrefs(String code) {
    return ref
        .read(uiSettingsProvider.notifier)
        .setLocale(localeFromLanguageCode(code));
  }

  final children = languageOptions.map((e) {
    final key = e.keys.first;
    final value = e[key]!;
    return dialogOption(key, value, saveToPrefs);
  }).toList();
  showSimpleDialog(title, saveToPrefs, children);
}

Locale? localeFromLanguageCode(String code) {
  if (code == 'system') return null;
  final parts = code.split('-');
  return Locale(parts.first, parts.length > 1 ? parts[1] : null);
}

Future<void> showColorPickerDialog(BuildContext context, WidgetRef ref) async {
  final currentColor = ref.read(uiSettingsProvider).themeColor;
  Color pickedColor = currentColor;

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AppDialog(
        title: L10n.of(dialogContext).settingsAppearanceThemeColor,
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickedColor,
            onColorChanged: (color) {
              pickedColor = color;
            },
            enableAlpha: false,
            displayThumbColor: true,
            pickerAreaHeightPercent: AppSettingsTokens.colorPickerHeightPercent,
          ),
        ),
        actions: [
          AppButton(
            label: L10n.of(dialogContext).commonCancel,
            variant: AppButtonVariant.text,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          AppSubmitButton(
            label: L10n.of(dialogContext).commonOk,
            feedbackMode: AppSubmitFeedbackMode.inline,
            onSubmit: () async {
              await ref
                  .read(uiSettingsProvider.notifier)
                  .setThemeColor(pickedColor);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
          ),
        ],
      );
    },
  );
}
