import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/style_panel_content_width.dart';
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
  final void Function(bool hide) hideAppBarAndBottomBar;
  final Future<int> Function(ReadTheme)? themeInserter;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final metrics = StylePanelDensity.of(context);
    final content = Column(
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
        SizedBox(height: metrics.sectionGap),
        _SectionTitle(title: l10n.readingPageReading),
        const ReadingMoreSettings(),
        SizedBox(height: metrics.sectionGap),
        _SectionTitle(title: l10n.readingPageStyle),
        const StyleSettings(),
        SizedBox(height: metrics.sectionGap),
        _SectionTitle(title: l10n.readingPageOther),
        const OtherSettings(),
      ],
    );

    // 合并内容在极窄右栏/弹框中无法把所有行压到单行时，保持内容按
    // 测量宽度渲染，并用横向滚动兜底，避免换行/省略或 RenderFlex 溢出。
    return LayoutBuilder(
      builder: (context, constraints) {
        final requiredWidth = stylePanelContentWidthFor(context, metrics);
        final availableWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : requiredWidth;
        final scrollable = SingleChildScrollView(
          key: const ValueKey('combined-style-settings-scroll'),
          padding: metrics.panelPadding,
          child: content,
        );
        if (availableWidth >= StylePanelTokens.minSingleLineFallbackWidth ||
            requiredWidth <= availableWidth + 0.5) {
          return scrollable;
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: requiredWidth,
            child: scrollable,
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final metrics = StylePanelDensity.of(context);
    return Padding(
      padding: metrics.sectionHeaderPadding,
      child: Text(title, style: StylePanelTokens.sectionTitle(context)),
    );
  }
}
