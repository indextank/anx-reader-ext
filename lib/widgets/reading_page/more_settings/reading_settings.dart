import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/enums/convert_chinese_mode.dart';
import 'package:anx_reader/enums/reading_info.dart';
import 'package:anx_reader/enums/translation_mode.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/enums/code_highlight_theme.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/reading_info.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

class ReadingMoreSettings extends StatefulWidget {
  const ReadingMoreSettings({super.key});

  @override
  State<ReadingMoreSettings> createState() => _ReadingMoreSettingsState();
}

class _ReadingMoreSettingsState extends State<ReadingMoreSettings> {
  final isReading =
      epubPlayerKey.currentState != null && epubPlayerKey.currentState!.mounted;

  @override
  Widget build(BuildContext context) {
    Widget convertChinese() {
      const iconStyle = TextStyle(fontWeight: FontWeight.bold);
      return StatefulBuilder(
        builder: (context, setState) {
          return SingleRowSettingTile(
            title: L10n.of(context).readingPageConvertChinese,
            subtitle: L10n.of(context).readingPageConvertChineseTips,
            trailing: AnxSegmentedButton<ConvertChineseMode>(
              segments: [
                SegmentButtonItem(
                  label: L10n.of(context).readingPageOriginal,
                  value: ConvertChineseMode.none,
                  icon: const Text("原", style: iconStyle),
                ),
                SegmentButtonItem(
                  label: L10n.of(context).readingPageSimplified,
                  value: ConvertChineseMode.t2s,
                  icon: const Text("简", style: iconStyle),
                ),
                SegmentButtonItem(
                  label: L10n.of(context).readingPageTraditional,
                  value: ConvertChineseMode.s2t,
                  icon: const Text("繁", style: iconStyle),
                ),
              ],
              selected: {Prefs().readingRules.convertChineseMode},
              onSelectionChanged: (value) {
                setState(() {
                  // Prefs().readingRules.convertChineseMode =
                  //     ConvertChineseMode.values.byName(value.first);
                  Prefs().readingRules = Prefs()
                      .readingRules
                      .copyWith(convertChineseMode: value.first);
                  epubPlayerKey.currentState
                      ?.changeReadingRules(Prefs().readingRules);
                });
              },
            ),
          );
        },
      );
    }

    Widget columnCount() {
      return StatefulBuilder(
        builder: (context, setState) => SingleRowSettingTile(
          title: L10n.of(context).readingPageColumnCount,
          trailing: AnxSegmentedButton<int>(
            segments: [
              SegmentButtonItem(
                label: L10n.of(context).readingPageAuto,
                value: 0,
                icon: const Icon(Icons.auto_awesome),
              ),
              SegmentButtonItem(
                label: L10n.of(context).readingPageSingle,
                value: 1,
                icon: const Icon(EvaIcons.book),
              ),
              SegmentButtonItem(
                label: L10n.of(context).readingPageDouble,
                value: 2,
                icon: const Icon(EvaIcons.book_open),
              ),
            ],
            selected: {Prefs().bookStyle.maxColumnCount},
            onSelectionChanged: (value) {
              setState(() {
                final newBookStyle =
                    Prefs().bookStyle.copyWith(maxColumnCount: value.first);
                Prefs().saveBookStyleToPrefs(newBookStyle);
                epubPlayerKey.currentState?.changeStyle(newBookStyle);
              });
            },
          ),
        ),
      );
    }

    Widget columnThreshold() {
      return StatefulBuilder(
        builder: (context, setState) => SingleRowSettingTile(
          title: L10n.of(context).readingPageColumnThreshold,
          valueLabel: '${Prefs().bookStyle.columnThreshold.toInt()}px',
          subtitle: Prefs().bookStyle.maxColumnCount == 0
              ? L10n.of(context).readingPageColumnThresholdTip
              : null,
          pinnedTrailing: true,
          trailing: Slider(
            value: Prefs().bookStyle.columnThreshold,
            min: 400,
            max: 1200,
            divisions: 40,
            label: '${Prefs().bookStyle.columnThreshold.toInt()}px',
            onChanged: Prefs().bookStyle.maxColumnCount == 0
                ? (value) {
                    setState(() {
                      final newBookStyle =
                          Prefs().bookStyle.copyWith(columnThreshold: value);
                      Prefs().saveBookStyleToPrefs(newBookStyle);
                      epubPlayerKey.currentState?.changeStyle(newBookStyle);
                    });
                  }
                : null,
          ),
        ),
      );
    }

    Widget writingMode() {
      return StatefulBuilder(
        builder: (context, setState) => SingleRowSettingTile(
          title: L10n.of(context).readingPageWritingDirection,
          trailing: AnxSegmentedButton<WritingModeEnum>(
            segments: [
              SegmentButtonItem(
                label: L10n.of(context).readingPageWritingDirectionAuto,
                value: WritingModeEnum.auto,
                icon: const Icon(EvaIcons.activity_outline),
              ),
              SegmentButtonItem(
                label: L10n.of(context).readingPageWritingDirectionVertical,
                value: WritingModeEnum.verticalRl,
                icon: const Icon(Bootstrap.arrows_vertical),
              ),
              SegmentButtonItem(
                label: L10n.of(context).readingPageWritingDirectionHorizontal,
                value: WritingModeEnum.horizontalTb,
                icon: const Icon(Bootstrap.arrows),
              ),
            ],
            selected: {Prefs().writingMode},
            onSelectionChanged: (value) {
              setState(() {
                final newBookStyle =
                    Prefs().bookStyle.copyWith(maxColumnCount: 1);
                Prefs().saveBookStyleToPrefs(newBookStyle);
                Prefs().writingMode = value.first;
                epubPlayerKey.currentState?.changeStyle(newBookStyle);
              });
            },
          ),
        ),
      );
    }

    Widget translationMode() {
      return StatefulBuilder(
        builder: (context, setState) => SingleRowSettingTile(
          title: L10n.of(context).translationMode,
          subtitle: !isReading
              ? L10n.of(context).readingPageTranslationModeTip
              : null,
          trailing: AnxSegmentedButton<TranslationModeEnum>(
            enabled: isReading,
            segments: [
              SegmentButtonItem(
                label: L10n.of(context).readingPageOriginal,
                value: TranslationModeEnum.off,
                icon: const Icon(Icons.translate_outlined),
              ),
              SegmentButtonItem(
                label: L10n.of(context).translationOnly,
                value: TranslationModeEnum.translationOnly,
                icon: const Icon(Icons.g_translate),
              ),
              SegmentButtonItem(
                label: L10n.of(context).bilingual,
                value: TranslationModeEnum.bilingual,
                icon: const Icon(Icons.compare),
              ),
            ],
            selected: {
              epubPlayerKey.currentState != null
                  ? Prefs().getBookTranslationMode(
                      epubPlayerKey.currentState!.widget.book.id)
                  : TranslationModeEnum.off
            },
            onSelectionChanged: (value) {
              setState(() {
                final currentBookId =
                    epubPlayerKey.currentState!.widget.book.id;
                final newMode = value.first;

                Prefs().setBookTranslationMode(currentBookId, newMode);

                epubPlayerKey.currentState?.setTranslationMode(newMode);
              });
            },
          ),
        ),
      );
    }

    Widget buildInfoDropdown(
      BuildContext context,
      String label,
      ReadingInfoEnum currentValue,
      Function(ReadingInfoEnum) onChanged,
    ) {
      return SingleRowSettingTile(
        title: label,
        pinnedTrailing: true,
        contentPadding: AppSpacing.horizontal4,
        trailing: DropdownButton<ReadingInfoEnum>(
          isDense: true,
          isExpanded: true,
          value: currentValue,
          onChanged: (value) {
            if (value != null) {
              onChanged(value);
            }
          },
          underline: Container(),
          dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: AppReadingTokens.dropdownRadius,
          items: ReadingInfoEnum.values.map((info) {
            return DropdownMenuItem<ReadingInfoEnum>(
              value: info,
              child: Text(
                info.getL10n(context),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
        ),
      );
    }

    Widget readingInfo() {
      return StatefulBuilder(
        builder: (context, setState) {
          void updateReadingInfo(ReadingInfoModel info) {
            Prefs().readingInfo = info;
            epubPlayerKey.currentState?.changeReadingInfo();
          }

          Widget buildSettingSlider({
            required String label,
            required double value,
            required double min,
            required double max,
            required int divisions,
            required ValueChanged<double> onChanged,
          }) {
            return Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(label),
                ),
                Expanded(
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    divisions: divisions,
                    label: value.toStringAsFixed(0),
                    onChanged: (newValue) {
                      setState(() {
                        onChanged(newValue);
                        epubPlayerKey.currentState?.changeReadingInfo();
                      });
                    },
                  ),
                ),
              ],
            );
          }

          Widget buildSectionSettings({
            required String title,
            required ReadingInfoSectionModel section,
            required ValueChanged<ReadingInfoSectionModel> onChanged,
          }) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: buildInfoDropdown(
                        context,
                        L10n.of(context).readingPageLeft,
                        section.left,
                        (value) {
                          setState(() {
                            onChanged(section.copyWith(left: value));
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: buildInfoDropdown(
                        context,
                        L10n.of(context).readingPageCenter,
                        section.center,
                        (value) {
                          setState(() {
                            onChanged(section.copyWith(center: value));
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: buildInfoDropdown(
                        context,
                        L10n.of(context).readingPageRight,
                        section.right,
                        (value) {
                          setState(() {
                            onChanged(section.copyWith(right: value));
                          });
                        },
                      ),
                    ),
                  ],
                ),
                buildSettingSlider(
                  label: L10n.of(context).readingSettingsMargin,
                  value: section.verticalMargin,
                  min: 0,
                  max: 80,
                  divisions: 40,
                  onChanged: (value) =>
                      onChanged(section.copyWith(verticalMargin: value)),
                ),
                buildSettingSlider(
                  label: L10n.of(context).readingPageLeftMargin,
                  value: section.leftMargin,
                  min: 0,
                  max: 80,
                  divisions: 40,
                  onChanged: (value) =>
                      onChanged(section.copyWith(leftMargin: value)),
                ),
                buildSettingSlider(
                  label: L10n.of(context).readingPageRightMargin,
                  value: section.rightMargin,
                  min: 0,
                  max: 80,
                  divisions: 40,
                  onChanged: (value) =>
                      onChanged(section.copyWith(rightMargin: value)),
                ),
                buildSettingSlider(
                  label: L10n.of(context).readingPageFontSize,
                  value: section.fontSize,
                  min: 8,
                  max: 24,
                  divisions: 16,
                  onChanged: (value) =>
                      onChanged(section.copyWith(fontSize: value)),
                ),
              ],
            );
          }

          final readingInfo = Prefs().readingInfo;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildSectionSettings(
                title: L10n.of(context).readingPageHeaderSettings,
                section: readingInfo.header,
                onChanged: (section) {
                  updateReadingInfo(readingInfo.copyWith(header: section));
                },
              ),
              const Divider(),
              buildSectionSettings(
                title: L10n.of(context).readingPageFooterSettings,
                section: readingInfo.footer,
                onChanged: (section) {
                  updateReadingInfo(readingInfo.copyWith(footer: section));
                },
              ),
            ],
          );
        },
      );
    }

    Widget downloadFonts() {
      return AppListTile(
        contentPadding: AppSpacing.zero,
        title: L10n.of(context).downloadFonts,
        leading: const Icon(Icons.font_download_outlined),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const FontsSettingPage(),
            ),
          );
        },
      );
    }

    Widget codeHighlightTheme() {
      return StatefulBuilder(
        builder: (context, setState) {
          final lightThemes = [
            CodeHighlightThemeEnum.defaultTheme,
            CodeHighlightThemeEnum.github,
            CodeHighlightThemeEnum.oneLight,
            CodeHighlightThemeEnum.materialLight,
          ];

          final darkThemes = [
            CodeHighlightThemeEnum.vsDark,
            CodeHighlightThemeEnum.oneDark,
            CodeHighlightThemeEnum.dracula,
            CodeHighlightThemeEnum.materialDark,
            CodeHighlightThemeEnum.nord,
            CodeHighlightThemeEnum.nightOwl,
            CodeHighlightThemeEnum.solarizedDark,
            CodeHighlightThemeEnum.atomDark,
          ];

          Widget themeChipRow(
            String label,
            List<CodeHighlightThemeEnum> themes,
          ) {
            return SingleRowSettingTile(
              title: label,
              // Wrap 需要按剩余宽度换行，因此钉合（不包横向滚动），
              // 并放宽右侧占比让芯片尽量单排放下。
              pinnedTrailing: true,
              trailingMaxWidthFactor: 0.85,
              trailing: Wrap(
                spacing: AppSpacing.tokens.s8,
                runSpacing: AppSpacing.tokens.s4,
                children: themes.map((theme) {
                  final isSelected = Prefs().codeHighlightTheme == theme;
                  return ChoiceChip(
                    label: Text(theme.displayName),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          Prefs().codeHighlightTheme = theme;
                          epubPlayerKey.currentState?.changeStyle(null);
                        });
                      }
                    },
                  );
                }).toList(),
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Quick toggle: Off / Light / Dark
              SingleRowSettingTile(
                title: L10n.of(context).codeHighlightTheme,
                trailing: AnxSegmentedButton<String>(
                  segments: [
                    SegmentButtonItem(
                      label: L10n.of(context).codeHighlightOff,
                      value: 'off',
                      icon: const Icon(Icons.code_off),
                    ),
                    SegmentButtonItem(
                      label: L10n.of(context).codeHighlightLight,
                      value: 'light',
                      icon: const Icon(Icons.light_mode),
                    ),
                    SegmentButtonItem(
                      label: L10n.of(context).codeHighlightDark,
                      value: 'dark',
                      icon: const Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {
                    Prefs().codeHighlightTheme == CodeHighlightThemeEnum.off
                        ? 'off'
                        : Prefs().codeHighlightTheme.isLight
                            ? 'light'
                            : 'dark'
                  },
                  onSelectionChanged: (value) {
                    setState(() {
                      if (value.first == 'off') {
                        Prefs().codeHighlightTheme = CodeHighlightThemeEnum.off;
                      } else if (value.first == 'light') {
                        Prefs().codeHighlightTheme =
                            CodeHighlightThemeEnum.defaultTheme;
                      } else {
                        Prefs().codeHighlightTheme =
                            CodeHighlightThemeEnum.vsDark;
                      }
                      epubPlayerKey.currentState?.changeStyle(null);
                    });
                  },
                ),
              ),
              // Detailed theme selection (only show if not off)
              if (Prefs().codeHighlightTheme != CodeHighlightThemeEnum.off) ...[
                if (Prefs().codeHighlightTheme.isLight)
                  themeChipRow(
                    L10n.of(context).codeHighlightLightThemes,
                    lightThemes,
                  ),
                if (Prefs().codeHighlightTheme.isDark)
                  themeChipRow(
                    L10n.of(context).codeHighlightDarkThemes,
                    darkThemes,
                  ),
              ],
            ],
          );
        },
      );
    }

    return Container(
      padding: AppReadingTokens.settingsPadding,
      child: Column(
        children: [
          downloadFonts(),
          const Divider(height: 20),
          writingMode(),
          translationMode(),
          columnCount(),
          columnThreshold(),
          convertChinese(),
          const Divider(height: 15),
          codeHighlightTheme(),
          const Divider(height: 15),
          readingInfo(),
          // const Divider(height: 8),
          // bionicReading(),
        ],
      ),
    );
  }
}
