import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';

/// 阅读页「样式」面板：样式/阅读/样式/其他四个分组纵向合排。
///
/// 排版遵循 [StylePanelTokens]（紧凑间距 + 统一文字样式），
/// 分组间以 [StylePanelTokens.sectionGap] 分隔，不再使用 Divider。
class CombinedStyleSettings extends StatelessWidget {
  const CombinedStyleSettings({
    super.key,
    required this.themes,
    required this.epubPlayerKey,
    required this.setCurrentPage,
    required this.hideAppBarAndBottomBar,
    this.themeInserter,
  });

  final List<ReadTheme> themes;
  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final ValueChanged<Widget> setCurrentPage;
  final Function hideAppBarAndBottomBar;
  final Future<int> Function(ReadTheme)? themeInserter;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SingleChildScrollView(
      key: const ValueKey('combined-style-settings-scroll'),
      padding: StylePanelTokens.panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionTitle(title: l10n.readingPageStyle),
          StyleWidget(
            themes: themes,
            epubPlayerKey: epubPlayerKey,
            setCurrentPage: setCurrentPage,
            hideAppBarAndBottomBar: hideAppBarAndBottomBar,
            embedded: true,
            themeInserter: themeInserter,
          ),
          const SizedBox(height: StylePanelTokens.sectionGap),
          _SectionTitle(title: l10n.readingPageReading),
          const ReadingMoreSettings(),
          const SizedBox(height: StylePanelTokens.sectionGap),
          _SectionTitle(title: l10n.readingPageStyle),
          const StyleSettings(),
          const SizedBox(height: StylePanelTokens.sectionGap),
          _SectionTitle(title: l10n.readingPageOther),
          const OtherSettings(),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: StylePanelTokens.sectionHeaderPadding,
      child: Text(title, style: StylePanelTokens.sectionTitle(context)),
    );
  }
}
