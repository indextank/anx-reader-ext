import 'package:anx_reader/dao/book.dart';
import 'package:anx_reader/dao/reading_time.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/chart_mode.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/book_detail.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/utils/date/week_of_year.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/hint/hint_banner.dart';
import 'package:anx_reader/widgets/statistic/statistic_card.dart';
import 'package:anx_reader/widgets/statistic/statistics_dashboard.dart';
import 'package:anx_reader/widgets/statistic/statistics_dashboard_title.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class StatisticPage extends StatefulWidget {
  const StatisticPage({
    super.key,
    this.controller,
    this.bookLoader,
    this.onDelete,
  });

  final ScrollController? controller;
  final StatisticBookLoader? bookLoader;
  final Future<void> Function(List<int> bookIds)? onDelete;

  @override
  State<StatisticPage> createState() => _StatisticPageState();
}

class _StatisticPageState extends State<StatisticPage> {
  late final bool _ownsScrollController = widget.controller == null;
  late final ScrollController _scrollController =
      widget.controller ?? ScrollController();
  final List<int> _deleteBookIds = [];

  void _markForDeletion(int bookId) {
    if (_deleteBookIds.contains(bookId)) return;
    setState(() => _deleteBookIds.add(bookId));
  }

  void _undoDeletion(int bookId) {
    setState(() => _deleteBookIds.remove(bookId));
  }

  DateBooks _dateBooks() {
    return DateBooks(
      bookLoader: widget.bookLoader,
      pendingDeletionIds: _deleteBookIds,
      onMarkForDeletion: _markForDeletion,
      onUndoDeletion: _undoDeletion,
    );
  }

  @override
  void dispose() {
    if (_deleteBookIds.isNotEmpty) {
      final onDelete = widget.onDelete;
      final bookIds = List<int>.unmodifiable(_deleteBookIds);
      if (onDelete != null) {
        onDelete(bookIds);
      } else {
        readingTimeDao.deleteReadingTimeByBookId(bookIds);
      }
    }
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppSafeArea(
        bottom: false,
        child: Padding(
          padding: AppStatisticsTokens.pagePadding,
          child: Column(
            children: [
              const StatisticsDashboardTitle(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >
                        AppStatisticsTokens.wideBreakpoint) {
                      return Row(
                        children: [
                          const Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  StatisticsDashboard(),
                                  StatisticCard(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: AppStatisticsTokens.wideSpacing,
                          ),
                          Expanded(
                            child: ListView(
                              controller: _scrollController,
                              children: [_dateBooks()],
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView(
                      padding: AppStatisticsTokens.listPadding,
                      controller: _scrollController,
                      children: [
                        const StatisticsDashboard(),
                        const StatisticCard(),
                        const SizedBox(
                          height: AppStatisticsTokens.sectionSpacing,
                        ),
                        _dateBooks(),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef StatisticBookLoader = Future<Book> Function(int bookId);

class DateBooks extends ConsumerStatefulWidget {
  const DateBooks({
    super.key,
    this.bookLoader,
    this.onDelete,
    this.pendingDeletionIds,
    this.onMarkForDeletion,
    this.onUndoDeletion,
  });

  final StatisticBookLoader? bookLoader;
  final Future<void> Function(List<int> bookIds)? onDelete;
  final List<int>? pendingDeletionIds;
  final void Function(int bookId)? onMarkForDeletion;
  final void Function(int bookId)? onUndoDeletion;

  @override
  ConsumerState<DateBooks> createState() => _DateBooksState();
}

class _DateBooksState extends ConsumerState<DateBooks> {
  final List<int> localDeleteBookIds = [];

  List<int> get deleteBookIds =>
      widget.pendingDeletionIds ?? localDeleteBookIds;

  @override
  void dispose() {
    if (widget.pendingDeletionIds == null && deleteBookIds.isNotEmpty) {
      final onDelete = widget.onDelete;
      if (onDelete != null) {
        onDelete(List.unmodifiable(deleteBookIds));
      } else {
        readingTimeDao.deleteReadingTimeByBookId(deleteBookIds);
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statisticData = ref.watch(statisticDataProvider);

    Widget dragToDelete(Widget child, int bookId) {
      return StatefulBuilder(builder: (context, localSetState) {
        if (deleteBookIds.contains(bookId)) {
          return AppCard(
            margin: AppStatisticsTokens.cardMargin,
            padding: AppStatisticsTokens.cardPadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppStatisticsTokens.deletedCardHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: AppStatisticsTokens.sectionSpacing),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.delete,
                              size: AppStatisticsTokens.deleteIconSize,
                            ),
                            Text(
                              L10n.of(context).statisticDeletedRecords,
                              style: AppStatisticsTokens.deletedTitleStyle,
                            ),
                          ],
                        ),
                      ),
                      AppButton(
                        label: L10n.of(context).commonUndo,
                        onPressed: () {
                          final onUndo = widget.onUndoDeletion;
                          if (onUndo != null) {
                            onUndo(bookId);
                          } else {
                            localSetState(
                              () => localDeleteBookIds.remove(bookId),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppStatisticsTokens.sectionSpacing),
                  const Divider(),
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: AppStatisticsTokens.infoIconSize,
                      ),
                      const SizedBox(width: AppStatisticsTokens.contentSpacing),
                      Expanded(
                        child: Text(
                          L10n.of(context).statisticDeletedRecordsTips,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }
        final actionPane = ActionPane(
          motion: const StretchMotion(),
          children: [
            SlidableAction(
              onPressed: (context) async {
                final confirmed = await AppDialog.confirm(
                  context,
                  title: L10n.of(context).commonDelete,
                  message: L10n.of(context).statisticDeletedRecordsTips,
                  confirmLabel: L10n.of(context).commonDelete,
                  isDangerous: true,
                  dangerDescription:
                      L10n.of(context).statisticDeletedRecordsTips,
                );
                if (!confirmed || !mounted) return;
                final onMark = widget.onMarkForDeletion;
                if (onMark != null) {
                  onMark(bookId);
                } else if (!localDeleteBookIds.contains(bookId)) {
                  localSetState(() => localDeleteBookIds.add(bookId));
                }
              },
              icon: Icons.delete,
              label: L10n.of(context).commonDelete,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
          ],
        );
        return Slidable(
          key: ValueKey(bookId),
          startActionPane: actionPane,
          endActionPane: actionPane,
          child: child,
        );
      });
    }

    return AppAsyncValue(
      value: statisticData,
      onRetry: () async => ref.invalidate(statisticDataProvider),
      dataBuilder: (context, data) {
        final title = data.isSelectingDay
            ? data.date.toString().substring(0, 10)
            : data.mode == ChartMode.week
                ? weekOfYear(data.date)
                : data.mode == ChartMode.month
                    ? '${data.date.year}.${data.date.month}'
                    : data.mode == ChartMode.year
                        ? data.date.year.toString()
                        : L10n.of(context).statisticAllTime;

        final books = data.bookReadingTime;
        return Column(
          children: [
            Padding(
              padding: AppStatisticsTokens.titlePadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: AppStatisticsTokens.dateTitleStyle,
                    ),
                  ),
                ],
              ),
            ),
            if (books.isEmpty)
              AppEmptyState(
                title: L10n.of(context).statisticsTips_1,
                message: L10n.of(context).statisticsTips_2,
                icon: Icons.auto_stories_outlined,
              )
            else
              Column(
                children: [
                  HintBanner(
                    icon: const Icon(Icons.swipe_left),
                    hintKey: HintKey.statisticsSwipeToDelete,
                    margin: AppStatisticsTokens.cardMargin,
                    child: Text(L10n.of(context).statisticsSwipeToDeleteHint),
                  ),
                  ...books.map((bookMap) {
                    final book = bookMap.keys.first;
                    final readingTime = bookMap.values.first;
                    return dragToDelete(
                      BookStatisticItem(
                        bookId: book.id,
                        readingTime: readingTime,
                        bookLoader: widget.bookLoader,
                      ),
                      book.id,
                    );
                  }),
                ],
              ),
          ],
        );
      },
    );
  }
}

class BookStatisticItem extends StatefulWidget {
  const BookStatisticItem({
    super.key,
    required this.bookId,
    required this.readingTime,
    this.bookLoader,
  });

  final int bookId;
  final int readingTime;
  final StatisticBookLoader? bookLoader;

  @override
  State<BookStatisticItem> createState() => _BookStatisticItemState();
}

class _BookStatisticItemState extends State<BookStatisticItem> {
  Future<Book> _loadBook() {
    return widget.bookLoader?.call(widget.bookId) ??
        bookDao.selectBookById(widget.bookId);
  }

  late Future<Book> _bookFuture = _loadBook();

  Future<void> _retry() async {
    setState(() {
      _bookFuture = _loadBook();
    });
    await _bookFuture;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Book>(
      future: _bookFuture,
      builder: (context, snapshot) {
        final isDone = snapshot.connectionState == ConnectionState.done;
        if (snapshot.hasError || (isDone && !snapshot.hasData)) {
          return AppErrorState(onRetry: _retry);
        }
        if (!isDone) {
          return AppSkeleton(
            child: _BookStatisticContent(
              book: Book.mock(),
              readingTime: widget.readingTime,
            ),
          );
        }
        final book = snapshot.requireData;
        return _BookStatisticContent(
          book: book,
          readingTime: widget.readingTime,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => BookDetail(book: book)),
            );
          },
        );
      },
    );
  }
}

class _BookStatisticContent extends StatelessWidget {
  const _BookStatisticContent({
    required this.book,
    required this.readingTime,
    this.onTap,
  });

  final Book book;
  final int readingTime;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      margin: AppStatisticsTokens.cardMargin,
      padding: AppStatisticsTokens.cardPadding,
      onTap: onTap,
      child: Row(
        children: [
          Hero(
            tag: book.coverFullPath,
            child: BookCover(
              book: book,
              height: AppStatisticsTokens.coverHeight,
              width: AppStatisticsTokens.coverWidth,
              radius: AppStatisticsTokens.coverRadius,
            ),
          ),
          const SizedBox(width: AppStatisticsTokens.coverSpacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book.title, style: AppStatisticsTokens.bookTitleStyle),
                const SizedBox(height: AppStatisticsTokens.contentSpacing),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        book.author,
                        style: AppStatisticsTokens.bookAuthorStyle.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      convertSeconds(readingTime),
                      textAlign: TextAlign.end,
                      style: AppStatisticsTokens.bookReadingTimeStyle,
                    ),
                  ],
                ),
                const SizedBox(height: AppStatisticsTokens.progressSpacing),
                Row(
                  children: [
                    Expanded(
                      child: LinearProgressIndicator(
                        value: book.readingPercentage,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: AppStatisticsTokens.contentSpacing),
                    Text('${(book.readingPercentage * 100).toInt()} %'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
