import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StatisticChart extends ConsumerStatefulWidget {
  const StatisticChart({
    super.key,
    required this.readingTime,
    required this.xLabels,
  });

  final List<int> readingTime;
  final List<String> xLabels;

  @override
  ConsumerState<StatisticChart> createState() => _StatisticChartState();
}

class _StatisticChartState extends ConsumerState<StatisticChart> {
  int? touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.readingTime.isEmpty || widget.xLabels.isEmpty) {
      return const AppEmptyState(compact: true);
    }
    final maximum = widget.readingTime.reduce(
          (value, element) => value > element ? value : element,
        ) *
        AppStatisticsTokens.chartMaxYFactor;
    return BarChart(
      BarChartData(
        barTouchData: _barTouchData(context),
        titlesData: _titlesData(context),
        borderData: FlBorderData(show: false),
        barGroups: _barGroups(context),
        gridData: const FlGridData(show: false),
        alignment: BarChartAlignment.spaceAround,
        maxY: maximum <= 0 ? AppStatisticsTokens.chartFallbackMaxY : maximum,
      ),
    );
  }

  BarTouchData _barTouchData(BuildContext context) {
    final topColor = Theme.of(context)
        .colorScheme
        .primary
        .withValues(alpha: AppStatisticsTokens.chartTopColorOpacity);
    return BarTouchData(
      enabled: true,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => AppColors.transparent,
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          if (touchedIndex != null && group.x.toInt() == touchedIndex) {
            return BarTooltipItem(
              convertSeconds(widget.readingTime[group.x.toInt()]),
              AppStatisticsTokens.chartAxisStyle.copyWith(color: topColor),
            );
          }
          return null;
        },
      ),
      touchCallback: (event, response) {
        if (response?.spot == null) return;
        setState(() {
          touchedIndex = response!.spot!.touchedBarGroupIndex;
          if (event is FlTapUpEvent) {
            if (widget.readingTime.length == 12) {
              ref
                  .read(statisticDataProvider.notifier)
                  .touchMonth(touchedIndex!);
            } else {
              ref
                  .read(statisticDataProvider.notifier)
                  .touchDay(widget.xLabels.length, touchedIndex!);
            }
          }
        });
      },
    );
  }

  FlTitlesData _titlesData(BuildContext context) => FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: AppStatisticsTokens.chartReservedSize,
            getTitlesWidget: (value, meta) => _getTitles(context, value, meta),
          ),
        ),
        leftTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      );

  List<BarChartGroupData> _barGroups(BuildContext context) {
    final bottomColor = Theme.of(context).colorScheme.primary;
    final topColor = bottomColor.withValues(
      alpha: AppStatisticsTokens.chartTopColorOpacity,
    );
    return [
      for (var index = 0; index < widget.readingTime.length; index++)
        BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: widget.readingTime[index].toDouble(),
              gradient: LinearGradient(
                colors: [bottomColor, topColor],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
            ),
          ],
          showingTooltipIndicators: const [0],
        ),
    ];
  }

  SideTitleWidget _getTitles(
    BuildContext context,
    double value,
    TitleMeta meta,
  ) {
    final index = value.toInt();
    return SideTitleWidget(
      meta: meta,
      child: Text(
        index >= 0 && index < widget.xLabels.length
            ? widget.xLabels[index]
            : '',
        style: AppStatisticsTokens.chartAxisStyle.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
