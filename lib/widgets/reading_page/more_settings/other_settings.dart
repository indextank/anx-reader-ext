import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/page_turn_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/platform_utils.dart';
import 'package:anx_reader/utils/ui/status_bar.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/diagram.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/page_turn_dropdown.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/page_turning/types_and_icons.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';

class OtherSettings extends StatefulWidget {
  const OtherSettings({super.key});

  @override
  State<OtherSettings> createState() => _OtherSettingsState();
}

class _OtherSettingsState extends State<OtherSettings> {
  @override
  Widget build(BuildContext context) {
    Widget screenTimeout() {
      return AppListTile(
        title: L10n.of(context).readingPageScreenTimeout,
        subtitle: L10n.of(context).commonMinutes(Prefs().awakeTime),
        trailing: SizedBox(
          width: 160,
          child: Slider(
            min: 0,
            max: 60,
            label: Prefs().awakeTime.toString(),
            value: Prefs().awakeTime.toDouble(),
            onChangeEnd: (value) => setState(() {
              readingPageKey.currentState?.setAwakeTimer(value.toInt());
            }),
            onChanged: (value) => setState(() {
              Prefs().awakeTime = value.toInt();
            }),
          ),
        ),
      );
    }

    Widget switchTile(
      String title, {
      String? subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return AppListTile(
        title: title,
        subtitle: subtitle,
        trailing: Switch(
          value: value,
          onChanged: (value) => setState(() => onChanged(value)),
        ),
      );
    }

    Widget pageTurningControl() {
      PageTurnMode currentMode = PageTurnMode.fromCode(Prefs().pageTurnMode);
      return StatefulBuilder(
        builder: (context, setState) {
          return SingleRowSettingTile(
            title: L10n.of(context).readingPagePageTurningMethod,
            trailing: AnxSegmentedButton<PageTurnMode>(
              segments: [
                SegmentButtonItem(
                  value: PageTurnMode.simple,
                  label: L10n.of(context).pageTurnModeSimple,
                ),
                SegmentButtonItem(
                  value: PageTurnMode.custom,
                  label: L10n.of(context).pageTurnModeCustom,
                ),
              ],
              selected: {currentMode},
              onSelectionChanged: (selected) {
                setState(() {
                  currentMode = selected.first;
                  Prefs().pageTurnMode = selected.first.code;
                });
              },
            ),
          );
        },
      );
    }

    Widget pageTurningContent() {
      int currentType = Prefs().pageTurningType;
      final scrollController = ScrollController();
      return StatefulBuilder(
        builder: (context, setState) {
          void onCustomConfigChanged(int index, PageTurningType type) {
            final config = Prefs().customPageTurnConfig;
            config[index] = type.index;
            Prefs().customPageTurnConfig = config;
          }

          if (PageTurnMode.fromCode(Prefs().pageTurnMode) ==
              PageTurnMode.simple) {
            return SizedBox(
              height: 144,
              child: ListView.builder(
                controller: scrollController,
                itemCount: pageTurningTypes.length,
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) => Padding(
                  padding: AppReadingTokens.settingsItemPadding,
                  child: getPageTurningDiagram(
                    context,
                    pageTurningTypes[index],
                    pageTurningIcons[index],
                    currentType == index,
                    () => setState(() {
                      Prefs().pageTurningType = index;
                      currentType = index;
                    }),
                  ),
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                L10n.of(context).customPageTurnConfig,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              for (int row = 0; row < 3; row++)
                Padding(
                  padding: AppReadingTokens.settingsRowGap,
                  child: Row(
                    children: [
                      for (int col = 0; col < 3; col++)
                        Expanded(
                          child: Padding(
                            padding: AppSpacing.only(right: col < 2 ? 8 : 0),
                            child: Builder(
                              builder: (context) {
                                final index = row * 3 + col;
                                final config = Prefs().customPageTurnConfig;
                                return PageTurnDropdown(
                                  value: PageTurningType.values[config[index]],
                                  onChanged: (type) {
                                    if (type != null) {
                                      setState(() {
                                        onCustomConfigChanged(index, type);
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      );
    }

    Widget autoSummaryPreviousContent() {
      final delayLabels = [
        L10n.of(context).readingPageAutoSummaryDelayEveryTime,
        L10n.of(context).readingPageAutoSummaryDelay30Minutes,
        L10n.of(context).readingPageAutoSummaryDelay3Hours,
        L10n.of(context).readingPageAutoSummaryDelayNextDay,
        L10n.of(context).readingPageAutoSummaryDelay3Days,
        L10n.of(context).readingPageAutoSummaryDelay1Week,
      ];
      return Column(
        children: [
          switchTile(
            L10n.of(context).readingPageAutoSummaryPreviousContent,
            value: Prefs().autoSummaryPreviousContent,
            onChanged: (value) => Prefs().autoSummaryPreviousContent = value,
          ),
          if (Prefs().autoSummaryPreviousContent)
            Padding(
              padding: AppReadingTokens.settingsIndent,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          delayLabels[Prefs().autoSummaryDelayLevel],
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Slider(
                          min: 0,
                          max: 5,
                          divisions: 5,
                          value: Prefs().autoSummaryDelayLevel.toDouble(),
                          onChanged: (value) => setState(() {
                            Prefs().autoSummaryDelayLevel = value.toInt();
                          }),
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: AppReadingTokens.settingsRowGap,
                    child: Text(
                      L10n.of(context).readingPageAutoSummaryDelaySubtitle(
                        delayLabels[Prefs().autoSummaryDelayLevel],
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    final metrics = StylePanelDensity.of(context);
    return Padding(
      // 水平对齐统一由行内边距 / 子缩进决定，分组仅保留垂直留白。
      padding: metrics.groupVerticalPadding,
      child: Column(
        children: [
          switchTile(
            L10n.of(context).readingPageFullScreen,
            value: Prefs().hideStatusBar,
            onChanged: (value) {
              Prefs().saveHideStatusBar(value);
              if (value) {
                hideStatusBar();
              } else {
                showStatusBar();
              }
            },
          ),
          if (AnxPlatform.isAndroid)
            switchTile(
              L10n.of(context).readingPageVolumeKeyTurnPage,
              value: Prefs().volumeKeyTurnPage,
              onChanged: (value) => Prefs().volumeKeyTurnPage = value,
            ),
          switchTile(
            L10n.of(context).readingPageSwapPageTurnArea,
            subtitle: L10n.of(context).readingPageSwapPageTurnAreaTips,
            value: Prefs().swapPageTurnArea,
            onChanged: (value) => Prefs().swapPageTurnArea = value,
          ),
          switchTile(
            L10n.of(context).readingPageShowMenuOnHover,
            subtitle: L10n.of(context).readingPageShowMenuOnHoverTips,
            value: Prefs().showMenuOnHover,
            onChanged: (value) => Prefs().showMenuOnHover = value,
          ),
          if (AnxPlatform.isDesktop)
            switchTile(
              L10n.of(context).readingPageKeyboardShortcutTurnPage,
              subtitle:
                  L10n.of(context).readingPageKeyboardShortcutTurnPageTips,
              value: Prefs().keyboardShortcutTurnPage,
              onChanged: (value) => Prefs().keyboardShortcutTurnPage = value,
            ),
          switchTile(
            L10n.of(context).readingPageAutoAdjustReadingTheme,
            subtitle: L10n.of(context).readingPageAutoAdjustReadingThemeTips,
            value: Prefs().autoAdjustReadingTheme,
            onChanged: (value) => Prefs().autoAdjustReadingTheme = value,
          ),
          switchTile(
            L10n.of(context).readingPageAutoTranslateSelection,
            value: Prefs().autoTranslateSelection,
            onChanged: (value) => Prefs().autoTranslateSelection = value,
          ),
          switchTile(
            L10n.of(context).readingPageAutoMarkSelection,
            subtitle: L10n.of(context).readingPageAutoMarkSelectionTips,
            value: Prefs().autoMarkSelection,
            onChanged: (value) => Prefs().autoMarkSelection = value,
          ),
          autoSummaryPreviousContent(),
          screenTimeout(),
          pageTurningControl(),
          Padding(
            padding: metrics.childIndent,
            child: pageTurningContent(),
          ),
        ],
      ),
    );
  }
}
