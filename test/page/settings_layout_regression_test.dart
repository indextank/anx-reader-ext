import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/models/md5_statistics.dart';
import 'package:anx_reader/page/settings_page/advanced.dart';
import 'package:anx_reader/page/settings_page/search_engines.dart';
import 'package:anx_reader/page/settings_page/subpage/chapter_split_rules_page.dart';
import 'package:anx_reader/page/settings_page/subpage/log_page.dart';
import 'package:anx_reader/page/settings_page/sync.dart';
import 'package:anx_reader/page/settings_page/translate.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => switch (call.method) {
        'getApplicationDocumentsDirectory' => '/tmp/anx-layout-documents',
        'getApplicationSupportDirectory' => '/tmp/anx-layout-support',
        _ => null,
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  void useCompactScaledView(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('search engine dialog saves preferences at 1.3 scale',
      (tester) async {
    useCompactScaledView(tester);
    await pumpDesignSystem(
      tester,
      const SearchEnginesSetting(),
      textScaler: const TextScaler.linear(1.3),
    );

    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Custom Engine'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(AppTextField).at(0),
      'Example engine',
    );
    await tester.enterText(
      find.byType(AppTextField).at(1),
      'https://example.com/search?q={query}',
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(Prefs().customSearchEngines.single.name, 'Example engine');
    expect(find.byType(AppDialog), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('chapter rule editor saves a valid custom rule at 1.3 scale',
      (tester) async {
    useCompactScaledView(tester);
    await pumpDesignSystem(
      tester,
      const ChapterSplitRulesPage(),
      textScaler: const TextScaler.linear(1.3),
    );

    final addButton = find.text('Add custom rule').last;
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.tap(addButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(AppTextField).at(1),
      r'^Chapter\s+\d+.*$',
    );
    await tester.pump();
    expect(
      tester.widget<AppSubmitButton>(find.byType(AppSubmitButton)).disabled,
      isFalse,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(Prefs().customSearchEngines, isEmpty);
    expect(Prefs().chapterSplitCustomRules.single.name, 'New custom rule');
    expect(find.byType(ChapterSplitRuleEditorPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final entry in <String, Widget>{
    'advanced': AdvancedSetting(
      loadMd5Statistics: () async => MD5Statistics(
        totalBooks: 0,
        booksWithMd5: 0,
        booksWithoutMd5: 0,
        localFilesCount: 0,
        localFilesWithoutMd5: 0,
      ),
    ),
    'translate': const TranslateSetting(),
    'sync': const ProviderScope(child: SyncSetting()),
    'log': const LogPage(),
  }.entries) {
    testWidgets('${entry.key} settings fits compact 1.3 scale', (tester) async {
      useCompactScaledView(tester);
      await pumpDesignSystem(
        tester,
        entry.value,
        textScaler: const TextScaler.linear(1.3),
      );
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  }
}
