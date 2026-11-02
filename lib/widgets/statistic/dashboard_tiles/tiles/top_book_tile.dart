import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/statistic_data_model.dart';
import 'package:anx_reader/providers/book_daily_reading_provider.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:anx_reader/widgets/bookshelf/book_cover.dart';
import 'package:anx_reader/widgets/statistic/book_reading_chart.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_async_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TopBookTile extends StatisticsDashboardTileBase {
  const TopBookTile();

  @override
  get metadata => StatisticsDashboardTileMetadata(
        type: StatisticsDashboardTileType.topBook,
        title: l10nLocal.tileTopBookTitle,
        description: l10nLocal.tileTopBookDescription,
        columnSpan: 4,
        rowSpan: 2,
        icon: Icons.bookmark_added_outlined,
      );

  @override
  Widget buildCorner(BuildContext context, WidgetRef ref) {
    return cornerIcon(context, Icons.favorite);
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    return DashboardAsyncValue<StatisticDataModel>(
      value: ref.watch(statisticDataProvider),
      mock: StatisticDataModel.mock(),
      onRetry: () async => ref.invalidate(statisticDataProvider),
      builder: (statisticData, _) {
        if (statisticData.bookReadingTime.isEmpty) {
          return AppEmptyState(
            compact: true,
            icon: Icons.auto_stories_outlined,
            title: L10n.of(context).statisticsTips_1,
          );
        }
        final entry = statisticData.bookReadingTime.first;
        final book = entry.keys.first;
        final seconds = entry.values.first;
        final dailyProvider = bookDailyReadingProvider(bookId: book.id);
        return Row(
          children: [
            BookCover(
              book: book,
              width: AppStatisticsTokens.topBookCoverWidth,
              radius: AppStatisticsTokens.topBookCoverRadius,
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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        convertSeconds(seconds),
                        textAlign: TextAlign.end,
                        style: AppStatisticsTokens.bookReadingTimeStyle,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppStatisticsTokens.contentSpacing),
                  Expanded(
                    child: DashboardAsyncValue(
                      value: ref.watch(dailyProvider),
                      mock: BookDailyReadingData.mock(),
                      onRetry: () async => ref.invalidate(dailyProvider),
                      builder: (bookReadingData, ready) => ready
                          ? Padding(
                              padding: AppStatisticsTokens.topBookChartPadding,
                              child: BookReadingChart(
                                cumulativeValues: bookReadingData.readingTimes,
                                dailySeconds: bookReadingData.readingTimes,
                                dates: bookReadingData.dates,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
