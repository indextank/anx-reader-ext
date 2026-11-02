import 'package:anx_reader/providers/statictics_summary_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_async_value.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_base.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_metadata.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/widgets/mini_metric.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotesTotalTile extends StatisticsDashboardTileBase {
  const NotesTotalTile();

  @override
  StatisticsDashboardTileMetadata get metadata {
    final l10n = l10nLocal;
    return StatisticsDashboardTileMetadata(
      type: StatisticsDashboardTileType.notesTotal,
      title: l10n.tileNotesTotalTitle,
      description: l10n.tileNotesTotalDescription,
      columnSpan: 1,
      rowSpan: 1,
      icon: Icons.note_alt_outlined,
    );
  }

  @override
  Widget buildContent(BuildContext context, WidgetRef ref) {
    final provider = StaticticsSummaryValueProvider(StatisticType.totalNotes);
    return DashboardAsyncValue<int>(
      value: ref.watch(provider),
      mock: 120,
      onRetry: () async => ref.invalidate(provider),
      builder: (count, _) => DashboardMiniMetric(
        value: count,
        label: l10nLocal.tileNotesTotalUnit,
        icon: metadata.icon,
      ),
    );
  }
}
