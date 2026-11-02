import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/providers/heatmap_data.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_heatmap_calendar/flutter_heatmap_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HeatmapChart extends ConsumerWidget {
  const HeatmapChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticData = ref.watch(heatmapDataProvider);
    return AppAsyncValue<Map<DateTime, int>>(
      value: statisticData,
      onRetry: () async => ref.invalidate(heatmapDataProvider),
      dataBuilder: (context, data) => data.isEmpty
          ? const AppEmptyState()
          : HeatMap(
              showColorTip: false,
              blockBorder: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: AppStatisticsTokens.heatmapBorderWidth,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
              defaultColor: Theme.of(context).colorScheme.surface,
              datasets: data,
              colorMode: ColorMode.opacity,
              showText: false,
              scrollable: true,
              colorsets: {1: Theme.of(context).colorScheme.primary},
              onClick: (value) {
                ref
                    .read(statisticDataProvider.notifier)
                    .setIsSelectingDay(true, value);
              },
            ),
    );
  }
}
