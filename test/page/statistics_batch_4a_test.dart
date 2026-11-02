import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/enums/chart_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/statistic_data_model.dart';
import 'package:anx_reader/page/home_page/statistics_page.dart';
import 'package:anx_reader/providers/heatmap_data.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/statistic/heatmap_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-statistics-4a-');
    documentPath = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('date books error retries to a design-system empty state',
      (tester) async {
    final harness = _StatisticsHarness()..shouldFail = true;
    await _pumpStatistics(
      tester,
      ProviderScope(
        overrides: [
          statisticDataProvider.overrideWith(() => _FakeStatisticData(harness)),
        ],
        child: const SizedBox(height: 500, child: DateBooks()),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private statistic failure'), findsNothing);

    harness.shouldFail = false;
    await tester.tap(find.text('Retry'));
    await _pumpFrames(tester);

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('book loading error is understandable and retries to data',
      (tester) async {
    var loads = 0;
    Future<Book> loadBook(int id) async {
      loads++;
      if (loads == 1) throw StateError('private book failure');
      return _book();
    }

    await _pumpStatistics(
      tester,
      BookStatisticItem(bookId: 1, readingTime: 60, bookLoader: loadBook),
      textScaler: const TextScaler.linear(1.3),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private book failure'), findsNothing);

    await tester.tap(find.text('Retry'));
    await _pumpFrames(tester);

    expect(find.text('Book'), findsWidgets);
    expect(find.byType(AppErrorState), findsNothing);
    expect(loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting reading records requires dangerous confirmation',
      (tester) async {
    final harness = _StatisticsHarness()..includeBook = true;
    final deletedIds = <List<int>>[];
    await _pumpStatistics(
      tester,
      ProviderScope(
        overrides: [
          statisticDataProvider.overrideWith(() => _FakeStatisticData(harness)),
        ],
        child: SizedBox(
          height: 500,
          child: DateBooks(
            bookLoader: (_) async => _book(),
            onDelete: (ids) async => deletedIds.add(ids),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    final slidable = tester.widget<Slidable>(find.byType(Slidable));
    final action = slidable.startActionPane!.children.single as SlidableAction;
    action.onPressed!(tester.element(find.byType(Slidable)));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Will be deleted when leaving this page'), findsWidgets);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Records to be deleted'), findsNothing);

    action.onPressed!(tester.element(find.byType(Slidable)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(find.text('Records to be deleted'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(deletedIds, [
      [1],
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('heatmap exposes errors and retries to data', (tester) async {
    final harness = _HeatmapHarness()..shouldFail = true;
    await _pumpStatistics(
      tester,
      ProviderScope(
        overrides: [
          heatmapDataProvider.overrideWith(() => _FakeHeatmapData(harness)),
        ],
        child: const SizedBox(height: 400, child: HeatmapChart()),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private heatmap failure'), findsNothing);

    harness.shouldFail = false;
    await tester.tap(find.text('Retry'));
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('heatmap empty datasets show a design-system empty state',
      (tester) async {
    final harness = _HeatmapHarness()..isEmpty = true;
    await _pumpStatistics(
      tester,
      ProviderScope(
        overrides: [
          heatmapDataProvider.overrideWith(() => _FakeHeatmapData(harness)),
        ],
        child: const SizedBox(height: 400, child: HeatmapChart()),
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpStatistics(
  WidgetTester tester,
  Widget child, {
  TextScaler? textScaler,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: AppTheme.build(
        brightness: Brightness.light,
        seedColor: AppColors.defaultBrand,
      ),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, app) {
        if (textScaler == null) return app!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: app!,
        );
      },
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Book _book() => Book(
      id: 1,
      title: 'Book',
      coverPath: 'cover/missing.jpg',
      filePath: 'file/book.epub',
      lastReadPosition: '',
      readingPercentage: 0.25,
      author: 'Author',
      isDeleted: false,
      rating: 4,
      createTime: DateTime(2024),
      updateTime: DateTime(2024),
    );

class _StatisticsHarness {
  bool shouldFail = false;
  bool includeBook = false;
}

class _FakeStatisticData extends StatisticData {
  _FakeStatisticData(this.harness);

  final _StatisticsHarness harness;

  @override
  Future<StatisticDataModel> build() async {
    if (harness.shouldFail) throw StateError('private statistic failure');
    return StatisticDataModel(
      mode: ChartMode.month,
      isSelectingDay: false,
      date: DateTime(2024),
      readingTime: const [0],
      xLabels: const [''],
      bookReadingTime: harness.includeBook
          ? [
              {_book(): 60},
            ]
          : const [],
    );
  }
}

class _HeatmapHarness {
  bool shouldFail = false;
  bool isEmpty = false;
}

class _FakeHeatmapData extends HeatmapData {
  _FakeHeatmapData(this.harness);

  final _HeatmapHarness harness;

  @override
  Future<Map<DateTime, int>> build() async {
    if (harness.shouldFail) throw StateError('private heatmap failure');
    if (harness.isEmpty) return const {};
    return {DateTime(2024, 1, 1): 60};
  }
}
