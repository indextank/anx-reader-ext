import 'dart:io';

import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/design_system/design_system.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/read_theme.dart';
import 'package:anx_reader/page/book_player/epub_player.dart';
import 'package:anx_reader/theme/app_colors.dart';
import 'package:anx_reader/theme/app_theme.dart';
import 'package:anx_reader/utils/get_path/get_base_path.dart';
import 'package:anx_reader/widgets/icon_and_text.dart';
import 'package:anx_reader/widgets/reading_page/combined_style_settings.dart';
import 'package:anx_reader/widgets/reading_page/panel_width.dart';
import 'package:anx_reader/widgets/reading_page/reading_tool_panel.dart';
import 'package:anx_reader/widgets/reading_page/style_panel_content_width.dart';
import 'package:anx_reader/widgets/settings/single_row_setting_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 样式面板两种展示形态的 golden 视觉对比（中文界面）。
///
/// 单独成文件：同一文件内只使用中文 locale，避免测试间切换 locale 时
/// 异步本地化加载造成的非确定性；golden 固定 1200x900、DPR=1。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String previousDocumentPath;

  setUp(() async {
    previousDocumentPath = documentPath;
    tempDir = Directory.systemTemp.createTempSync('anx-style-golden-');
    documentPath = tempDir.path;
    getFontDir().createSync();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs().initPrefs();
  });

  tearDown(() {
    documentPath = previousDocumentPath;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  List<ReadTheme> sampleThemes() => <ReadTheme>[
        ReadTheme(
          id: 1,
          backgroundColor: 'FFFDF6E3',
          textColor: 'FF333333',
          backgroundImagePath: '',
        ),
        ReadTheme(
          id: 2,
          backgroundColor: 'FF121212',
          textColor: 'FFCCCCCC',
          backgroundImagePath: '',
        ),
      ];

  Widget combinedBuilder(
    BuildContext context,
    List<ReadTheme> themes,
    ValueChanged<Widget> setCurrentPage,
  ) {
    return CombinedStyleSettings(
      themes: themes,
      epubPlayerKey: GlobalKey<EpubPlayerState>(),
      setCurrentPage: setCurrentPage,
      hideAppBarAndBottomBar: (_) {},
      themeInserter: (_) async => 1,
    );
  }

  Widget panel({
    required Future<List<ReadTheme>> Function() loader,
    bool sideContent = false,
    StylePanelLayoutPlan? plan,
  }) {
    return ReadingToolPanel(
      kind: ReadingToolPanelKind.style,
      notesBuilder: (_) => const SizedBox.shrink(),
      ttsBuilder: (_) => const SizedBox.shrink(),
      styleThemesLoader: loader,
      styleBuilder: combinedBuilder,
      sideContent: sideContent,
      styleLayoutPlan: plan,
      heightFactor: readingStylePanelHeightFactor,
    );
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
  }

  Future<void> pumpPopup(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          backgroundColor: const Color(0xFFDCDCD5),
          body: panel(loader: () async => sampleThemes()),
        ),
      ),
    );
    await pumpFrames(tester);
  }

  Future<void> pumpSide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(
          brightness: Brightness.light,
          seedColor: AppColors.defaultBrand,
        ),
        locale: const Locale('zh'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) {
            final plan = resolveStylePanelLayout(
              context,
              availableWidth: 1200,
              maxWidth: panelMaxWidthFor(availableWidth: 1200),
            );
            return Scaffold(
              backgroundColor: const Color(0xFFDCDCD5),
              body: Row(
                children: [
                  const Expanded(child: SizedBox.shrink()),
                  SizedBox(
                    width: plan.width,
                    height: 900,
                    child: panel(
                      loader: () async => sampleThemes(),
                      sideContent: true,
                      plan: plan,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await pumpFrames(tester);
  }

  int renderedLineCount(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder.first);
    if (paragraph.text.toPlainText().isEmpty) return 1;
    // 测试字体缺少中文字形时 getBoxesForSelection 可能为空；
    // 复用同段落样式/宽度重新 layout，用行度量统计真实行数。
    final painter = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      maxLines: paragraph.maxLines,
      ellipsis: paragraph.overflow == TextOverflow.ellipsis ? '…' : null,
      textHeightBehavior: paragraph.textHeightBehavior,
      locale: paragraph.locale,
    )..layout(maxWidth: paragraph.size.width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines <= 0 ? 1 : lines;
  }

  void expectTextFullyVisible(
    WidgetTester tester,
    Finder finder,
    String title,
  ) {
    final paragraph = tester.renderObject<RenderParagraph>(finder.first);
    if (paragraph.text.toPlainText().isEmpty) return;
    final full = TextPainter(
      text: paragraph.text,
      textDirection: paragraph.textDirection,
      textAlign: paragraph.textAlign,
      textScaler: paragraph.textScaler,
      locale: paragraph.locale,
    )..layout();
    final fullWidth = full.width;
    full.dispose();
    expect(paragraph.size.width + 0.5, greaterThanOrEqualTo(fullWidth),
        reason: '设置项「$title」不得截断/省略');
  }

  void expectEverySettingSingleLine(WidgetTester tester) {
    final titles = <String>{
      for (final tile in tester.widgetList<SingleRowSettingTile>(
        find.byType(SingleRowSettingTile),
      ))
        tile.title,
      for (final tile
          in tester.widgetList<AppListTile>(find.byType(AppListTile)))
        tile.title,
      for (final row in tester.widgetList<IconAndText>(
        find.byType(IconAndText),
      ))
        row.text,
    };
    expect(titles, isNotEmpty);
    for (final title in titles) {
      final finder = find.text(title);
      if (finder.evaluate().isEmpty) continue;
      expect(renderedLineCount(tester, finder), 1,
          reason: '中文设置项「$title」必须单行完整展示');
      expectTextFullyVisible(tester, finder, title);
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('zh popup every setting is single line without overflow',
      (tester) async {
    await pumpPopup(tester);
    expectEverySettingSingleLine(tester);
  });

  testWidgets('popup form golden', (tester) async {
    await pumpPopup(tester);
    await expectLater(
      find.byType(ReadingToolPanel),
      matchesGoldenFile('goldens/style_panel_popup.png'),
    );
  });

  testWidgets('side form golden', (tester) async {
    await pumpSide(tester);
    await expectLater(
      find.byType(ReadingToolPanel),
      matchesGoldenFile('goldens/style_panel_side.png'),
    );
  });
}
