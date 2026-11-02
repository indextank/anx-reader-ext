import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/page/book_notes_page.dart';
import 'package:anx_reader/providers/notes_page_current_book.dart';
import 'package:anx_reader/providers/notes_statistics.dart';
import 'package:anx_reader/theme/app_page_tokens.dart';
import 'package:anx_reader/theme/app_spacing.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/highlight_digit.dart';
import 'package:anx_reader/widgets/tips/notes_tips.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  late final ScrollController _scrollController;
  late final bool _ownsScrollController;

  @override
  void initState() {
    super.initState();
    _ownsScrollController = widget.controller == null;
    _scrollController = widget.controller ?? ScrollController();
  }

  @override
  void dispose() {
    if (_ownsScrollController) _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppSafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > AppNotesTokens.wideBreakpoint) {
            return Row(
              children: [
                Expanded(
                  flex: 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      notesStatistic(),
                      bookNotesList(false),
                    ],
                  ),
                ),
                const VerticalDivider(
                  thickness: AppNotesTokens.dividerSize,
                  width: AppNotesTokens.dividerSize,
                ),
                const Expanded(
                  flex: 2,
                  child: NotesDetail(),
                ),
              ],
            );
          } else {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                notesStatistic(),
                bookNotesList(true),
              ],
            );
          }
        },
      ),
    );
  }

  Widget notesStatistic() {
    final notesStats = ref.watch(notesStatisticsProvider);

    final digitStyle = Theme.of(context).textTheme.headlineSmall!;
    final textStyle = Theme.of(context)
        .textTheme
        .titleMedium!
        .copyWith(fontFamily: 'SourceHanSerif');

    return notesStats.when(
      data: (data) {
        return Padding(
          padding: AppNotesTokens.statisticsPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              highlightDigit(
                context,
                L10n.of(context).notesNotesAcross(data['numberOfNotes']!),
                textStyle,
                digitStyle,
              ),
              highlightDigit(
                context,
                L10n.of(context).notesBooks(data['numberOfBooks']!),
                textStyle,
                digitStyle,
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: AppLoadingIndicator()),
      error: (error, stack) => AppErrorState(
        onRetry: () async {
          ref.invalidate(notesStatisticsProvider);
          await ref.read(notesStatisticsProvider.future);
        },
      ),
    );
  }

  Widget bookNotesList(bool isMobile) {
    final bookIdAndNotes = ref.watch(bookIdAndNotesProvider);

    return bookIdAndNotes.when(
      data: (data) {
        return data.isEmpty
            ? const Expanded(child: Center(child: NotesTips()))
            : Expanded(
                child: ListView.builder(
                    padding: AppNotesTokens.listPadding,
                    controller: _scrollController,
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      return bookNotesItem(
                        book: data[index]['book']!,
                        numberOfNotes: data[index]['numberOfNotes']!,
                        isMobile: isMobile,
                        readingTime: data[index]['readingTime']!,
                      );
                    }),
              );
      },
      loading: () => const Expanded(
        child: Center(child: AppLoadingIndicator()),
      ),
      error: (error, stack) => Expanded(
        child: AppErrorState(
          onRetry: () async {
            ref.invalidate(bookIdAndNotesProvider);
            await ref.read(bookIdAndNotesProvider.future);
          },
        ),
      ),
    );
  }

  Widget bookNotesItem({
    required Book book,
    required int numberOfNotes,
    required bool isMobile,
    required int readingTime,
  }) {
    final digitStyle = Theme.of(context).textTheme.displaySmall!;
    final textStyle = Theme.of(context).textTheme.titleLarge!;
    final titleStyle = Theme.of(context).textTheme.titleMedium!.copyWith(
          overflow: TextOverflow.ellipsis,
          fontFamily: 'SourceHanSerif',
          fontWeight: FontWeight.bold,
        );
    final readingTimeStyle = Theme.of(context).textTheme.bodySmall!.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
    return AppCard(
      margin: AppNotesTokens.listCardMargin,
      padding: AppNotesTokens.listCardPadding,
      onTap: () {
        if (isMobile) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BookNotesPage(
                book: book,
                numberOfNotes: numberOfNotes,
                isMobile: true,
              ),
            ),
          );
        } else {
          ref
              .read(notesPageCurrentBookProvider.notifier)
              .setData(book, numberOfNotes);
        }
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                highlightDigit(
                  context,
                  L10n.of(context).notesNotes(numberOfNotes),
                  textStyle,
                  digitStyle,
                ),
                SizedBox(height: AppSpacing.tokens.s8),
                Text(book.title, style: titleStyle, maxLines: 1),
                SizedBox(height: AppSpacing.tokens.s16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: AppNotesTokens.metadataIconSize,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(width: AppSpacing.tokens.s4),
                      Text(
                        convertSeconds(readingTime),
                        style: readingTimeStyle,
                      ),
                      Text(' | ', style: readingTimeStyle),
                      Icon(
                        Icons.bar_chart,
                        size: AppNotesTokens.metadataIconSize,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      SizedBox(width: AppSpacing.tokens.s4),
                      Text(
                        '${(book.readingPercentage * 100).toStringAsFixed(1)}%',
                        style: readingTimeStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Hero(
            tag: isMobile
                ? book.coverFullPath
                : '${book.coverFullPath}notMobile',
            child: BookCover(
              book: book,
              height: AppNotesTokens.listCoverHeight,
              width: AppNotesTokens.listCoverWidth,
              radius: AppNotesTokens.listCoverRadius,
            ),
          ),
        ],
      ),
    );
  }
}

class NotesDetail extends ConsumerWidget {
  const NotesDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(notesPageCurrentBookProvider).when(
          data: (current) {
            return BookNotesPage(
                isMobile: false,
                book: current.book,
                numberOfNotes: current.numberOfNotes);
          },
          loading: () => const Center(child: AppLoadingIndicator()),
          error: (error, stack) => AppErrorState(
            onRetry: () async {
              ref.invalidate(notesPageCurrentBookProvider);
              await ref.read(notesPageCurrentBookProvider.future);
            },
          ),
        );
  }
}
