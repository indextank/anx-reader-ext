import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/chart_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/statistic_data_model.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/theme/app_motion.dart';
import 'package:anx_reader/theme/app_statistics_tokens.dart';
import 'package:anx_reader/utils/date/week_of_year.dart';
import 'package:anx_reader/widgets/common/anx_segmented_button.dart';
import 'package:anx_reader/widgets/statistic/heatmap_chart.dart';
import 'package:anx_reader/widgets/statistic/statistic_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsx_plus/iconsx_plus.dart';

class StatisticCard extends ConsumerWidget {
  const StatisticCard({super.key});

  void _changeDate(
    WidgetRef ref,
    bool isPlus,
    ChartMode currentMode,
    DateTime currentDate,
  ) {
    final durationMap = {
      ChartMode.week: () => isPlus
          ? currentDate.add(const Duration(days: 7))
          : currentDate.subtract(const Duration(days: 7)),
      ChartMode.month: () => DateTime(
            currentDate.year,
            isPlus ? currentDate.month + 1 : currentDate.month - 1,
          ),
      ChartMode.year: () => DateTime(
            isPlus ? currentDate.year + 1 : currentDate.year - 1,
            currentDate.month,
          ),
    };

    var newDate = durationMap[currentMode]!();
    if (newDate.isAfter(DateTime.now())) {
      newDate = DateTime.now();
    } else if (newDate.isBefore(DateTime(2024))) {
      return;
    }

    ref.read(statisticDataProvider.notifier).setDate(newDate);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statisticData = ref.watch(statisticDataProvider);
    final segmentButtonItems = <SegmentButtonItem<ChartMode>>[
      SegmentButtonItem(
        value: ChartMode.week,
        icon: const Icon(Icons.calendar_view_week),
        label: L10n.of(context).statisticWeek,
      ),
      SegmentButtonItem(
        value: ChartMode.month,
        icon: const Icon(Icons.calendar_month),
        label: L10n.of(context).statisticMonth,
      ),
      SegmentButtonItem(
        value: ChartMode.year,
        icon: const Icon(Icons.calendar_today),
        label: L10n.of(context).statisticYear,
      ),
      SegmentButtonItem(
        value: ChartMode.heatmap,
        icon: const Icon(Icons.grid_view_rounded),
        label: L10n.of(context).statisticAll,
      ),
    ];

    Widget segmentButton(StatisticDataModel data) => Row(
          children: [
            Expanded(
              child: AnxSegmentedButton<ChartMode>(
                segments: segmentButtonItems,
                selected: {data.mode},
                onSelectionChanged: (newSelection) {
                  ref
                      .read(statisticDataProvider.notifier)
                      .setMode(newSelection.first);
                },
              ),
            ),
          ],
        );

    Widget barChart(StatisticDataModel data) => SizedBox(
          height: AppStatisticsTokens.chartHeight,
          child: Column(
            children: [
              Row(
                children: [
                  AppIconButton(
                    onPressed: () =>
                        _changeDate(ref, false, data.mode, data.date),
                    icon: EvaIcons.arrow_ios_back_outline,
                  ),
                  const Spacer(),
                  AppButton(
                    variant: AppButtonVariant.text,
                    onPressed: () async {
                      final newDate = await showDatePicker(
                        context: context,
                        initialEntryMode: DatePickerEntryMode.calendarOnly,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                        initialDate: data.date,
                      );
                      if (newDate != null) {
                        ref
                            .read(statisticDataProvider.notifier)
                            .setDate(newDate);
                      }
                    },
                    label: data.mode == ChartMode.week
                        ? weekOfYear(data.date)
                        : data.mode == ChartMode.month
                            ? '${data.date.year}.${data.date.month}'
                            : data.date.year.toString(),
                  ),
                  const Spacer(),
                  AppIconButton(
                    onPressed: () =>
                        _changeDate(ref, true, data.mode, data.date),
                    icon: EvaIcons.arrow_ios_forward_outline,
                  ),
                ],
              ),
              const SizedBox(height: AppStatisticsTokens.contentSpacing),
              Expanded(
                child: StatisticChart(
                  readingTime: data.readingTime,
                  xLabels: data.xLabels,
                ),
              ),
            ],
          ),
        );

    return AnimatedSize(
      duration: AppMotion.tokens.emphasis,
      curve: Curves.easeOutBack,
      alignment: Alignment.topCenter,
      child: AppCard(
        padding: AppStatisticsTokens.cardPadding,
        child: AppAsyncValue<StatisticDataModel>(
          value: statisticData,
          onRetry: () async => ref.invalidate(statisticDataProvider),
          dataBuilder: (context, data) => Column(
            children: [
              const SizedBox(height: AppStatisticsTokens.contentSpacing),
              segmentButton(data),
              const SizedBox(height: AppStatisticsTokens.contentSpacing),
              if (data.mode == ChartMode.heatmap) const HeatmapChart(),
              if (data.mode != ChartMode.heatmap) barChart(data),
            ],
          ),
        ),
      ),
    );
  }
}
