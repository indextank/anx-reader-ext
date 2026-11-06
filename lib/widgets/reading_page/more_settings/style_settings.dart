import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/enums/text_alignment.dart';
import 'package:anx_reader/enums/writing_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/custom_css_editor.dart';
import 'package:anx_reader/widgets/reading_page/style_panel_slider_label.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

// Reusable style slider widget that can be disabled
class StyleSlider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelFormatter;
  final bool enabled;

  const StyleSlider({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelFormatter,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        StylePanelSliderLabel(icon: Icon(icon), text: label),
        Expanded(
          child: Slider(
            padding: AppReadingTokens.sliderPadding,
            value: value,
            onChanged: enabled ? onChanged : null,
            min: min,
            max: max,
            divisions: divisions,
            label: labelFormatter(value),
          ),
        ),
      ],
    );
  }
}

class StyleSettings extends StatefulWidget {
  const StyleSettings({super.key});

  @override
  State<StyleSettings> createState() => _StyleSettingsState();
}

class _StyleSettingsState extends State<StyleSettings> {
  void _updateBookStyle(BookStyle Function(BookStyle current) update) {
    setState(() {
      final bookStyle = update(Prefs().bookStyle);
      Prefs().saveBookStyleToPrefs(bookStyle);
      epubPlayerKey.currentState?.changeStyle(bookStyle);
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget useBookStylesSwitch() {
      return AppListTile(
        title: L10n.of(context).useBookStyles,
        subtitle: L10n.of(context).useBookStylesDescription,
        trailing: Switch(
          value: Prefs().useBookStyles,
          onChanged: (value) {
            setState(() {
              Prefs().useBookStyles = value;
              epubPlayerKey.currentState?.changeStyle(Prefs().bookStyle);
            });
          },
        ),
      );
    }

    Widget textIndent() {
      final enabled = !Prefs().useBookStyles;
      final bookStyle = Prefs().bookStyle;
      return StyleSlider(
        icon: Icons.format_indent_increase,
        label: L10n.of(context).readingPageIndent,
        value: bookStyle.indent,
        onChanged: (value) => _updateBookStyle(
          (current) => current.copyWith(indent: value),
        ),
        min: -0.5,
        max: 8,
        divisions: 17,
        labelFormatter: (value) => value < 0
            ? L10n.of(context).readingPageIndentNoChange
            : value.toStringAsFixed(1),
        enabled: enabled,
      );
    }

    Widget sideMarginSlider() {
      final bookStyle = Prefs().bookStyle;
      return StyleSlider(
        icon: Prefs().writingMode == WritingModeEnum.verticalRl
            ? Bootstrap.arrows_vertical
            : Bootstrap.arrows,
        label: Prefs().writingMode == WritingModeEnum.verticalRl
            ? L10n.of(context).readingPageVerticleMargin
            : L10n.of(context).readingPageSideMargin,
        value: bookStyle.sideMargin,
        onChanged: (value) => _updateBookStyle(
          (current) => current.copyWith(sideMargin: value),
        ),
        min: 0,
        max: 20,
        divisions: 20,
        labelFormatter: (value) => value.toStringAsFixed(1),
        enabled: true, // Side margin is always enabled
      );
    }

    Widget letterSpacingSlider() {
      final enabled = !Prefs().useBookStyles;
      final bookStyle = Prefs().bookStyle;
      return StyleSlider(
        icon: Icons.compare_arrows,
        label: L10n.of(context).readingPageLetterSpacing,
        value: bookStyle.letterSpacing,
        onChanged: (value) => _updateBookStyle(
          (current) => current.copyWith(letterSpacing: value),
        ),
        min: -3,
        max: 7,
        divisions: 10,
        labelFormatter: (value) => value.toString(),
        enabled: enabled,
      );
    }

    Row topBottomMarginSlider() {
      final bookStyle = Prefs().bookStyle;
      return Row(children: [
        Prefs().writingMode == WritingModeEnum.verticalRl
            ? StylePanelSliderLabel(
                icon: const Icon(Bootstrap.chevron_bar_right),
                text: L10n.of(context).readingPageRightMargin,
              )
            : StylePanelSliderLabel(
                icon: const Icon(Bootstrap.chevron_bar_up),
                text: L10n.of(context).readingPageTopMargin,
              ),
        Expanded(
          child: Slider(
            padding: AppReadingTokens.sliderPadding,
            value: bookStyle.topMargin,
            onChanged: (value) => _updateBookStyle(
              (current) => current.copyWith(topMargin: value),
            ),
            min: 0,
            max: 200,
            divisions: 10,
            label: (bookStyle.topMargin / 20).toStringAsFixed(0),
          ),
        ),
        Prefs().writingMode == WritingModeEnum.verticalRl
            ? StylePanelSliderLabel(
                icon: const Icon(Bootstrap.chevron_bar_left),
                text: L10n.of(context).readingPageLeftMargin,
              )
            : StylePanelSliderLabel(
                icon: const Icon(Bootstrap.chevron_bar_down),
                text: L10n.of(context).readingPageBottomMargin,
              ),
        Expanded(
          child: Slider(
            padding: AppReadingTokens.sliderPadding,
            value: bookStyle.bottomMargin,
            onChanged: (value) => _updateBookStyle(
              (current) => current.copyWith(bottomMargin: value),
            ),
            min: 0,
            max: 200,
            divisions: 10,
            label: (bookStyle.bottomMargin / 20).toStringAsFixed(0),
          ),
        ),
      ]);
    }

    Widget fontWeightSlider() {
      final enabled = !Prefs().useBookStyles;
      final bookStyle = Prefs().bookStyle;
      return StyleSlider(
        icon: Icons.format_bold,
        label: L10n.of(context).readingPageFontWeight,
        value: bookStyle.fontWeight,
        onChanged: (value) => _updateBookStyle(
          (current) => current.copyWith(fontWeight: value),
        ),
        min: 100,
        max: 900,
        divisions: 8,
        labelFormatter: (value) => value.toString(),
        enabled: enabled,
      );
    }

    Widget headingFontSizeSlider() {
      final enabled = !Prefs().useBookStyles;
      final bookStyle = Prefs().bookStyle;
      return StyleSlider(
        icon: Icons.title,
        label: L10n.of(context).headingFontSize,
        value: bookStyle.headingFontSize,
        onChanged: (value) => _updateBookStyle(
          (current) => current.copyWith(headingFontSize: value),
        ),
        min: 0.5,
        max: 2.0,
        divisions: 15,
        labelFormatter: (value) => value.toStringAsFixed(1),
        enabled: enabled,
      );
    }

    Widget textAlignment() {
      final items = [
        {
          "icon": Icons.auto_awesome,
          "text": L10n.of(context).textAlignmentAuto,
          "value": TextAlignmentEnum.auto
        },
        {
          "icon": Icons.format_align_left,
          "text": L10n.of(context).textAlignmentLeft,
          "value": TextAlignmentEnum.left
        },
        {
          "icon": Icons.format_align_center,
          "text": L10n.of(context).textAlignmentCenter,
          "value": TextAlignmentEnum.center
        },
        {
          "icon": Icons.format_align_right,
          "text": L10n.of(context).textAlignmentRight,
          "value": TextAlignmentEnum.right
        },
        {
          "icon": Icons.format_align_justify,
          "text": L10n.of(context).textAlignmentJustify,
          "value": TextAlignmentEnum.justify
        },
      ];

      return StatefulBuilder(
        builder: (context, setState) => SingleRowSettingTile(
          title: L10n.of(context).textAlignment,
          leading: Icon(
            Icons.format_align_left,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          trailing: DropdownMenu<TextAlignmentEnum>(
            width: StylePanelTokens.dropdownWidth,
            initialSelection: Prefs().textAlignment,
            inputDecorationTheme: InputDecorationTheme(
              isDense: false,
              border: InputBorder.none,
            ),
            dropdownMenuEntries: items.map((item) {
              return DropdownMenuEntry<TextAlignmentEnum>(
                value: item["value"] as TextAlignmentEnum,
                label: item["text"] as String,
                leadingIcon: Icon(item["icon"] as IconData),
              );
            }).toList(),
            onSelected: (value) {
              if (value != null) {
                setState(() {
                  Prefs().textAlignment = value;
                  epubPlayerKey.currentState?.changeStyle(Prefs().bookStyle);
                });
              }
            },
          ),
        ),
      );
    }

    Widget sliders() {
      return Column(
        children: [
          textIndent(),
          sideMarginSlider(),
          topBottomMarginSlider(),
          letterSpacingSlider(),
          fontWeightSlider(),
          headingFontSizeSlider(),
        ],
      );
    }

    final metrics = StylePanelDensity.of(context);
    return Padding(
      // 水平对齐统一由各设置行内边距 / 子缩进决定，分组仅保留垂直留白。
      padding: metrics.groupVerticalPadding,
      child: Column(
        children: [
          useBookStylesSwitch(),
          Padding(
            padding: metrics.childIndent,
            child: sliders(),
          ),
          textAlignment(),
          Padding(
            padding: metrics.childIndent,
            child: const CustomCSSEditor(),
          ),
        ],
      ),
    );
  }
}
