import 'dart:convert';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/page/changelog_screen.dart';
import 'package:anx_reader/widgets/markdown/styled_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design_system/design_system_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  Future<void> mockChangelog(
    WidgetTester tester,
    String? content,
  ) async {
    const channel = 'flutter/assets';
    rootBundle.evict('assets/CHANGELOG.md');
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(channel, (
      message,
    ) async {
      if (content == null) return null;
      final bytes = Uint8List.fromList(utf8.encode(content));
      return ByteData.sublistView(bytes);
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        channel,
        null,
      );
    });
  }

  testWidgets('failed changelog load keeps fallback content and can retry',
      (tester) async {
    await mockChangelog(tester, null);
    await pumpDesignSystem(
      tester,
      const ChangelogScreen(
        lastVersion: '1.2.2',
        currentVersion: '1.2.3+4',
        onComplete: _noop,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    expect(find.text("Content couldn't be loaded. Try again."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(StyledMarkdown), findsOneWidget);

    await mockChangelog(
      tester,
      '## 1.2.3\n- Added reliable sync\n- 添加可靠同步\n',
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Content couldn't be loaded. Try again."), findsNothing);
    expect(find.byType(StyledMarkdown), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changelog data and actions fit at 1.3 text scale',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await mockChangelog(
      tester,
      '## 1.2.3\n- Added reliable sync\n- 添加可靠同步\n',
    );

    await pumpDesignSystem(
      tester,
      const ChangelogScreen(
        lastVersion: '1.2.2',
        currentVersion: '1.2.3+4',
        onComplete: _noop,
      ),
      textScaler: const TextScaler.linear(1.3),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(StyledMarkdown), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}
