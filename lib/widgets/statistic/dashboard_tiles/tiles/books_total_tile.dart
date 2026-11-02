import 'package:anx_reader/providers/statictics_summary_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_async_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/widgets/mini_metric.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BooksTotalTile extends StatisticsDashboardTileBase {
  const BooksTotalTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.booksTotal,
      title: l10n.tileBooksReadTitle,
      description: l10n.tileBooksReadDescription,
      columnSpan: 1,
      rowSpan: 1,
      icon: Icons.auto_stories_outlined,
    );
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final provider = StaticticsSummaryValueProvider(StatisticType.totalBooks);
    return DashboardAsyncValue<int>(
      value: ref.watch(provider),
      mock: 12,
      onRetry: () async => ref.invalidate(provider),
      builder: (count, _) => DashboardMiniMetric(
        value: count,
        label: l10nLocal.tileBooksReadUnit,
        icon: metadata.icon,
      ),
    );
  }
}
