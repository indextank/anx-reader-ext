import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/other_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/reading_settings.dart';
import 'package:anx_reader/widgets/reading_page/more_settings/style_settings.dart';
import 'package:anx_reader/widgets/reading_page/style_widget.dart';
import 'package:flutter/material.dart';

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
      padding: AppReadingTokens.panelPadding,
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
          Divider(color: AppReadingTokens.divider(context)),
          _SectionTitle(title: l10n.readingPageReading),
          const ReadingMoreSettings(),
          Divider(color: AppReadingTokens.divider(context)),
          _SectionTitle(title: l10n.readingPageStyle),
          const StyleSettings(),
          Divider(color: AppReadingTokens.divider(context)),
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
      padding: AppReadingTokens.settingsItemPadding,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge,
      ),
    );
  }
}
