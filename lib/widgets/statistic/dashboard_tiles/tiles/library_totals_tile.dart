import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/statictics_summary_value.dart';
import 'package:anx_reader/theme/app_radius.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/widgets/common/async_skeleton_wrapper.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_async_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LibraryTotalsTile extends StatisticsDashboardTileBase {
  const LibraryTotalsTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.libraryTotals,
      title: l10n.tileLibraryTotalsTitle,
      description: l10n.tileLibraryTotalsDescription,
      columnSpan: 4,
      rowSpan: 1,
      icon: Icons.menu_book_outlined,
    );
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final booksProvider =
        StaticticsSummaryValueProvider(StatisticType.totalBooks);
    final datesProvider =
        StaticticsSummaryValueProvider(StatisticType.totalDates);
    final notesProvider =
        StaticticsSummaryValueProvider(StatisticType.totalNotes);
    return DashboardAsyncValue<List<dynamic>>(
      value: combineAsyncValues([
        ref.watch(booksProvider),
        ref.watch(datesProvider),
        ref.watch(notesProvider),
      ]),
      mock: const [0, 0, 0],
      onRetry: () async {
        ref.invalidate(booksProvider);
        ref.invalidate(datesProvider);
        ref.invalidate(notesProvider);
      },
      builder: (data, _) {
        return Row(
          children: [
            Expanded(
              child: _NumberTile(
                icon: Icons.auto_stories,
                label: l10n.statisticBooksRead(data[0] as int),
              ),
            ),
            const SizedBox(width: AppStatisticsTokens.librarySpacing),
            Expanded(
              child: _NumberTile(
                icon: Icons.calendar_today,
                label: l10n.statisticDaysOfReading(data[1] as int),
              ),
            ),
            const SizedBox(width: AppStatisticsTokens.librarySpacing),
            Expanded(
              child: _NumberTile(
                icon: Icons.note_alt_outlined,
                label: l10n.statisticNotes(data[2] as int),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NumberTile extends StatelessWidget {
  const _NumberTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppStatisticsTokens.libraryTilePadding,
      decoration: BoxDecoration(
        borderRadius: AppRadius.border12,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: AppStatisticsTokens.libraryIconSize),
          const SizedBox(height: AppStatisticsTokens.libraryLabelSpacing),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
