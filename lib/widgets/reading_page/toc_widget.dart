import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/widgets/reading_page/toc_pin_button.dart';
import 'package:anx_reader/widgets/reading_page/widgets/book_toc.dart';
import 'package:anx_reader/widgets/reading_page/widgets/bookmark.dart';
import 'package:flutter/material.dart';

/// 悬浮弹框（Drawer）内目录面板的稳定 Key。
const tocFloatingPanelKey = ValueKey('toc-floating-panel');

/// 固定侧栏内目录面板的稳定 Key。
const tocPinnedPanelKey = ValueKey('toc-pinned-panel');

class TocWidget extends StatefulWidget {
  const TocWidget({
    super.key,
    required this.epubPlayerKey,
    required this.hideAppBarAndBottomBar,
    required this.closeDrawer,
    this.onRetryToc,
  });

  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function hideAppBarAndBottomBar;

  /// 关闭悬浮弹框。固定侧栏形态下由阅读页保证为 no-op（目录保持可见）。
  final VoidCallback closeDrawer;

  /// 目录加载失败时的重试入口；为空时目录区域回退到书页播放器的
  /// refreshToc。
  final Future<void> Function()? onRetryToc;

  @override
  State<TocWidget> createState() => _TocWidgetState();
}

class _TocWidgetState extends State<TocWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: AppReadingTokens.searchFieldHeight,
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    Tab(text: L10n.of(context).readingContents),
                    Tab(text: L10n.of(context).readingBookmark),
                  ],
                ),
              ),
              // 标题栏右上角的目录固定开关（图标随状态切换）。
              Padding(
                padding: AppSpacing.horizontal8,
                child: const TocPinButton(),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: AppReadingTokens.contentPadding,
            child: TabBarView(
              controller: _tabController,
              children: [
                buildBookToc(),
                buildBookmarkList(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildBookmarkList() {
    return BookmarkWidget(
      epubPlayerKey: widget.epubPlayerKey,
      onNavigate: () {
        widget.hideAppBarAndBottomBar(false);
        widget.closeDrawer();
      },
    );
  }

  BookToc buildBookToc() {
    return BookToc(
      epubPlayerKey: widget.epubPlayerKey,
      hideAppBarAndBottomBar: widget.hideAppBarAndBottomBar,
      closeDrawer: widget.closeDrawer,
      onRetryToc: widget.onRetryToc,
    );
  }
}
