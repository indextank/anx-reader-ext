import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/dao/theme.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book_style.dart';
import 'package:anx_reader/models/font_model.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/page/settings_page/subpage/fonts.dart';
import 'package:anx_reader/service/book_player/book_player_server.dart';
import 'package:anx_reader/service/font.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/font_parser.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/more_settings.dart';
import 'package:anx_reader/widgets/reading_page/widget_title.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bgimg_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

enum PageTurn {
  noAnimation,
  slide,
  scroll;

  String getLabel(BuildContext context) {
    switch (this) {
      case PageTurn.noAnimation:
        return L10n.of(context).noAnimation;
      case PageTurn.slide:
        return L10n.of(context).slide;
      case PageTurn.scroll:
        return L10n.of(context).scroll;
    }
  }
}

class StyleWidget extends StatefulWidget {
  const StyleWidget({
    super.key,
    required this.themes,
    required this.epubPlayerKey,
    required this.setCurrentPage,
    required this.hideAppBarAndBottomBar,
    this.embedded = false,
    this.themeInserter,
  });

  final List<ReadTheme> themes;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function setCurrentPage;
  final Function hideAppBarAndBottomBar;
  final bool embedded;
  final Future<int> Function(ReadTheme)? themeInserter;

  @override
  StyleWidgetState createState() => StyleWidgetState();
}

class StyleWidgetState extends State<StyleWidget> {
  int? currentThemeId = Prefs().readTheme.id;
  bool _addingTheme = false;
  bool _themeActionFailed = false;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (!widget.embedded)
          widgetTitle(L10n.of(context).readingPageStyle, ReadingSettings.theme),
        sliders(),
        fontAndPageTurn(),
        const Divider(),
        if (widget.themes.isEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: AppReadingTokens.settingsRowGap,
              child: Text(
                L10n.of(context).readingThemesEmpty,
                style: StylePanelTokens.helper(context),
              ),
            ),
          ),
        themeSelector(),
        if (_themeActionFailed)
          AppInlineFeedback(
            message: L10n.of(context).commonActionFailed,
            onRetry: _addTheme,
          ),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton(
            variant: AppButtonVariant.outlined,
            onPressed: () => widget.setCurrentPage(const BgimgSelector()),
            icon: Icons.arrow_forward_ios,
            label: L10n.of(context).readingPageStyleBackground,
          ),
        ),
      ],
    );
    if (widget.embedded) return content;
    return SingleChildScrollView(
      padding: AppReadingTokens.panelPadding,
      child: content,
    );
  }

  List<FontModel> fonts() {
    final fontDir = getFontDir();
    final fontList = [
      FontModel(
        label: L10n.of(context).downloadFonts,
        name: 'download',
        path: 'download',
      ),
      FontModel(
        label: L10n.of(context).addNewFont,
        name: 'newFont',
        path: 'newFount',
      ),
      FontModel(
        label: L10n.of(context).followBook,
        name: 'book',
        path: 'book',
      ),
      FontModel(
        label: L10n.of(context).systemFont,
        name: 'system',
        path: 'system',
      ),
    ];
    final files = fontDir.listSync();
    for (int i = 0; i < files.length; i++) {
      final element = files[i] as File;
      fontList.add(
        FontModel(
          label: getFontNameFromFile(element),
          name: 'customFont$i',
          path:
              'http://127.0.0.1:${Server().port}/fonts/${element.path.split(Platform.pathSeparator).last}',
        ),
      );
    }
    return fontList;
  }

  Widget fontAndPageTurn() {
    final font = fonts().firstWhere(
      (element) => element.path == Prefs().font.path,
      orElse: () => FontModel(
        label: L10n.of(context).followBook,
        name: 'book',
        path: 'book',
      ),
    );

    Widget? leadingIcon(String name) {
      if (name == 'download') return const Icon(Icons.download);
      if (name == 'newFont') return const Icon(Icons.add);
      return null;
    }

    final inputDecorationTheme = InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(borderRadius: AppReadingTokens.dropdownRadius),
    );
    return Column(
      children: [
        DropdownMenu<PageTurn>(
          label: Text(L10n.of(context).readingPagePageTurningMethod),
          initialSelection: Prefs().pageTurnStyle,
          expandedInsets: AppSpacing.zero,
          inputDecorationTheme: inputDecorationTheme,
          onSelected: (value) {
            if (value != null) {
              Prefs().pageTurnStyle = value;
              epubPlayerKey.currentState!.changePageTurnStyle(value);
            }
          },
          dropdownMenuEntries: PageTurn.values
              .map(
                (value) => DropdownMenuEntry(
                  value: value,
                  label: value.getLabel(context),
                ),
              )
              .toList(),
        ),
        DropdownMenu<FontModel>(
          label: Text(L10n.of(context).font),
          expandedInsets: AppSpacing.zero,
          initialSelection: font,
          inputDecorationTheme: inputDecorationTheme,
          onSelected: (font) async {
            if (font == null) return;
            if (font.name == 'newFont') {
              widget.hideAppBarAndBottomBar(false);
              await importFont();
              return;
            }
            if (font.name == 'download') {
              widget.hideAppBarAndBottomBar(false);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const FontsSettingPage()),
              );
              return;
            }
            epubPlayerKey.currentState!.changeFont(font);
            Prefs().font = font;
          },
          dropdownMenuEntries: fonts()
              .map(
                (font) => DropdownMenuEntry(
                  value: font,
                  label: font.label,
                  leadingIcon: leadingIcon(font.name),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  void _updateBookStyle(BookStyle Function(BookStyle current) update) {
    setState(() {
      final bookStyle = update(Prefs().bookStyle);
      Prefs().saveBookStyleToPrefs(bookStyle);
      widget.epubPlayerKey.currentState!.changeStyle(bookStyle);
    });
  }

  Widget sliders() {
    return Column(
      children: [
        fontSizeSlider(),
        lineHeightAndParagraphSpacingSlider(),
      ],
    );
  }

  Widget lineHeightAndParagraphSpacingSlider() {
    final enabled = !Prefs().useBookStyles;
    final bookStyle = Prefs().bookStyle;
    return Column(
      children: [
        Row(
          children: [
            _panelSliderLabel(
              context,
              icon: const Icon(Icons.line_weight),
              text: L10n.of(context).readingPageLineSpacing,
            ),
            Expanded(
              child: Slider(
                padding: AppReadingTokens.sliderPadding,
                value: bookStyle.lineHeight,
                onChanged: enabled
                    ? (value) {
                        _updateBookStyle(
                          (current) => current.copyWith(lineHeight: value),
                        );
                      }
                    : null,
                min: 0,
                max: 3,
                divisions: 10,
                label: (bookStyle.lineHeight / 3 * 10).round().toString(),
              ),
            ),
          ],
        ),
        Row(
          children: [
            _panelSliderLabel(
              context,
              icon: const Icon(Icons.height),
              text: L10n.of(context).readingPageParagraphSpacing,
            ),
            Expanded(
              child: Slider(
                padding: AppReadingTokens.sliderPadding,
                value: bookStyle.paragraphSpacing,
                onChanged: enabled
                    ? (value) {
                        _updateBookStyle(
                          (current) =>
                              current.copyWith(paragraphSpacing: value),
                        );
                      }
                    : null,
                min: 0,
                max: 5,
                divisions: 10,
                label: (bookStyle.paragraphSpacing / 5 * 10).round().toString(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget fontSizeSlider() {
    final enabled = !Prefs().useBookStyles;
    final bookStyle = Prefs().bookStyle;
    return Row(
      children: [
        _panelSliderLabel(
          context,
          icon: const Icon(Icons.format_size),
          text: L10n.of(context).readingPageFontSize,
        ),
        Expanded(
          child: Slider(
            value: bookStyle.fontSize,
            onChanged: enabled
                ? (value) {
                    _updateBookStyle(
                      (current) => current.copyWith(fontSize: value),
                    );
                  }
                : null,
            min: 0.5,
            max: 3,
            divisions: 25,
            label: bookStyle.fontSize.toStringAsFixed(2),
          ),
        ),
      ],
    );
  }

  Future<void> _addTheme() async {
    if (_addingTheme) return;
    setState(() {
      _addingTheme = true;
      _themeActionFailed = false;
    });
    try {
      final theme = ReadTheme(
        backgroundColor: 'ff121212',
        textColor: 'ffcccccc',
        backgroundImagePath: '',
      );
      final insertTheme = widget.themeInserter ?? themeDao.insertTheme;
      final id = await insertTheme(theme);
      widget.setCurrentPage(
        ThemeChangeWidget(
          readTheme: ReadTheme(
            id: id,
            backgroundColor: theme.backgroundColor,
            textColor: theme.textColor,
            backgroundImagePath: '',
          ),
          setCurrentPage: widget.setCurrentPage,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _themeActionFailed = true);
    } finally {
      if (mounted) setState(() => _addingTheme = false);
    }
  }

  Widget themeSelector() {
    const size = 40.0;
    return SizedBox(
      height: StylePanelTokens.themeRowHeight,
      child: ListView.builder(
        itemCount: widget.themes.length + 1,
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          if (index == widget.themes.length) {
            return Padding(
              padding: AppReadingTokens.smallPadding,
              child: AppCard(
                padding: AppReadingTokens.smallPadding,
                borderRadius: AppReadingTokens.pillRadius,
                onTap: _addTheme,
                enabled: !_addingTheme,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Center(
                    child: _addingTheme
                        ? const AppLoadingIndicator()
                        : const Icon(Icons.add),
                  ),
                ),
              ),
            );
          }
          final theme = widget.themes[index];
          final selected = index + 1 == currentThemeId;
          return Padding(
            padding: AppReadingTokens.smallPadding,
            child: AppCard(
              padding: AppReadingTokens.smallPadding,
              borderRadius: AppReadingTokens.pillRadius,
              color: Color(int.parse('0x${theme.backgroundColor}')),
              onTap: () {
                Prefs().saveReadThemeToPrefs(theme);
                widget.epubPlayerKey.currentState!.changeTheme(theme);
                setState(() => currentThemeId = theme.id);
              },
              onSecondaryTap: () => _editTheme(theme),
              onLongPress: () => _editTheme(theme),
              semanticLabel: selected ? '${theme.id}' : null,
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: Text(
                    'A',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Color(int.parse('0x${theme.textColor}')),
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _editTheme(ReadTheme theme) {
    widget.setCurrentPage(
      ThemeChangeWidget(
        readTheme: theme,
        setCurrentPage: widget.setCurrentPage,
      ),
    );
  }
}

class ThemeChangeWidget extends StatefulWidget {
  const ThemeChangeWidget({
    super.key,
    required this.readTheme,
    required this.setCurrentPage,
  });

  final ReadTheme readTheme;
  final Function setCurrentPage;

  @override
  State<ThemeChangeWidget> createState() => _ThemeChangeWidgetState();
}

class _ThemeChangeWidgetState extends State<ThemeChangeWidget> {
  late ReadTheme readTheme;

  @override
  void initState() {
    super.initState();
    readTheme = widget.readTheme;
  }

  Future<void> _pickColor(bool background) async {
    final pickingColor = await showColorPickerDialog(
      background ? readTheme.backgroundColor : readTheme.textColor,
    );
    if (pickingColor != null && pickingColor.isNotEmpty && mounted) {
      setState(() {
        if (background) {
          readTheme.backgroundColor = pickingColor;
        } else {
          readTheme.textColor = pickingColor;
        }
      });
      await themeDao.updateTheme(readTheme);
    }
  }

  Future<void> _confirmDelete() async {
    final l10n = L10n.of(context);
    final deleted = await AppDialog.confirm(
      context,
      title: l10n.commonDelete,
      message: l10n.readingPageTheme,
      confirmLabel: l10n.commonDelete,
      isDangerous: true,
      dangerDescription: l10n.readingPageTheme,
      onConfirm: () async => themeDao.deleteTheme(readTheme.id!),
    );
    if (deleted) widget.setCurrentPage(const SizedBox(height: 1));
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        AppIconButton(
          onPressed: () => _pickColor(true),
          child: Icon(
            Icons.circle,
            size: 80,
            color: Color(int.parse('0x${readTheme.backgroundColor}')),
          ),
        ),
        AppIconButton(
          onPressed: () => _pickColor(false),
          child: Icon(
            Icons.text_fields,
            size: 60,
            color: Color(int.parse('0x${readTheme.textColor}')),
          ),
        ),
        AppIconButton(
          icon: Icons.delete,
          tooltip: L10n.of(context).commonDelete,
          variant: AppButtonVariant.danger,
          onPressed: _confirmDelete,
        ),
      ],
    );
  }

  Future<String?> showColorPickerDialog(String currColor) async {
    var pickedColor = Color(int.parse('0x$currColor'));
    await showDialog<String>(
      context: navigatorKey.currentState!.overlay!.context,
      builder: (context) => AppDialog(
        title: L10n.of(context).readingPageTheme,
        content: SingleChildScrollView(
          child: ColorPicker(
            hexInputBar: true,
            pickerColor: pickedColor,
            onColorChanged: (color) => pickedColor = color,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          AppButton(
            variant: AppButtonVariant.text,
            label: L10n.of(context).commonCancel,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(
            label: L10n.of(context).commonConfirm,
            onPressed: () => Navigator.of(context)
                .pop(pickedColor.toARGB32().toRadixString(16)),
          ),
        ],
      ),
    );
    return pickedColor.toARGB32().toRadixString(16);
  }
}

/// 面板滑杆行的统一图标+标签（高度与文字样式取自 StylePanelTokens）。
Widget _panelSliderLabel(
  BuildContext context, {
  required Widget icon,
  required String text,
}) {
  return IconAndText(
    icon: icon,
    text: text,
    heightOverride: StylePanelTokens.sliderLabelHeight,
    style: StylePanelTokens.optionLabel(context),
  );
}
