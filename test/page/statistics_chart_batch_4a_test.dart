import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/widgets/statistic/book_reading_chart.dart';
import 'package:anx_reader/widgets/statistic/statistic_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  testWidgets('empty chart data shows an empty state instead of reducing',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const ProviderScope(
        child: SizedBox(
          height: 300,
          child: StatisticChart(readingTime: [], xLabels: []),
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty book reading values show empty state and data keeps chart',
      (tester) async {
    await pumpDesignSystem(
      tester,
      const SizedBox(
        height: 300,
        child: BookReadingChart(
          cumulativeValues: [],
          dailySeconds: [],
          dates: [],
        ),
      ),
      textScaler: const TextScaler.linear(1.3),
    );

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);

    await pumpDesignSystem(
      tester,
      SizedBox(
        height: 300,
        child: BookReadingChart(
          cumulativeValues: const [0, 60],
          dailySeconds: const [0, 60],
          dates: [DateTime(2024, 1, 1), DateTime(2024, 1, 2)],
        ),
      ),
    );

    expect(find.byType(AppEmptyState), findsNothing);
    expect(find.byType(LineChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
