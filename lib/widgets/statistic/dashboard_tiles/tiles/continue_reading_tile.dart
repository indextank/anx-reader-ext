import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/providers/last_read_book_provider.dart';
import 'package:anx_reader/service/book.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/utils/date/relative_time_formatter.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_async_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ContinueReadingTile extends StatisticsDashboardTileBase {
  const ContinueReadingTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.continueReading,
      title: l10n.tileContinueReadingTitle,
      description: l10n.tileContinueReadingDescription,
      columnSpan: 2,
      rowSpan: 1,
      icon: Icons.play_arrow_rounded,
    );
  }

  @override
  bool get canFlip => false;

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerIcon(context, Icons.play_circle_outline);
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    Future<void> retry() => ref.read(lastReadBookProvider.notifier).refresh();
    return DashboardAsyncValue<LastReadBookData?>(
      value: ref.watch(lastReadBookProvider),
      mock: LastReadBookData(book: Book.mock(), lastReadDate: DateTime.now()),
      onRetry: retry,
      builder: (data, _) {
        if (data == null) {
          return AppEmptyState(
            compact: true,
            icon: Icons.menu_book_outlined,
            title: L10n.of(context).tileContinueReadingEmptyState,
            actionLabel: L10n.of(context).commonRefresh,
            onAction: () => retry(),
          );
        }
        final book = data.book;
        return _ContinueReadingContent(
          book: book,
          lastReadDate: data.lastReadDate,
          heroTag: 'continue_reading_${book.id}',
        );
      },
    );
  }

  @override
  void onTap(BuildContext context, WidgetRef ref) {
    final data = ref.read(lastReadBookProvider).maybeWhen(
          data: (value) => value,
          orElse: () => null,
        );
    final book = data?.book;
    if (book == null) return;
    pushToReadingPage(
      ref,
      context,
      book,
      heroTag: 'continue_reading_${book.id}',
    );
  }
}

class _ContinueReadingContent extends StatelessWidget {
  const _ContinueReadingContent({
    required this.book,
    required this.lastReadDate,
    required this.heroTag,
  });

  final Book book;
  final DateTime? lastReadDate;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = lastReadDate == null
        ? L10n.of(context).tileContinueReadingNoTimestamp
        : RelativeTimeFormatter.format(lastReadDate!);
    return Row(
      children: [
        Hero(
          tag: heroTag,
          child: BookCover(
            book: book,
            width: AppStatisticsTokens.continueCoverWidth,
            radius: AppStatisticsTokens.continueCoverRadius,
          ),
        ),
        const SizedBox(width: AppStatisticsTokens.continueSpacing),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppStatisticsTokens.continueTextSpacing),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AppStatisticsTokens.continueTextSpacing),
              Text(subtitle, style: theme.textTheme.labelSmall),
              const SizedBox(
                  height: AppStatisticsTokens.continueProgressSpacing),
              LinearProgressIndicator(
                value: book.readingPercentage.clamp(0, 1),
                minHeight: AppStatisticsTokens.progressHeight,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
