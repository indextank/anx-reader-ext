import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/search_result_model.dart';
import 'package:anx_reader/models/toc_item.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/providers/toc_panel.dart';
import 'package:anx_reader/providers/toc_search.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_reading_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 目录加载中占位 Key。
const tocLoadingStateKey = ValueKey('toc-loading-state');

/// 目录加载失败（带重试入口）Key。
const tocErrorStateKey = ValueKey('toc-error-state');

/// 目录空态 Key。
const tocEmptyStateKey = ValueKey('toc-empty-state');

/// 目录内容宽度低于该值切换紧凑排版（隐藏百分比、压缩状态区、
/// 收窄层级缩进），避免固定侧栏在窄屏上的溢出。
const tocCompactContentWidth = 120.0;

/// 目录内容宽度低于该值隐藏"定位当前章节"按钮（搜索框优先保留）。
const tocLocateMinContentWidth = 120.0;

/// 目录内容宽度低于该值时连搜索框也隐藏（极窄固定侧栏）。
const tocSearchMinContentWidth = 64.0;

class BookToc extends ConsumerStatefulWidget {
  const BookToc({
    super.key,
    required this.epubPlayerKey,
    required this.hideAppBarAndBottomBar,
    required this.closeDrawer,
    this.onRetryToc,
  });

  final GlobalKey<EpubPlayerState> epubPlayerKey;
  final Function hideAppBarAndBottomBar;
  final VoidCallback closeDrawer;

  /// 加载失败时的重试回调；为空时回退到书页播放器的 refreshToc。
  final Future<void> Function()? onRetryToc;

  @override
  ConsumerState<BookToc> createState() => _BookTocState();
}

class _BookTocState extends ConsumerState<BookToc> {
  final TextEditingController searchBarController = TextEditingController();
  final ScrollController searchResultsScrollController = ScrollController();
  late List<TocItem> tocItems;
  List<_VisibleTocEntry> _visibleItems = const [];
  final Set<String> _expandedItemKeys = {};
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  String? _lastAutoScrolledHref;
  String? _pendingScrollKey;
  bool _pendingScrollAnimated = false;
  bool _hasRestoredScrollPosition = false;

  @override
  void initState() {
    super.initState();
    searchBarController.text = ref.read(tocSearchProvider).query ?? '';
    // Add listener to save scroll position
    searchResultsScrollController.addListener(_saveScrollPosition);
  }

  void _saveScrollPosition() {
    if (searchResultsScrollController.hasClients) {
      ref.read(tocSearchProvider.notifier).updateScrollOffset(
            searchResultsScrollController.offset,
          );
    }
  }

  @override
  void dispose() {
    searchBarController.dispose();
    searchResultsScrollController.dispose();
    super.dispose();
  }

  /// 加载失败后的重试：优先使用外部注入的回调（阅读页负责重新向书页
  /// 请求目录）；独立使用本 widget 时回退到播放器刷新 + loading 状态。
  Future<void> _retryToc() async {
    final onRetry = widget.onRetryToc;
    if (onRetry != null) {
      await onRetry();
      return;
    }
    ref.read(tocLoadStatusProvider.notifier).beginLoading();
    widget.epubPlayerKey.currentState?.refreshToc();
  }

  /// 目录搜索框。
  ///
  /// [dense] 用于极窄的固定侧栏：去掉前置搜索图标、收窄内边距，使
  /// "搜索中"状态（尾部清除按钮）也不会在窄宽度下溢出。
  Widget _buildSearchBox(
    BuildContext context, {
    required bool isSearchActive,
    required bool dense,
  }) {
    return SizedBox(
      height: AppReadingTokens.searchFieldHeight,
      child: SearchBar(
        controller: searchBarController,
        shadowColor: const WidgetStatePropertyAll<Color>(AppColors.transparent),
        padding: WidgetStatePropertyAll<EdgeInsets>(
          dense ? AppSpacing.horizontal8 : AppSpacing.horizontal16,
        ),
        leading: dense ? null : const Icon(Icons.search),
        trailing: [
          if (isSearchActive)
            AppIconButton(
              icon: Icons.close,
              tooltip: L10n.of(context).readingTocClearSearch,
              semanticLabel: L10n.of(context).readingTocClearSearch,
              onPressed: () {
                searchBarController.clear();
                widget.epubPlayerKey.currentState?.clearSearch();
              },
            ),
        ],
        onSubmitted: (value) {
          final trimmed = value.trim();
          if (trimmed.isEmpty) {
            searchBarController.clear();
            widget.epubPlayerKey.currentState?.clearSearch();
          } else {
            widget.epubPlayerKey.currentState?.search(trimmed);
          }
        },
      ),
    );
  }

  String _keyForItem(TocItem item) => '${item.id}_${item.href}';

  List<TocItem>? _findPath(List<TocItem> items, String href) {
    for (final item in items) {
      if (item.href == href) {
        return [item];
      }
      final nested = _findPath(item.subitems, href);
      if (nested != null) {
        return [item, ...nested];
      }
    }
    return null;
  }

  void _ensureItemVisible(TocItem item, {bool animated = false}) {
    if (!mounted) {
      return;
    }
    final path = _findPath(tocItems, item.href);
    if (path == null) {
      return;
    }

    final keysToExpand = <String>{};
    for (final ancestor in path) {
      if (ancestor.subitems.isNotEmpty) {
        final key = _keyForItem(ancestor);
        if (!_expandedItemKeys.contains(key)) {
          keysToExpand.add(key);
        }
      }
    }

    void scheduleScroll() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        final key = _keyForItem(item);
        if (!_itemScrollController.isAttached) {
          _pendingScrollKey = key;
          _pendingScrollAnimated = animated;
          return;
        }
        final index = _visibleItems.indexWhere((entry) => entry.key == key);
        if (index == -1) {
          _pendingScrollKey = key;
          _pendingScrollAnimated = animated;
          return;
        }
        _pendingScrollKey = null;
        _pendingScrollAnimated = false;
        final duration = animated
            ? const Duration(milliseconds: 250)
            : const Duration(milliseconds: 1);
        _itemScrollController.scrollTo(
          index: index,
          duration: duration,
          curve: Curves.easeInOut,
          alignment: 0.0,
        );
      });
    }

    if (keysToExpand.isNotEmpty) {
      setState(() {
        _expandedItemKeys.addAll(keysToExpand);
      });
    }
    scheduleScroll();
  }

  void _scrollToCurrent({bool animated = false}) {
    final currentHref = widget.epubPlayerKey.currentState?.chapterHref ?? '';
    if (currentHref.isEmpty) {
      return;
    }
    final path = _findPath(tocItems, currentHref);
    if (path == null || path.isEmpty) {
      return;
    }
    _ensureItemVisible(path.last, animated: animated);
  }

  void _toggleExpanded(TocItem item) {
    final key = _keyForItem(item);
    setState(() {
      if (_expandedItemKeys.contains(key)) {
        _expandedItemKeys.remove(key);
      } else {
        _expandedItemKeys.add(key);
      }
    });
  }

  void _pruneExpandedKeys(List<TocItem> items) {
    final validKeys = <String>{};

    void collect(List<TocItem> children) {
      for (final child in children) {
        final key = _keyForItem(child);
        validKeys.add(key);
        if (child.subitems.isNotEmpty) {
          collect(child.subitems);
        }
      }
    }

    collect(items);
    _expandedItemKeys.removeWhere((key) => !validKeys.contains(key));
  }

  List<_VisibleTocEntry> _buildVisibleItems(List<TocItem> items) {
    final entries = <_VisibleTocEntry>[];

    void visit(List<TocItem> nodes, int depth) {
      for (final node in nodes) {
        final key = _keyForItem(node);
        final isExpanded = _expandedItemKeys.contains(key);
        entries.add(
          _VisibleTocEntry(
            item: node,
            key: key,
            depth: depth,
            isExpanded: isExpanded,
          ),
        );
        if (node.subitems.isNotEmpty && isExpanded) {
          visit(node.subitems, depth + 1);
        }
      }
    }

    visit(items, 0);
    return entries;
  }

  void _fulfillPendingScrollIfPossible() {
    if (!mounted) {
      return;
    }
    final pendingKey = _pendingScrollKey;
    if (pendingKey == null) {
      return;
    }
    if (!_itemScrollController.isAttached) {
      return;
    }

    final index = _visibleItems.indexWhere((entry) => entry.key == pendingKey);
    if (index == -1) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!_itemScrollController.isAttached) {
        return;
      }
      _pendingScrollKey = null;
      final duration = _pendingScrollAnimated
          ? const Duration(milliseconds: 250)
          : const Duration(milliseconds: 1);
      _pendingScrollAnimated = false;
      _itemScrollController.scrollTo(
        index: index,
        duration: duration,
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tocContent = ref.watch(tocContentProvider);
    tocItems = tocContent.valueOrNull ?? const <TocItem>[];
    _pruneExpandedKeys(tocItems);
    _visibleItems = _buildVisibleItems(tocItems);
    _fulfillPendingScrollIfPossible();
    final tocSearchState = ref.watch(tocSearchProvider);
    final currentQuery = tocSearchState.query ?? '';
    if (searchBarController.text != currentQuery) {
      searchBarController.value = TextEditingValue(
        text: currentQuery,
        selection: TextSelection.collapsed(offset: currentQuery.length),
      );
    }
    final isSearchActive = tocSearchState.isActive;
    final searchResults = tocSearchState.results;
    final showSearchProgress = tocSearchState.isSearching;
    final progressValue = tocSearchState.progress <= 0.0
        ? null
        : tocSearchState.progress.clamp(0.0, 1.0);

    // Restore scroll position when search results are available (only once)
    if (isSearchActive &&
        searchResults.isNotEmpty &&
        !_hasRestoredScrollPosition &&
        tocSearchState.scrollOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && searchResultsScrollController.hasClients) {
          final targetOffset = tocSearchState.scrollOffset.clamp(
            0.0,
            searchResultsScrollController.position.maxScrollExtent,
          );
          searchResultsScrollController.jumpTo(targetOffset);
          _hasRestoredScrollPosition = true;
        }
      });
    }

    // Reset the flag when search becomes inactive
    if (!isSearchActive && _hasRestoredScrollPosition) {
      _hasRestoredScrollPosition = false;
    }

    final currentHref = widget.epubPlayerKey.currentState?.chapterHref ?? '';
    final currentPath = currentHref.isEmpty
        ? <TocItem>[]
        : (_findPath(tocItems, currentHref) ?? <TocItem>[]);

    if (!isSearchActive &&
        currentHref.isNotEmpty &&
        currentHref != _lastAutoScrolledHref &&
        currentPath.isNotEmpty) {
      _lastAutoScrolledHref = currentHref;
      final target = currentPath.last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _ensureItemVisible(target);
      });
    }

    final selectedKeys = currentPath.map(_keyForItem).toSet();
    final currentState = widget.epubPlayerKey.currentState;
    final currentProgress = currentState == null
        ? ''
        : '${currentState.chapterCurrentPage} / ${currentState.chapterTotalPages}';

    final locatingButton = AppIconButton(
      icon: Icons.my_location,
      tooltip: L10n.of(context).readingTocLocateCurrent,
      semanticLabel: L10n.of(context).readingTocLocateCurrent,
      onPressed: () {
        _scrollToCurrent(animated: true);
      },
    );

    final searchResult = Column(
      children: [
        const SizedBox(height: 6.0),
        if (showSearchProgress)
          LinearProgressIndicator(
            value: progressValue,
          ),
        Expanded(
          child: searchResults.isEmpty
              ? showSearchProgress
                  ? const SizedBox()
                  : AppEmptyState(
                      compact: true,
                      title: L10n.of(context).commonEmpty,
                      icon: Icons.search_off,
                    )
              : ListView.builder(
                  controller: searchResultsScrollController,
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    return searchResultWidget(
                      searchResult: searchResults[index],
                      hideAppBarAndBottomBar: widget.hideAppBarAndBottomBar,
                      epubPlayerKey: widget.epubPlayerKey,
                      closeDrawer: widget.closeDrawer,
                    );
                  },
                ),
        ),
      ],
    );
    // 目录区域统一承载 loading / error / empty / 数据四种状态：
    // 三种非数据状态同样占满剩余空间（不留下空白），固定侧栏内保持一致。
    // 固定侧栏在窄屏下远窄于悬浮抽屉，因此按可用宽度做紧凑降级：
    // 隐藏定位按钮、搜索框切紧凑样式、状态区改用 compact 排版、列表项
    // 限制百分比宽度，保证极窄宽度下不会出现 RenderFlex / ListTile 溢出。
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth;
        final compact = contentWidth < tocCompactContentWidth;
        final header = <Widget>[
          if (contentWidth >= tocSearchMinContentWidth)
            Expanded(
              child: _buildSearchBox(
                context,
                isSearchActive: isSearchActive,
                dense: compact,
              ),
            ),
          if (!isSearchActive && contentWidth >= tocLocateMinContentWidth)
            locatingButton,
        ];
        final columnChildren = <Widget>[];

        final Widget browseContent;
        if (isSearchActive) {
          browseContent = searchResult;
        } else if (tocContent.isLoading && !tocContent.hasValue) {
          browseContent = const Center(
            child: AppLoadingIndicator(key: tocLoadingStateKey),
          );
        } else if (tocContent.hasError && !tocContent.hasValue) {
          browseContent = AppErrorState(
            key: tocErrorStateKey,
            compact: compact,
            onRetry: _retryToc,
          );
        } else if (tocItems.isEmpty) {
          browseContent = AppEmptyState(
            key: tocEmptyStateKey,
            compact: compact,
            icon: Icons.menu_book_outlined,
          );
        } else {
          browseContent = ScrollablePositionedList.builder(
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            itemCount: _visibleItems.length,
            itemBuilder: (context, index) {
              final entry = _visibleItems[index];
              final tocItem = entry.item;
              final key = entry.key;
              final isSelected = selectedKeys.contains(key);
              final isCurrentLeaf =
                  currentHref == tocItem.href && tocItem.subitems.isEmpty;

              return TocItemWidget(
                tocItem: tocItem,
                depth: entry.depth,
                isExpanded: entry.isExpanded,
                isSelected: isSelected,
                showProgress: isCurrentLeaf,
                progressText: currentProgress,
                compact: compact,
                onToggle: tocItem.subitems.isEmpty
                    ? null
                    : () => _toggleExpanded(tocItem),
                onTap: () {
                  widget.hideAppBarAndBottomBar(false);
                  widget.epubPlayerKey.currentState?.goToHref(tocItem.href);
                  widget.closeDrawer();
                },
              );
            },
          );
        }

        if (header.isNotEmpty) {
          columnChildren.add(Row(children: header));
        }
        columnChildren.add(Expanded(child: browseContent));
        return Column(children: columnChildren);
      },
    );
  }
}

Widget searchResultWidget({
  required SearchResultModel searchResult,
  required Function hideAppBarAndBottomBar,
  required GlobalKey<EpubPlayerState> epubPlayerKey,
  required VoidCallback closeDrawer,
}) {
  bool isExpanded = true;
  return StatefulBuilder(
    builder: (context, setState) {
      final matchStyle = TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
      );
      final prePostStyle = TextStyle(color: AppReadingTokens.muted(context));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppButton(
            variant: AppButtonVariant.text,
            onPressed: () => setState(() => isExpanded = !isExpanded),
            icon: isExpanded ? Icons.expand_less : Icons.expand_more,
            label: '${searchResult.label} (${searchResult.subitems.length})',
          ),
          if (isExpanded)
            for (var subItem in searchResult.subitems)
              AppCard(
                margin: AppReadingTokens.listItemGap,
                padding: AppSpacing.symmetric(vertical: 8, horizontal: 12),
                onTap: () {
                  hideAppBarAndBottomBar(false);
                  epubPlayerKey.currentState!.goToCfi(subItem.cfi);
                  closeDrawer();
                },
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: subItem.pre, style: prePostStyle),
                      TextSpan(text: subItem.match, style: matchStyle),
                      TextSpan(text: subItem.post, style: prePostStyle),
                    ],
                  ),
                ),
              ),
        ],
      );
    },
  );
}

class TocItemWidget extends StatelessWidget {
  const TocItemWidget({
    super.key,
    required this.tocItem,
    required this.depth,
    required this.isExpanded,
    required this.isSelected,
    required this.showProgress,
    required this.progressText,
    required this.onToggle,
    required this.onTap,
    this.compact = false,
  });

  final TocItem tocItem;
  final int depth;
  final bool isExpanded;
  final bool isSelected;
  final bool showProgress;
  final String progressText;
  final VoidCallback? onToggle;
  final VoidCallback onTap;

  /// 窄屏（固定侧栏）紧凑排版：隐藏右侧百分比、收窄层级缩进，
  /// 避免 ListTile 在极窄宽度下出现 "Trailing/Leading consumes the
  /// entire tile width" 断言。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 百分比宽度限制在列表项宽度的 35% 内，超高文字缩放/深层缩进
        // 时省略而不是撑满整行，避免 ListTile 的 "Trailing widget
        // consumes the entire tile width" 断言。
        final trailingMaxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth * 0.35
            : null;
        final showPercentage = !compact && trailingMaxWidth != null;
        return AppListTile(
          title: tocItem.label.trim(),
          subtitle: showProgress ? progressText : null,
          selected: isSelected,
          semanticLabel: tocItem.label.trim(),
          contentPadding: AppSpacing.only(
            left: depth * (compact ? 8 : AppReadingTokens.tocIndent),
            right: AppSpacing.tokens.s8,
          ),
          leading: tocItem.subitems.isEmpty
              ? null
              : AppIconButton(
                  icon: isExpanded ? Icons.expand_less : Icons.expand_more,
                  tooltip: isExpanded
                      ? L10n.of(context).readingTocCollapse
                      : L10n.of(context).readingTocExpand,
                  semanticLabel: isExpanded
                      ? L10n.of(context).readingTocCollapse
                      : L10n.of(context).readingTocExpand,
                  onPressed: onToggle,
                ),
          trailing: showPercentage
              ? ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: trailingMaxWidth),
                  child: Text(
                    tocItem.percentage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : AppReadingTokens.muted(context),
                        ),
                  ),
                )
              : null,
          onTap: onTap,
        );
      },
    );
  }
}

class _VisibleTocEntry {
  const _VisibleTocEntry({
    required this.item,
    required this.key,
    required this.depth,
    required this.isExpanded,
  });

  final TocItem item;
  final String key;
  final int depth;
  final bool isExpanded;
}
