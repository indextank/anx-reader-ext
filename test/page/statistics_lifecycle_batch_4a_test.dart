import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/enums/chart_mode.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/models/book.dart';
import 'package:anx_reader/models/statistic_data_model.dart';
import 'package:anx_reader/page/home_page/statistics_page.dart';
import 'package:anx_reader/providers/dashboard_tiles_provider.dart';
import 'package:anx_reader/providers/statistic_data.dart';
import 'package:anx_reader/providers/total_reading_time.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
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
    tempDir = Directory.systemTemp.createTempSync('anx-statistics-lifecycle-');
    documentPath = tempDir.path;
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('internal scroll controller is disposed with the page',
      (tester) async {
    await _pumpStatisticPage(tester);
    final controller =
        tester.widget<ListView>(find.byType(ListView).first).controller!;

    await tester.pumpWidget(const SizedBox.shrink());

    expect(() => controller.addListener(_noop), throwsFlutterError);
  });

  testWidgets('external scroll controller is not disposed by the page',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await _pumpStatisticPage(tester, controller: controller);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(() => controller.addListener(_noop), returnsNormally);
  });

  testWidgets('responsive branch replacement does not commit pending deletion',
      (tester) async {
    final deletions = <List<int>>[];
    await _pumpStatisticPage(
      tester,
      includeBook: true,
      bookLoader: (_) async => _book(),
      onDelete: (ids) async => deletions.add(ids),
    );
    final slidable = tester.widget<Slidable>(find.byType(Slidable));
    final action = slidable.startActionPane!.children.single as SlidableAction;
    action.onPressed!(tester.element(find.byType(Slidable)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(deletions, isEmpty);

    tester.view.physicalSize = const Size(1000, 800);
    await tester.pump();

    expect(deletions, isEmpty);
    expect(find.text('Records to be deleted'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(deletions, [
      [1],
    ]);
  });
}

void _noop() {}

Future<void> _pumpStatisticPage(
  WidgetTester tester, {
  ScrollController? controller,
  bool includeBook = false,
  StatisticBookLoader? bookLoader,
  Future<void> Function(List<int> bookIds)? onDelete,
}) async {
  tester.view.physicalSize = const Size(500, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
      home: ProviderScope(
        overrides: [
          if (includeBook)
            statisticDataProvider.overrideWith(_BookStatisticData.new)
          else
            statisticDataProvider.overrideWith(_EmptyStatisticData.new),
          totalReadingTimeProvider.overrideWith(_ZeroTotalReadingTime.new),
          dashboardTilesProvider.overrideWith((ref) => _EmptyDashboardTiles()),
        ],
        child: StatisticPage(
          controller: controller,
          bookLoader: bookLoader,
          onDelete: onDelete,
        ),
      ),
    ),
  );
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _EmptyStatisticData extends StatisticData {
  @override
  Future<StatisticDataModel> build() async {
    return StatisticDataModel(
      mode: ChartMode.month,
      isSelectingDay: false,
      date: DateTime(2024),
      readingTime: const [0],
      xLabels: const [''],
      bookReadingTime: const [],
    );
  }
}

class _ZeroTotalReadingTime extends TotalReadingTime {
  @override
  Future<int> build() async => 0;
}

class _EmptyDashboardTiles extends DashboardTilesNotifier {
  _EmptyDashboardTiles() {
    state = const DashboardTilesState(
      savedTiles: [],
      workingTiles: [],
      hasUnsavedChanges: false,
      isEditing: false,
    );
  }
}

class _BookStatisticData extends StatisticData {
  @override
  Future<StatisticDataModel> build() async {
    return StatisticDataModel(
      mode: ChartMode.month,
      isSelectingDay: false,
      date: DateTime(2024),
      readingTime: const [0],
      xLabels: const [''],
      bookReadingTime: [
        {_book(): 60},
      ],
    );
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
