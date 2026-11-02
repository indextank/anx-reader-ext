import 'dart:math';

import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/hint_key.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/widgets/hint/hint_banner.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/dashboard_tile_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staggered_reorderable/staggered_reorderable.dart';

class StatisticsDashboard extends ConsumerWidget {
  const StatisticsDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tilesState = ref.watch(dashboardTilesProvider);
    final notifier = ref.read(dashboardTilesProvider.notifier);
    final workingTiles = tilesState.workingTiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HintBanner(
          icon: const Icon(Icons.drag_handle),
          hintKey: HintKey.statisticsDashboardRearrange,
          margin: AppStatisticsTokens.dashboardHintMargin,
          child: Text(L10n.of(context).statisticsDashboardHint),
        ),
        if (workingTiles.isEmpty)
          AppEmptyState(
            title: L10n.of(context).statisticsDashboardEmpty,
            actionLabel: L10n.of(context).statisticsDashboardAddCard,
            onAction: () => notifier.reorder,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisUnits =
                  _calculateColumnUnits(constraints.maxWidth);
              return StaggeredReorderableView.customer(
                columnNum: crossAxisUnits,
                spacing: AppStatisticsTokens.dashboardSpacing,
                canDrag: true,
                children: _buildReorderableItems(
                  context,
                  workingTiles,
                  crossAxisUnits,
                ),
                onReorder: notifier.reorder,
                fixedCellHeight: AppStatisticsTokens.dashboardCellHeight,
              );
            },
          ),
      ],
    );
  }

  List<ReorderableItem> _buildReorderableItems(
    BuildContext context,
    List<StatisticsDashboardTileType> workingTiles,
    int columnUnits,
  ) {
    return workingTiles
        .map(
          (type) => dashboardTileRegistry[type]!.buildReorderableItem(
            context: context,
          ),
        )
        .toList(growable: false);
  }

  int _calculateColumnUnits(double width) {
    return max(
      AppStatisticsTokens.dashboardMinColumnUnits,
      (width ~/ AppStatisticsTokens.dashboardColumnWidth) * 2,
    );
  }
}
