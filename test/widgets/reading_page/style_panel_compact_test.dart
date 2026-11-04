import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/main.dart' show navigatorKey;
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/theme/style_panel_tokens.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/widgets/reading_page/combined_style_settings.dart';

/// 面板紧凑化与文字样式统一回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-style-panel-compact-');
    documentPath = tempDir.path;
    getFontDir().createSync();
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpPanel(
    WidgetTester tester, {
    Size size = const Size(420, 900),
    TextScaler? textScaler,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: AppTheme.build(
          brightness: brightness,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: textScaler ?? TextScaler.noScaling,
          ),
          child: Scaffold(
            body: CombinedStyleSettings(
              themes: const [],
              epubPlayerKey: GlobalKey<EpubPlayerState>(),
              setCurrentPage: (_) {},
              hideAppBarAndBottomBar: (_) {},
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('section titles share one unified style', (tester) async {
    await pumpPanel(tester);
    final context = tester.element(find.text('其他').first);
    final expected = StylePanelTokens.sectionTitle(context);
    for (final title in ['样式', '阅读', '其他']) {
      final titles = find.text(title).evaluate();
      expect(titles, isNotEmpty, reason: title);
      for (final e in titles) {
        final widget = e.widget as Text;
        expect(
          widget.style?.fontSize,
          expected.fontSize,
          reason: '$title 字号应与分组标题令牌一致',
        );
        expect(
          widget.style?.fontWeight,
          expected.fontWeight,
          reason: '$title 字重应与分组标题令牌一致',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('panel no longer renders redundant full-width dividers',
      (tester) async {
    await pumpPanel(tester);
    final dividers = find.byType(Divider).evaluate();
    // 分组间已由 sectionGap 取代；剩余 Divider 属于内容语义
    // （如页眉/页脚分隔），数量应少于旧布局的每分组两条。
    expect(dividers.length, lessThan(6));
    expect(tester.takeException(), isNull);
  });

  for (final variant in [
    (size: const Size(360, 800), scale: 1.3),
    (size: const Size(420, 900), scale: 1.5),
  ]) {
    testWidgets(
        'no overflow at ${variant.size.width}px and ${variant.scale}x scale',
        (tester) async {
      await pumpPanel(
        tester,
        size: variant.size,
        textScaler: TextScaler.linear(variant.scale),
      );
      expect(tester.takeException(), isNull, reason: '紧凑面板在窄屏大字号下不得溢出');
    });
  }

  testWidgets('dark theme keeps unified section style', (tester) async {
    await pumpPanel(tester, brightness: Brightness.dark);
    final context = tester.element(find.text('阅读').first);
    final expected = StylePanelTokens.sectionTitle(context);
    final widget = find.text('其他').evaluate().first.widget as Text;
    expect(widget.style?.fontSize, expected.fontSize);
    expect(tester.takeException(), isNull);
  });
}
