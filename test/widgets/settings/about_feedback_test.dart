import 'about_test_utils.dart';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/widgets/settings/about.dart';
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

  testWidgets(
      'copy and developer unlock use localized Overlay success feedback',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: About()),
      ),
    );
    await tester.pumpAndSettle();
    await mockPubspec(tester, null);

    await tester.tap(find.byType(About));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(OutlinedButton), findsOneWidget);

    await mockPubspec(tester, 'name: anx_reader\nversion: 1.2.3+4\n');
    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();
    await tester.pumpAndSettle();

    final version = find.textContaining('1.2.3+4');
    await tester.tap(version);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(Overlay),
        matching: find.byIcon(Icons.check_circle_outline),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(Overlay),
        matching: find.text('已复制'),
      ),
      findsOneWidget,
    );

    for (var tap = 1; tap < 7; tap++) {
      await tester.tap(version);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(Prefs().developerOptionsEnabled, isTrue);
    expect(find.text('开发者选项已开启'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 2));
  });
}
