import 'dart:async';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/md5_statistics.dart';
import 'package:anx_reader/page/settings_page/advanced.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  testWidgets('proxy test reports start, success, and deduplicates pending',
      (tester) async {
    final pending = Completer<bool>();
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      AdvancedSetting(
        loadMd5Statistics: _emptyStatistics,
        testProxy: (host, port, testUrl) {
          attempts++;
          expect(host, '127.0.0.1');
          expect(port, 7890);
          expect(testUrl, 'https://example.com');
          return pending.future;
        },
      ),
    );
    await _openProxyDialog(tester);
    await tester.tap(find.text('Test Connection'));
    await tester.pump();

    expect(find.text('Testing...'), findsOneWidget);
    expect(attempts, 1);
    await tester.tap(find.text('Test Connection'));
    await tester.pump();
    expect(attempts, 1);

    pending.complete(true);
    await tester.pump();
    await tester.pump();

    expect(find.text('Connection Successful'), findsOneWidget);
    expect(find.text('Connection Failed'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('proxy failure stays inline and retry reports success',
      (tester) async {
    var attempts = 0;
    await pumpDesignSystem(
      tester,
      AdvancedSetting(
        loadMd5Statistics: _emptyStatistics,
        testProxy: (host, port, testUrl) async {
          attempts++;
          return attempts > 1;
        },
      ),
    );
    await _openProxyDialog(tester);
    await tester.tap(find.text('Test Connection'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Connection Failed'), findsOneWidget);
    expect(attempts, 1);

    await tester.tap(find.descendant(
      of: find.byType(AppDialog),
      matching: find.text('Retry'),
    ));
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.text('Connection Successful'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });
}

Future<MD5Statistics> _emptyStatistics() async {
  return MD5Statistics(
    totalBooks: 0,
    booksWithMd5: 0,
    booksWithoutMd5: 0,
    localFilesCount: 0,
    localFilesWithoutMd5: 0,
  );
}

Future<void> _openProxyDialog(WidgetTester tester) async {
  await tester.ensureVisible(find.text('HTTP Proxy Config'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('HTTP Proxy Config'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(AppTextField).at(0), '127.0.0.1');
  await tester.enterText(find.byType(AppTextField).at(1), '7890');
  await tester.enterText(
    find.byType(AppTextField).at(2),
    'https://example.com',
  );
}
