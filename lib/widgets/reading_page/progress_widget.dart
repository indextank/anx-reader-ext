import 'dart:async';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/page/reading_page.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:flutter/material.dart';

class ProgressWidget extends StatefulWidget {
  const ProgressWidget({
    super.key,
    required this.epubPlayerKey,
    required this.showOrHideAppBarAndBottomBar,
  });

  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function(bool) showOrHideAppBarAndBottomBar;

  @override
  State<ProgressWidget> createState() => _ProgressWidgetState();
}

class _ProgressWidgetState extends State<ProgressWidget> {
  Timer? _sliderTimer;
  double _readProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _readProgress = epubPlayerKey.currentState!.percentage;
  }

  @override
  void dispose() {
    _sliderTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppReadingTokens.panelPadding,
      child: Column(
        children: [
          Text(
            widget.epubPlayerKey.currentState!.chapterTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: AppReadingTokens.titleFontFamily,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Divider(),
          Row(
            children: [
              AppIconButton(
                icon: Icons.arrow_back,
                onPressed: () {
                  setState(() {
                    widget.epubPlayerKey.currentState!.prevChapter();
                  });
                },
              ),
              Expanded(
                child: Slider(
                  inactiveColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  value: _readProgress,
                  onChanged: (value) {
                    setState(() => _readProgress = value);
                    _sliderTimer?.cancel();
                    _sliderTimer = Timer(
                      const Duration(milliseconds: 100),
                      () async {
                        await widget.epubPlayerKey.currentState!
                            .goToPercentage(value);
                        Timer(const Duration(milliseconds: 300), () {
                          if (mounted) setState(() {});
                        });
                      },
                    );
                  },
                ),
              ),
              AppIconButton(
                icon: Icons.arrow_forward,
                onPressed: () {
                  setState(() {
                    widget.epubPlayerKey.currentState!.nextChapter();
                  });
                },
              ),
            ],
          ),
          Row(
            children: [
              ProgressDisplay(
                mainText: widget.epubPlayerKey.currentState!.chapterCurrentPage
                    .toString(),
                subText: L10n.of(context).readingPageCurrentPage,
              ),
              ProgressDisplay(
                mainText: widget.epubPlayerKey.currentState!.chapterTotalPages
                    .toString(),
                subText: L10n.of(context).readingPageChapterPages,
              ),
              ProgressDisplay(
                mainText: (widget.epubPlayerKey.currentState!.percentage * 100)
                    .toStringAsFixed(2),
                subText: '%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProgressDisplay extends StatelessWidget {
  const ProgressDisplay({
    super.key,
    required this.mainText,
    required this.subText,
  });

  final String mainText;
  final String subText;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            mainText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: AppReadingTokens.titleFontFamily,
                  fontWeight: FontWeight.bold,
                ),
          ),
          Text(
            subText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: AppReadingTokens.titleFontFamily,
                  fontWeight: FontWeight.w300,
                ),
          ),
        ],
      ),
    );
  }
}
