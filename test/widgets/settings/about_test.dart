import 'about_test_utils.dart';

import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/settings/about.dart';
import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> mockPubspec(WidgetTester tester, String? content) {
    return mockAboutPubspec(tester, content);
  }

  testWidgets('about load failure is recoverable and data fits at 1.3 scale',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mockPubspec(tester, null);
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
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: app!,
        ),
        home: const Scaffold(body: About()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byType(About));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text("Content couldn't be loaded. Try again."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await mockPubspec(tester, 'name: anx_reader\nversion: 1.2.3+4\n');
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.textContaining('1.2.3+4'), findsOneWidget);
    expect(find.text("Content couldn't be loaded. Try again."), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
