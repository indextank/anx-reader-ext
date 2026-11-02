import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/providers/statictics_summary_value.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/statistic/dashboard_tiles/tiles/books_total_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('dashboard tile error retries within its original layout',
      (tester) async {
    final harness = _SummaryHarness()..shouldFail = true;
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
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: ProviderScope(
            overrides: [
              StaticticsSummaryValueProvider(StatisticType.totalBooks)
                  .overrideWith(() => _FakeSummary(harness)),
            ],
            child: Scaffold(
              body: SizedBox(
                width: 200,
                height: 150,
                child: Consumer(
                  builder: (context, ref, _) =>
                      const BooksTotalTile().buildTile(context, ref),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(AppErrorState), findsOneWidget);
    expect(find.textContaining('private tile failure'), findsNothing);

    harness.shouldFail = false;
    await tester.tap(find.byTooltip('Retry'));
    await _pumpFrames(tester);

    expect(find.text('12'), findsOneWidget);
    expect(find.byType(AppErrorState), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 12; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _SummaryHarness {
  bool shouldFail = false;
}

class _FakeSummary extends StaticticsSummaryValue {
  _FakeSummary(this.harness);

  final _SummaryHarness harness;

  @override
  Future<int> build(StatisticType type) async {
    if (harness.shouldFail) throw StateError('private tile failure');
    return 12;
  }
}
