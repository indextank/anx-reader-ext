import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/utils/date/convert_seconds.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class BookReadingChart extends StatefulWidget {
  const BookReadingChart({
    super.key,
    required this.cumulativeValues,
    required this.dailySeconds,
    required this.dates,
    this.maxY,
  });

  final List<int> cumulativeValues;
  final List<int> dailySeconds;
  final List<DateTime> dates;
  final double? maxY;

  @override
  State<BookReadingChart> createState() => _BookReadingChartState();
}

class _BookReadingChartState extends State<BookReadingChart> {
  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final formatter = DateFormat('M/d');
    final dataLength = widget.cumulativeValues.length;
    if (dataLength == 0) return const AppEmptyState();
    final effectiveMaxY = widget.maxY ??
        widget.cumulativeValues.reduce((a, b) => a > b ? a : b) *
            AppStatisticsTokens.chartMaxYFactor;
    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.transparent,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.toInt();
                if (index >= 0 && index < dataLength) {
                  final label = formatter.format(widget.dates[index]);
                  final daily = widget.dailySeconds[index];
                  return LineTooltipItem(
                    '$label · ${convertSeconds(daily)}',
                    AppStatisticsTokens.chartTooltipStyle.copyWith(
                      color: primaryColor,
                    ),
                  );
                }
                return null;
              }).toList();
            },
          ),
        ),
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: dataLength > 0 ? (dataLength - 1).toDouble() : 0,
        minY: 0,
        maxY: effectiveMaxY <= 0
            ? AppStatisticsTokens.chartFallbackMaxY
            : effectiveMaxY,
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              dataLength,
              (index) => FlSpot(
                index.toDouble(),
                widget.cumulativeValues[index].toDouble(),
              ),
            ),
            isCurved: true,
            color: primaryColor,
            barWidth: AppStatisticsTokens.chartLineWidth,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  primaryColor.withAlpha(AppStatisticsTokens.chartAreaAlpha),
                  AppColors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
